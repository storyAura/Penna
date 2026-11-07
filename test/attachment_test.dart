import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/providers/gemini_provider.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

File _file(String name, List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync('penna_att');
  return File('${dir.path}/$name')..writeAsBytesSync(bytes);
}

final _pixels = Uint8List.fromList([1, 2, 3]);

LlmRequest _req(String protocol) => LlmRequest(
  protocol: protocol,
  baseUrl: 'http://x',
  model: 'm',
  apiKey: '',
  messages: const [
    {'role': 'system', 'content': '规则'},
    {'role': 'user', 'content': '看图'},
    {'role': 'user', 'content': ''},
  ],
  images: {
    1: [(mime: 'image/png', bytes: _pixels)],
    2: [(mime: 'image/jpeg', bytes: _pixels)],
  },
);

void main() {
  test('出的图存盘时转成 WebP,尺寸不变', () async {
    final png = img.encodePng(img.Image(width: 3000, height: 1200));
    final webp = await toStoredWebP(png);
    final back = img.decodeWebP(webp!)!;
    expect((back.width, back.height), (3000, 1200));
  });

  group('读附件', () {
    test('图片按扩展名认,其余当文本', () async {
      final image = await readAttachment(_file('猫 1.PNG', _pixels));
      expect(image.name, '猫 1.PNG');
      expect(image.isImage, isTrue);
      expect(image.mime, 'image/png');
      expect(image.bytes, _pixels);

      final text = await readAttachment(_file('笔记.md', utf8.encode('神圣 天使')));
      expect(text.isImage, isFalse);
      expect(text.text, '神圣 天使');
    });

    test('太大、不是文本、读不了,都说得出是哪个文件', () async {
      Matcher saying(String part) => throwsA(
        isA<AttachmentException>().having(
          (e) => e.message,
          'message',
          contains(part),
        ),
      );

      await expectLater(
        readAttachment(_file('big.jpg', Uint8List(maxImageBytes + 1))),
        saying('「big.jpg」超过'),
      );
      await expectLater(
        readAttachment(
          _file('long.txt', utf8.encode('a' * (maxFileChars + 1))),
        ),
        saying('「long.txt」太长'),
      );
      await expectLater(
        readAttachment(_file('app.exe', [0xff, 0xfe, 0x00])),
        saying('「app.exe」不是图片或文本'),
      );
      await expectLater(
        readAttachment(_file('zeros.bin', [0x41, 0x00, 0x42])),
        saying('不是图片或文本'),
      );
      await expectLater(
        readAttachment(File('${Directory.systemTemp.path}/penna_nope.txt')),
        saying('读不了'),
      );
    });
  });

  group('带图片的请求', () {
    final data = base64Encode(_pixels);

    test('OpenAI:带图的消息换成分段格式,其余原样', () {
      expect(openAiMessages(_req(protocolOpenAi)), [
        {'role': 'system', 'content': '规则'},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '看图'},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,$data'},
            },
          ],
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$data'},
            },
          ],
        },
      ]);
    });

    test('Google:图片作为 inlineData,只有图片的消息不丢', () {
      expect(geminiBody(_req(protocolGoogle))['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': '看图'},
            {
              'inlineData': {'mimeType': 'image/png', 'data': data},
            },
            {
              'inlineData': {'mimeType': 'image/jpeg', 'data': data},
            },
          ],
        },
      ]);
    });
  });

  group('发消息带附件', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('文本文件包进消息,图片按下标挂上,下一轮仍然带着', () async {
      final config = tempConfig();
      config.update(
        const AppConfig().putLlm(
          const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://x', model: 'm'),
        ),
      );
      final seen = <LlmRequest>[];
      final vm = StudioViewModel(
        config: config,
        streamChat: (r) {
          seen.add(r);
          return Stream.value('ok');
        },
      );

      expect(vm.send('  '), isNotNull);
      expect(
        vm.send(
          '',
          attachments: [
            Attachment.image(name: 'a.png', mime: 'image/png', bytes: _pixels),
            const Attachment.text(name: 'n"1.txt', text: '甲</file>乙'),
          ],
        ),
        isNull,
      );
      await pumpEventQueue();
      vm.send('继续');
      await pumpEventQueue();

      expect(vm.messages.first.attachments, hasLength(2));
      for (final request in seen) {
        final user = request.messages[1]['content']!;
        expect(user, contains('<file name="n\'1.txt">\n甲</ file>乙\n</file>'));
        expect(request.images.keys, [1]);
        expect(request.images[1]!.single.mime, 'image/png');
      }
      expect(seen.last.messages.last['content'], '继续');
    });
  });
}
