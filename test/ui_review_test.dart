import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:az_utility/app/az_utility_app.dart';
import 'package:az_utility/app/controller.dart';
import 'package:az_utility/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(1360, 900), const Size(390, 844)]) {
    testWidgets('dashboard layout at ${size.width.toInt()} pixels', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      if (Platform.environment['AZ_UI_PREVIEW_DIR'] != null) {
        await tester.runAsync(() async {
          final font = File(
            '../toolchain/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
          );
          if (await font.exists()) {
            final loader = FontLoader('Roboto')
              ..addFont(font.readAsBytes().then(ByteData.sublistView));
            await loader.load();
          }
          final icon = File(
            '../toolchain/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          );
          if (await icon.exists()) {
            final loader = FontLoader('MaterialIcons')
              ..addFont(icon.readAsBytes().then(ByteData.sublistView));
            await loader.load();
          }
        });
      }
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      await tester.runAsync(() => container.read(controllerProvider).ready);
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: key, child: const AzUtilityApp()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your system. In focus.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['AZ_UI_PREVIEW_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File(
            '$directory/dashboard-${size.width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await database.close();
    });
  }
}
