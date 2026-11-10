import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/cli_provider.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/data/models/app_config.dart';

LlmRequest _req(String protocol, {String model = 'opus', String? effort}) =>
    LlmRequest(
      protocol: protocol,
      baseUrl: '',
      model: model,
      apiKey: '',
      effort: effort,
      messages: const [
        {'role': 'system', 'content': 'SYS'},
        {'role': 'user', 'content': '画只猫'},
        {'role': 'assistant', 'content': '好'},
        {'role': 'user', 'content': '再画只狗'},
      ],
      images: {
        3: [
          (mime: 'image/png', bytes: Uint8List.fromList([1, 2])),
        ],
      },
    );

void main() {
  test('Claude Code:系统提示另放,工具全关;对话拼成一段,图跟在后面', () {
    final req = _req(protocolClaudeCode, effort: 'high');
    final args = claudeCliArgs(req, 'sys.txt');
    expect(args, containsAllInOrder(['--system-prompt-file', 'sys.txt']));
    expect(args, containsAllInOrder(['--tools', '']));
    expect(args, containsAllInOrder(['--model', 'opus']));
    expect(args, containsAllInOrder(['--effort', 'high']));
    expect(cliSystem(req), 'SYS');

    final line = jsonDecode(claudeCliInput(req)) as Map;
    final content = line['message']['content'] as List;
    final text = content.first['text'] as String;
    expect(text, isNot(contains('SYS')));
    expect(text, contains('<user>\n画只猫\n</user>'));
    expect(text.indexOf('再画只狗'), greaterThan(text.indexOf('画只猫')));
    expect(content.last['source']['data'], base64Encode([1, 2]));
  });

  test('Codex:系统提示写进输入;default 不传模型;图走 -i', () {
    final req = _req(protocolCodex, model: cliDefaultModel);
    final args = codexCliArgs(req, ['a.png']);
    expect(args, isNot(contains('-m')));
    expect(args.sublist(args.length - 3), ['-', '-i', 'a.png']);
    expect(
      cliTranscript(req, withSystem: true),
      startsWith('<instructions>\nSYS'),
    );
  });

  test('读 Claude Code 的流:字、用量、出错', () {
    expect(
      parseClaudeCliLine(
        '{"type":"stream_event","event":{"type":"content_block_delta",'
        '"delta":{"type":"text_delta","text":"hi"}}}',
      ).delta,
      'hi',
    );
    final done = parseClaudeCliLine(
      '{"type":"result","is_error":false,"usage":{"input_tokens":2,'
      '"cache_creation_input_tokens":700,"cache_read_input_tokens":10,'
      '"output_tokens":4}}',
    );
    expect(done.usage, (input: 712, cached: 10, output: 4));
    expect(done.error, isNull);
    final failed = parseClaudeCliLine(
      '{"type":"result","is_error":true,"result":"Not logged in · Please run /login"}',
    );
    expect(
      cliProblem(protocolClaudeCode, failed.error!),
      contains('claude 登录'),
    );
    expect(parseClaudeCliLine('not json').delta, isNull);
  });

  test('读 Codex 的流:回复、用量、出错', () {
    expect(
      parseCodexLine(
        '{"type":"item.completed","item":{"id":"1","type":"agent_message","text":"好"}}',
      ).delta,
      '好',
    );
    expect(
      parseCodexLine(
        '{"type":"turn.completed","usage":{"input_tokens":5,'
        '"cached_input_tokens":1,"output_tokens":2}}',
      ).usage,
      (input: 5, cached: 1, output: 2),
    );
    expect(
      parseCodexLine('{"type":"turn.failed","error":{"message":"boom"}}').error,
      'boom',
    );
    expect(
      cliProblem(protocolCodex, 'unexpected status 401 Unauthorized'),
      contains('codex login'),
    );
  });

  test('设置里存得住这两种协议', () {
    for (final p in [protocolClaudeCode, protocolCodex]) {
      final l = LlmProfile(
        id: 'x',
        name: 'x',
        baseUrl: '',
        model: 'm',
        protocol: p,
      );
      expect(LlmProfile.fromJson(l.toJson()).protocol, p);
    }
  });
}
