import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/data/services/notebook_store.dart';
import 'package:penna/main.dart';
import 'package:penna/ui/features/local/local_model.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('native minimum window at scale $scale', (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (_) async => false,
      );
      final config = tempConfig();
      await tester.runAsync(() async {
        config.update(AppConfig(uiScale: scale));
        await config.flushed();
      });
      final vm = StudioViewModel(
        config: config,
        streamChat: (_) => const Stream.empty(),
      );
      final layoutChat = StudioViewModel(
        config: config,
        streamChat: (_) => const Stream.empty(),
      );
      final local = LocalModel(streamChat: (_) => const Stream.empty());
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        layoutChat.dispose();
        local.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        );
      });
      await tester.pumpWidget(
        PennaApp(
          config: config,
          skills: tempSkills(),
          vm: vm,
          layoutChat: layoutChat,
          archive: ArchiveStore(),
          notebooks: NotebookStore(),
          local: local,
        ),
      );
      await tester.pumpAndSettle();
      final exception = tester.takeException();
      expect(exception, isNull);
    });
  }
}
