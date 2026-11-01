// 输入框旁边那个上下文圆环要用到的:模型的上下文上限、估算 token 数。

/// 常见模型的上下文上限,按模型名里的片段认(靠前的优先)。数字取自 models.dev(2026-11)。
// ponytail: 新模型、中转站自己起的名字认不出来,靠接口卡片上的「上下文上限」填;
// 要更准得联网查 models.dev,离线和国内网络下不一定连得上,所以先用这张表。
const _knownLimits = <(String, int)>[
  ('grok', 500000),
  ('gemini', 1048576),
  ('deepseek', 1048576),
  ('gpt-6', 1050000),
  ('gpt-5', 400000),
  ('gpt-4o', 128000),
  ('kimi', 1048576),
  ('glm-5', 1024000),
  ('qwen', 262144),
  ('claude', 1000000),
];

/// 认不出来时返回 null。
int? modelContextLimit(String model) {
  final name = model.toLowerCase();
  for (final (part, limit) in _knownLimits) {
    if (name.contains(part)) return limit;
  }
  return null;
}

/// 一张图大约算多少 token(各家算法不同,只求量级)。
const imageTokenEstimate = 1000;

/// 估算一段文字的 token 数:英文约 4 个字符一个,中日韩文字约一个字一个。
// ponytail: 不是各家真实的分词,误差一两成,只用来显示「预计加载」;发出去后换成接口报的真数。
int estimateTokens(String text) {
  var wide = 0, narrow = 0;
  for (final rune in text.runes) {
    rune >= 0x2E80 ? wide++ : narrow++;
  }
  return wide + (narrow / 4).ceil();
}

/// 355300 → `355.3K`。
String formatKilo(int tokens) => '${(tokens / 1000).toStringAsFixed(1)}K';
