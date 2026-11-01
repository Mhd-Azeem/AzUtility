import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/models.dart';
import '../../core/platform/native_bridge.dart';

class DeviceService {
  const DeviceService(this.native);
  final NativeBridge native;
  Future<List<Metric>> snapshot() async => [
    Metric('Operating system', Platform.operatingSystemVersion),
    Metric('Logical processors', '${Platform.numberOfProcessors}'),
    Metric('Application resident memory', bytes(ProcessInfo.currentRss)),
    ...await native.snapshot(),
  ];

  Stream<Map<String, Object?>> benchmark(
    String kind,
    Cancellation cancel,
  ) async* {
    final timer = Stopwatch()..start();
    if (kind == 'CPU') {
      int work = 0, checksum = 0;
      for (int i = 0; i < 20; i++) {
        cancel.check();
        final int chunkChecksum = await Isolate.run<int>(_cpuChunk);
        checksum = (checksum + chunkChecksum) & 0x7fffffff;
        work += 500000;
        yield {
          'progress': (i + 1) / 20,
          'iterations': work,
          'checksum': checksum,
          'seconds': timer.elapsedMicroseconds / 1e6,
        };
      }
      yield {
        'progress': 1.0,
        'complete': true,
        'iterations': work,
        'checksum': checksum,
        'seconds': timer.elapsedMicroseconds / 1e6,
        'definition':
            '20 bounded integer arithmetic chunks; iterations per second, no cross-device score',
      };
    } else if (kind == 'Memory') {
      int checksum = 0;
      for (int i = 0; i < 8; i++) {
        cancel.check();
        final allocation = await Isolate.run(_memoryChunk);
        for (int offset = 0; offset < allocation.length; offset += 4096) {
          checksum += allocation[offset];
        }
        yield {
          'progress': (i + 1) / 8,
          'seconds': timer.elapsedMicroseconds / 1e6,
        };
      }
      yield {
        'complete': true,
        'allocatedMiB': 64,
        'peakChunkMiB': 8,
        'checksum': checksum,
        'seconds': timer.elapsedMicroseconds / 1e6,
      };
    } else {
      final directory = await getTemporaryDirectory();
      final file = File(
        p.join(
          directory.path,
          'az-benchmark-${DateTime.now().microsecondsSinceEpoch}.tmp',
        ),
      );
      const size = 16 * 1024 * 1024;
      final data = Uint8List(256 * 1024);
      final random = Random();
      for (int i = 0; i < data.length; i++) {
        data[i] = random.nextInt(256);
      }
      try {
        final output = await file.open(mode: FileMode.writeOnly);
        timer.reset();
        try {
          for (int i = 0; i < 64; i++) {
            cancel.check();
            await output.writeFrom(data);
            yield {'progress': (i + 1) / 128};
          }
          await output.flush();
        } finally {
          await output.close();
        }
        final writeSeconds = max(timer.elapsedMicroseconds / 1e6, 0.000001);
        timer.reset();
        int read = 0;
        await for (final chunk in file.openRead()) {
          cancel.check();
          read += chunk.length;
          yield {'progress': 0.5 + read / size / 2};
        }
        yield {
          'complete': true,
          'bytes': size,
          'writeMiBs': 16 / writeSeconds,
          'readMiBs': 16 / max(timer.elapsedMicroseconds / 1e6, 0.000001),
          'definition': '16 MiB temporary file; OS cache affects results',
        };
      } finally {
        if (await file.exists()) await file.delete();
      }
    }
  }

  static int _cpuChunk() {
    int value = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    for (int i = 0; i < 500000; i++) {
      value = (value * 1664525 + 1013904223) & 0x7fffffff;
    }
    return value;
  }

  static Uint8List _memoryChunk() {
    final data = Uint8List(8 * 1024 * 1024);
    for (int i = 0; i < data.length; i += 4096) {
      data[i] = i % 251;
    }
    return data;
  }
}
