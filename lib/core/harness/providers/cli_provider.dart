import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../data/models/app_config.dart';
import '../../../l10n/l10n.dart';
import 'llm_http.dart';

// Claude 订阅、Codex 订阅(2026-11-11 用户要求):Penna 不碰订阅的登录凭据,
// 而是调用户本机装好、自己登录过的 Claude Code / Codex 命令行,让它们去问模型。
// Anthropic 不许第三方程序做 Claude 账号登录、拿订阅的凭据发请求(Claude Code 文档
// 「Legal and compliance」),但用户用自己的订阅登录原版 Claude Code 是可以的,所以走命令行。
// ponytail: 每条消息开一个进程,整场对话拼成一段文字发过去(命令行没有多轮的接口);
// 工具全关,只要文字;Codex 的图走 -i 临时文件。慢一点,够用。

/// 「拉取模型」时给的几个:命令行认的别名。
List<String> cliModels(String protocol) => protocol == protocolClaudeCode
    ? const ['haiku', 'opus', 'sonnet']
    : const [cliDefaultModel];

/// 把整场对话拼成一段:系统提示([withSystem] 为真时)、之前的几轮、最后一句。
String cliTranscript(LlmRequest req, {required bool withSystem}) {
  final system = [
    for (final m in req.messages)
      if (m['role'] == 'system') m['content'] ?? '',
  ].join('\n\n');
  final turns = [
    for (final m in req.messages)
      if (m['role'] != 'system') m,
  ];
  return [
    if (withSystem && system.trim().isNotEmpty)
      '<instructions>\n$system\n</instructions>',
    if (turns.length > 1) '下面是到现在为止的对话,最后一条是用户现在说的话,接着回复它,只写回复本身。',
    for (final m in turns)
      turns.length > 1
          ? '<${m['role']}>\n${m['content'] ?? ''}\n</${m['role']}>'
          : m['content'] ?? '',
  ].join('\n\n');
}

/// 系统提示(Claude Code 用 --system-prompt-file 换掉它自己的)。
String cliSystem(LlmRequest req) => [
  for (final m in req.messages)
    if (m['role'] == 'system') m['content'] ?? '',
].join('\n\n');

List<String> claudeCliArgs(LlmRequest req, String systemFile) => [
  '-p',
  '--input-format', 'stream-json',
  '--output-format', 'stream-json',
  '--verbose',
  '--include-partial-messages',
  // 只要文字:工具、MCP、本机的设置和会话记录都不要。
  '--tools', '',
  '--strict-mcp-config',
  '--setting-sources', '',
  '--no-session-persistence',
  '--system-prompt-file', systemFile,
  if (req.model.isNotEmpty && req.model != cliDefaultModel) ...[
    '--model',
    req.model,
  ],
  if (req.effort case final effort?) ...['--effort', effort],
];

/// 发给 Claude Code 的那一行(stream-json):对话拼成的文字,后面跟着图。
String claudeCliInput(LlmRequest req) => jsonEncode({
  'type': 'user',
  'message': {
    'role': 'user',
    'content': [
      {'type': 'text', 'text': cliTranscript(req, withSystem: false)},
      for (final images in req.images.values)
        for (final image in images)
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': image.mime,
              'data': base64Encode(image.bytes),
            },
          },
    ],
  },
});

List<String> codexCliArgs(LlmRequest req, List<String> imageFiles) => [
  'exec',
  '--json',
  '--skip-git-repo-check',
  '--ephemeral',
  '--color', 'never',
  '-s', 'read-only',
  if (req.model.isNotEmpty && req.model != cliDefaultModel) ...[
    '-m',
    req.model,
  ],
  if (req.effort case final effort?) ...[
    '-c',
    'model_reasoning_effort="$effort"',
  ],
  // 提示词从标准输入读;图放在最后(-i 后面跟几个文件)。
  '-',
  if (imageFiles.isNotEmpty) ...['-i', ...imageFiles],
];

/// 命令行吐出的一行里的一件事:一段字、用量、或出错的原因。
typedef CliEvent = ({String? delta, LlmUsage? usage, String? error});

const CliEvent _nothing = (delta: null, usage: null, error: null);

Map<String, dynamic>? _json(String line) {
  try {
    final j = jsonDecode(line);
    return j is Map<String, dynamic> ? j : null;
  } on FormatException {
    return null;
  }
}

int _n(Object? v) => v is num ? v.toInt() : 0;

CliEvent parseClaudeCliLine(String line) {
  final j = _json(line);
  if (j == null) return _nothing;
  if (j case {
    'type': 'stream_event',
    'event': {
      'type': 'content_block_delta',
      'delta': {'type': 'text_delta', 'text': final String text},
    },
  }) {
    return (delta: text, usage: null, error: null);
  }
  if (j['type'] != 'result') return _nothing;
  final u = j['usage'];
  final usage = u is Map
      ? (
          input:
              _n(u['input_tokens']) +
              _n(u['cache_creation_input_tokens']) +
              _n(u['cache_read_input_tokens']),
          cached: _n(u['cache_read_input_tokens']),
          output: _n(u['output_tokens']),
        )
      : null;
  final failed = j['is_error'] == true;
  return (
    delta: null,
    usage: usage,
    error: failed ? '${j['result'] ?? j['subtype'] ?? ''}' : null,
  );
}

CliEvent parseCodexLine(String line) {
  final j = _json(line);
  if (j == null) return _nothing;
  return switch (j) {
    {
      'type': 'item.completed',
      'item': {'type': 'agent_message', 'text': final String text},
    } =>
      (delta: text, usage: null, error: null),
    {'type': 'turn.completed', 'usage': final Map u} => (
      delta: null,
      usage: (
        input: _n(u['input_tokens']),
        cached: _n(u['cached_input_tokens']),
        output: _n(u['output_tokens']),
      ),
      error: null,
    ),
    {'type': 'turn.failed', 'error': {'message': final Object? m}} ||
    {
      'type': 'error',
      'message': final Object? m,
    } => (delta: null, usage: null, error: '$m'),
    _ => _nothing,
  };
}

/// 认得的报错说人话:没装、没登录。
String cliProblem(String protocol, String raw) {
  final text = raw.toLowerCase();
  final claude = protocol == protocolClaudeCode;
  if (text.contains('log in') ||
      text.contains('login') ||
      text.contains('sign in') ||
      text.contains('401')) {
    return claude
        ? tr('Claude Code 没登录:在终端运行 claude 登录')
        : tr('Codex 没登录或登录过期:在终端运行 codex login');
  }
  return tr('模型返回错误:{0}', [clipLlmError(raw.trim())]);
}

/// 调本机的命令行问模型。取消订阅时结束进程。
Stream<String> streamCliChat(LlmRequest req) {
  final claude = req.protocol == protocolClaudeCode;
  Process? process;
  Directory? dir;
  var cancelled = false;
  late final StreamController<String> out;

  Future<void> run() async {
    // 放在空的临时文件夹里跑:不读到哪个项目的 CLAUDE.md、AGENTS.md。
    final work = dir = Directory.systemTemp.createTempSync('penna-cli');
    final images = <String>[];
    final List<String> args;
    final String input;
    if (claude) {
      final system = File('${work.path}${Platform.pathSeparator}system.txt')
        ..writeAsStringSync(cliSystem(req));
      args = claudeCliArgs(req, system.path);
      input = '${claudeCliInput(req)}\n';
    } else {
      for (final (i, image) in req.images.values.expand((l) => l).indexed) {
        final ext = image.mime.split('/').last;
        final f = File('${work.path}${Platform.pathSeparator}$i.$ext')
          ..writeAsBytesSync(image.bytes);
        images.add(f.path);
      }
      args = codexCliArgs(req, images);
      input = cliTranscript(req, withSystem: true);
    }
    final exe = claude ? 'claude' : 'codex';
    Process started;
    try {
      started = await Process.start(exe, args, workingDirectory: work.path);
    } on ProcessException {
      // npm 装的是 .cmd,要经过 shell 才找得到。
      try {
        started = await Process.start(
          exe,
          args,
          workingDirectory: work.path,
          runInShell: true,
        );
      } on ProcessException {
        throw LlmException(
          claude
              ? tr('没找到 claude 命令:先安装 Claude Code 并登录')
              : tr('没找到 codex 命令:先安装 Codex 并登录'),
        );
      }
    }
    process = started;
    if (cancelled) {
      started.kill();
      return;
    }
    started.stdin.add(utf8.encode(input));
    await started.stdin.close();
    final errors = StringBuffer();
    final errDone = started.stderr
        .transform(utf8.decoder)
        .forEach(errors.write);
    var yielded = false;
    String? failed;
    await for (final line
        in started.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (cancelled) return;
      final e = claude ? parseClaudeCliLine(line) : parseCodexLine(line);
      if (e.usage case final u?) req.onUsage?.call(u);
      if (e.error case final err?) failed = err;
      if (e.delta case final d? when d.isNotEmpty) {
        // Codex 一次给一整段;几段之间空一行。
        if (yielded && !claude) out.add('\n\n');
        yielded = true;
        out.add(d);
      }
    }
    final code = await started.exitCode;
    await errDone;
    if (cancelled) return;
    if (failed != null) throw LlmException(cliProblem(req.protocol, failed));
    if (!yielded) {
      throw LlmException(
        code == 0
            ? tr('模型没有返回内容')
            : cliProblem(req.protocol, errors.toString()),
      );
    }
  }

  void cleanUp() {
    try {
      dir?.deleteSync(recursive: true);
    } on FileSystemException {
      // 进程还占着文件时删不掉,留在临时文件夹里由系统清。
    }
  }

  out = StreamController<String>(
    onListen: () async {
      try {
        await run();
      } on Object catch (e) {
        if (!cancelled) out.addError(e);
      } finally {
        cleanUp();
        if (!cancelled) await out.close();
      }
    },
    onCancel: () {
      cancelled = true;
      process?.kill();
    },
  );
  return out.stream;
}
