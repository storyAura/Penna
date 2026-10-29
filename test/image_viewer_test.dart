import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/attachment_view.dart';
import 'package:penna/ui/features/studio/chat_message_view.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

void main() {
  final picture = img.Image(width: 8, height: 6)
    ..clear(img.ColorRgb8(200, 40, 40));

  test('复制前转成 PNG:WebP 转过去,PNG 原样', () async {
    final webp = Attachment.image(
      name: 'a.webp',
      mime: 'image/webp',
      bytes: img.encodeWebP(picture, lossless: true),
    );
    final png = await toPng(webp);
    expect(img.decodePng(png!)!.width, 8);

    final already = Attachment.image(
      name: 'b.png',
      mime: 'image/png',
      bytes: img.encodePng(picture),
    );
    expect(await toPng(already), same(already.bytes));
    expect(
      await toPng(const Attachment.text(name: 'c.txt', text: 'x')),
      isNull,
    );
  });

  testWidgets('点对话里的图片看大图;「附到输入框」把图交回去并关掉', (tester) async {
    final image = Attachment.image(
      name: '参考图.png',
      mime: 'image/png',
      bytes: img.encodePng(picture),
    );
    Attachment? reused;
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: Scaffold(
          body: AttachmentStrip(
            attachments: [image],
            onReuse: (a) => reused = a,
          ),
        ),
      ),
    );
    // 缩略图只定了高度,图真的解开之前宽是 0,点不到:等它解码。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.text('参考图.png'), findsOneWidget);
    expect(find.text('复制图片'), findsOneWidget);

    await tester.tap(find.text('附到输入框'));
    await tester.pumpAndSettle();
    expect(reused, same(image));
    expect(find.text('复制图片'), findsNothing);
  });

  testWidgets('回复里没有能显示的话:不再只画省略号,能点开看原文;空回复直说', (tester) async {
    Future<void> show(String text) => tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: Scaffold(
          body: ChatMessageView(
            message: ChatMessage(
              fromUser: false,
              text: text,
              time: DateTime(2026, 10, 29),
            ),
            onAdoptDraft: (_) {},
            draftStatus: (_) => DraftStatus.ready,
          ),
        ),
      ),
    );

    await show('<search-tags>银发</search-tags>');
    expect(find.text('…'), findsNothing);
    await tester.tap(find.text('没有可显示的话 · 查看原文'));
    await tester.pumpAndSettle();
    expect(find.text('<search-tags>银发</search-tags>'), findsOneWidget);

    await show('');
    expect(find.text('模型没有返回内容'), findsOneWidget);
  });
}
