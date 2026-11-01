import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../core/models.dart';

class NetworkSample {
  const NetworkSample(
    this.time, {
    this.tcpMs,
    this.httpsMs,
    this.error,
    this.addresses = const [],
  });
  final DateTime time;
  final double? tcpMs, httpsMs;
  final String? error;
  final List<String> addresses;
  Map<String, Object?> toJson() => {
    'time': time.toIso8601String(),
    'tcpMs': tcpMs,
    'httpsMs': httpsMs,
    'error': error,
    'addresses': addresses,
  };
}

class NetworkStats {
  NetworkStats(List<NetworkSample> samples) {
    final values = samples
        .where((s) => s.tcpMs != null)
        .map((s) => s.tcpMs!)
        .toList();
    mean = values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
    jitter = values.length < 2
        ? null
        : List.generate(
                values.length - 1,
                (i) => (values[i + 1] - values[i]).abs(),
              ).reduce((a, b) => a + b) /
              (values.length - 1);
    failurePercent = samples.isEmpty
        ? null
        : samples.where((s) => s.tcpMs == null).length * 100 / samples.length;
  }
  late final double? mean, jitter, failurePercent;
}

class NetworkService {
  Uri endpoint(String input) {
    final uri = Uri.parse(input);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Enter an HTTPS endpoint without credentials.',
      );
    }
    return uri;
  }

  Future<NetworkSample> measure(
    Uri uri,
    Cancellation cancel, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    Socket? socket;
    final client = HttpClient()..connectionTimeout = timeout;
    cancel.onCancel(() {
      socket?.destroy();
      client.close(force: true);
    });
    double? tcp;
    final timer = Stopwatch();
    try {
      cancel.check();
      final addresses = await InternetAddress.lookup(uri.host).timeout(timeout);
      cancel.check();
      timer.start();
      socket = await Socket.connect(
        addresses.first,
        uri.port,
        timeout: timeout,
      );
      tcp = timer.elapsedMicroseconds / 1000;
      socket.destroy();
      timer.reset();
      cancel.check();
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      final https = timer.elapsedMicroseconds / 1000;
      // Header latency only; do not download an unbounded response body.
      client.close(force: true);
      return NetworkSample(
        DateTime.now(),
        tcpMs: tcp,
        httpsMs: https,
        addresses: addresses.map((a) => a.address).toList(),
        error: response.statusCode >= 400
            ? 'HTTP ${response.statusCode}'
            : null,
      );
    } on Cancelled {
      rethrow;
    } on TimeoutException {
      return NetworkSample(DateTime.now(), tcpMs: tcp, error: 'Timeout');
    } on SocketException catch (e) {
      return NetworkSample(
        DateTime.now(),
        tcpMs: tcp,
        error: 'DNS or socket: ${e.message}',
      );
    } on HandshakeException {
      return NetworkSample(
        DateTime.now(),
        tcpMs: tcp,
        error: 'TLS handshake failed',
      );
    } catch (e) {
      cancel.check();
      return NetworkSample(DateTime.now(), tcpMs: tcp, error: e.toString());
    } finally {
      timer.stop();
      socket?.destroy();
      client.close(force: true);
    }
  }

  Stream<Map<String, Object?>> throughput(
    Uri uri, {
    required bool upload,
    required int limit,
    required Cancellation cancel,
  }) async* {
    if (limit < 1024 || limit > 64 * 1024 * 1024) {
      throw ArgumentError('Transfer limit must be 1 KiB–64 MiB');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..autoUncompress = false;
    cancel.onCancel(() => client.close(force: true));
    final timer = Stopwatch()..start();
    int transferred = 0;
    try {
      final request = await (upload ? client.postUrl(uri) : client.getUrl(uri))
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (upload) {
        request.contentLength = limit;
        final chunk = List<int>.filled(64 * 1024, 0);
        while (transferred < limit) {
          cancel.check();
          final length = min(chunk.length, limit - transferred);
          request.add(chunk.sublist(0, length));
          await request.flush().timeout(const Duration(seconds: 10));
          transferred += length;
          yield {
            'bytes': transferred,
            'seconds': timer.elapsedMilliseconds / 1000,
          };
        }
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Endpoint returned HTTP ${response.statusCode}');
      }
      if (!upload) {
        await for (final chunk in response.timeout(
          const Duration(seconds: 10),
        )) {
          cancel.check();
          transferred += min(chunk.length, limit - transferred);
          yield {
            'bytes': transferred,
            'seconds': timer.elapsedMilliseconds / 1000,
          };
          if (transferred >= limit) break;
        }
      }
      cancel.check();
      yield {
        'bytes': transferred,
        'seconds': timer.elapsedMicroseconds / 1e6,
        'complete': true,
        'mbps': transferred * 8 / max(timer.elapsedMicroseconds, 1),
      };
    } finally {
      client.close(force: true);
      timer.stop();
    }
  }

  Stream<Map<String, Object?>> scanLan(
    String localIp,
    Cancellation cancel,
  ) async* {
    if (!privateV4(localIp) || !(await localAddresses()).contains(localIp)) {
      throw ArgumentError('Choose an assigned private IPv4 interface.');
    }
    final prefix = localIp.substring(0, localIp.lastIndexOf('.'));
    int completed = 0;
    // Explicit /24 only, eight simultaneous hosts, one TCP service probe per host.
    for (int base = 1; base <= 254; base += 8) {
      cancel.check();
      final results = await Future.wait(
        List.generate(min(8, 255 - base), (offset) async {
          final ip = '$prefix.${base + offset}';
          final timer = Stopwatch()..start();
          Socket? socket;
          try {
            socket = await Socket.connect(
              ip,
              443,
              timeout: const Duration(milliseconds: 400),
            );
            return <String, Object?>{
              'ip': ip,
              'ms': timer.elapsedMicroseconds / 1000,
            };
          } on SocketException {
            return <String, Object?>{};
          } finally {
            socket?.destroy();
          }
        }),
      );
      for (final result in results) {
        cancel.check();
        completed++;
        yield {...result, 'progress': completed / 254};
      }
    }
  }
}
