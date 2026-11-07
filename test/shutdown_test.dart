import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/data/services/notebook_store.dart';
import 'package:penna/main.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/local/local_model.dart';
import 'package:penna/ui/features/poses/pose_library.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  testWidgets('关窗在销毁原生窗口前保存两份工作台、布局和排队的配置', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('penna_close');
    final config = tempConfig();
    final board = LayoutBoard(dir: dir);
    final vm = StudioViewModel(
      config: config,
      streamChat: (_) => const Stream.empty(),
      layout: board,
      saveFile: File('${dir.path}/workspace.json'),
    );
    final layoutChat = StudioViewModel(
      config: config,
      streamChat: (_) => const Stream.empty(),
      layout: board,
      layoutOnly: true,
      saveFile: File('${dir.path}/layout_chat.json'),
    );
    final local = LocalModel(streamChat: (_) => const Stream.empty());
    var destroyed = 0;
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'destroy') {
        destroyed++;
        expect(File('${dir.path}/workspace.json').existsSync(), isTrue);
        expect(File('${dir.path}/layout_chat.json').existsSync(), isTrue);
        expect(File('${dir.path}/layout.json').existsSync(), isTrue);
        expect(
          jsonDecode(config.file.readAsStringSync())['fontLatin'],
          'close-test',
        );
      }
      return false;
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(config.flushed);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      layoutChat.dispose();
      board.dispose();
      local.dispose();
      dir.deleteSync(recursive: true);
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
        poses: PoseLibrary(),
      ),
    );
    await tester.pumpAndSettle();
    vm.setText(0, 'close-now');
    board.setSummary(caption: 'close-layout');
    await tester.runAsync(() async {
      config.update(config.config.copyWith(fontLatin: 'close-test'));
      final dynamic state = tester.state(find.byType(PennaApp));
      await Future.wait<void>([state.onWindowClose(), state.onWindowClose()]);
    });
    expect(destroyed, 1);
    expect(
      jsonDecode(
        File('${dir.path}/workspace.json').readAsStringSync(),
      )['pages'][0]['blocks'][0]['text'],
      'close-now',
    );
    expect(
      jsonDecode(
        File('${dir.path}/layout.json').readAsStringSync(),
      )['layout']['caption'],
      'close-layout',
    );
  });
}
