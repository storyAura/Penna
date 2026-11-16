// 真的放一段视频:插件起得来、读得出时长、画面在走、能跳、能静音。
// `test/` 里没有原生播放器,跑不到这里。只有 Windows 在窗口里播。
//
// 跑法(PowerShell,路径里有中文要先 subst,见根目录 CLAUDE.md):
//
//   $env:PENNA_TEST_VIDEO = 'C:\path\to\sample.mp4'   # 几秒长的 H.264 mp4
//   flutter test integration_test/video_player_test.dart -d windows
//
// 没给这个环境变量就跳过,放在仓库里不影响别人。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:penna/ui/features/studio/comfy_video_player.dart';
import 'package:video_player/video_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final video = Platform.environment['PENNA_TEST_VIDEO'];

  testWidgets('播放窗口:读出时长,画面在走,← 跳回去,点音量静音', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showVideoPlayer(context, video!),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // 等插件把文件打开(真时间)。
    for (var i = 0; i < 50 && find.byType(Slider).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('这个视频播放不了'), findsNothing);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));

    String clock() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((t) => t.contains(' / '));

    // 读出了时长,放了两秒位置往前走了。
    await tester.pump(const Duration(seconds: 2));
    final playing = clock();
    expect(playing.split(' / ').last, isNot('00:00'));
    expect(playing.split(' / ').first, isNot('00:00'));

    // 暂停后按 ←:跳回开头附近。
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 800));
    expect(clock().split(' / ').first, '00:00');

    // 点音量图标静音,图标换成静音的。
    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
  }, skip: video == null || !Platform.isWindows);
}
