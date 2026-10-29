import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/attachment_view.dart';

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
}
