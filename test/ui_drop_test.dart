import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/ui/core/gallery.dart';
import 'package:penna/ui/core/image_drop.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/attachment_view.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/features/studio/side_chat.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

class _PendingFile implements File {
  _PendingFile(this.path);

  @override
  final String path;
  final contents = Completer<Uint8List>();
  @override
  Uri get uri => Uri.file(path);
  @override
  Future<int> length() async => 1;
  @override
  Future<Uint8List> readAsBytes() => contents.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _drop(WidgetTester tester, Offset at) async {
  final physical = at * tester.view.devicePixelRatio;
  for (final call in [
    MethodCall('entered', [physical.dx, physical.dy]),
    const MethodCall('performOperation', ['preview.png']),
  ]) {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'desktop_drop',
      const StandardMethodCodec().encodeMethodCall(call),
      (_) {},
    );
  }
  await tester.pump();
}

Future<void> _studio(WidgetTester tester, {double scale = 1}) async {
  tester.view.physicalSize = const Size(1440, 900) * scale;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final vm = StudioViewModel(
    config: tempConfig(),
    streamChat: (_) => const Stream.empty(),
  );
  vm.side = SideChat(vm);
  addTearDown(vm.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: pennaTheme(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final size = media.size / scale;
        return MediaQuery(
          data: media.copyWith(
            size: size,
            devicePixelRatio: media.devicePixelRatio * scale,
          ),
          child: FittedBox(
            child: SizedBox.fromSize(size: size, child: child),
          ),
        );
      },
      home: Scaffold(
        body: StudioPage(
          vm: vm,
          config: vm.config,
          archive: ArchiveStore(),
          onOpenSettings: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('原生文件拖放只交给可见页,弹窗打开时也不透给底下的页', (tester) async {
    final received = <String>[];
    Widget target(String id) => GalleryItem(
      id: id,
      onMove: (_) {},
      onImage: (_) => received.add(id),
      child: const SizedBox.expand(),
    );
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              page = context;
              return Stack(
                children: [
                  TickerMode(
                    enabled: false,
                    child: IgnorePointer(child: target('hidden')),
                  ),
                  target('visible'),
                ],
              );
            },
          ),
        ),
      ),
    );
    await _drop(tester, const Offset(100, 100));
    expect(received, ['visible']);

    showDialog<void>(
      context: page,
      builder: (_) => Dialog(
        child: SizedBox(width: 200, height: 160, child: target('dialog')),
      ),
    );
    await tester.pumpAndSettle();
    await _drop(tester, tester.getCenter(find.byType(Dialog)));
    expect(received, ['visible', 'dialog']);
    Navigator.of(page).pop();
    await tester.pumpAndSettle();
    await _drop(tester, const Offset(100, 100));
    expect(received, ['visible', 'dialog', 'visible']);
  });

  testWidgets('界面放大后原生拖入按屏幕上看到的位置命中', (tester) async {
    var received = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final size = media.size / 2;
          return MediaQuery(
            data: media.copyWith(
              size: size,
              devicePixelRatio: media.devicePixelRatio * 2,
            ),
            child: FittedBox(
              child: SizedBox.fromSize(size: size, child: child),
            ),
          );
        },
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 100,
                top: 80,
                width: 100,
                height: 100,
                child: GalleryItem(
                  id: 'scaled',
                  onMove: (_) {},
                  onImage: (_) => received++,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await _drop(tester, tester.getCenter(find.byType(GalleryItem)));
    expect(received, 1);
  });

  testWidgets('图框卸载后不再提交尚未读完的图片', (tester) async {
    var received = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageDrop(image: null, onChanged: (_) => received++),
        ),
      ),
    );
    final file = _PendingFile('late.png');
    final drop = tester.widget<DropTarget>(find.byType(DropTarget));
    IOOverrides.runZoned(
      () => drop.onDragDone!(
        DropDoneDetails(
          files: [DropItemFile(file.path)],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      ),
      createFile: (_) => file,
    );
    await tester.pumpWidget(const SizedBox());
    file.contents.complete(Uint8List.fromList([1]));
    await tester.pump();
    expect(received, 0);
  });

  testWidgets('多次并行拖入在读完文件后仍遵守附件数量上限', (tester) async {
    await _studio(tester);
    final pending = {
      for (var i = 0; i <= maxAttachments; i++)
        'file$i.txt': _PendingFile('file$i.txt'),
    };
    final drop = tester.widget<DropTarget>(find.byType(DropTarget));
    IOOverrides.runZoned(() {
      for (final file in pending.values) {
        drop.onDragDone!(
          DropDoneDetails(
            files: [DropItemFile(file.path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
      }
    }, createFile: (path) => pending[path]!);
    await tester.pump();
    for (final file in pending.values) {
      file.contents.complete(Uint8List.fromList([65]));
    }
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentChip), findsNWidgets(maxAttachments));
    expect(find.text('最多 $maxAttachments 个附件'), findsOneWidget);
  });

  testWidgets('放大界面后拖入副聊天右侧仍交给副聊天', (tester) async {
    await _studio(tester, scale: 2);
    await tester.tap(find.text('副聊天'));
    await tester.pumpAndSettle();
    final input = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '问问工作区里的提示词',
    );
    final at = tester.getBottomRight(input) - const Offset(20, 20);
    final file = _PendingFile('side.txt');
    final drop = tester.widget<DropTarget>(find.byType(DropTarget));
    IOOverrides.runZoned(
      () => drop.onDragDone!(
        DropDoneDetails(
          files: [DropItemFile(file.path)],
          localPosition: Offset.zero,
          globalPosition: at,
        ),
      ),
      createFile: (_) => file,
    );
    await tester.pump();
    file.contents.complete(Uint8List.fromList([65]));
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentChip), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentChip), findsNothing);
  });
}
