import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// 读 GGUF 文件开头的几条信息,用来判断视觉组件(mmproj)和模型是不是一套。
// llama.cpp 启动时比的就是这两个数:模型的 <架构>.embedding_length
// 和视觉组件的 clip.vision.projection_dim,对不上就退出。

/// 一个 GGUF 文件的架构、名字和宽度。[width] 是模型的 embedding_length,
/// 或视觉组件要接的 projection_dim;不知道时为 0(有的视觉组件不写)。
typedef GgufInfo = ({String arch, String name, int width});

/// 只看文件开头这么多字节:要的几条都在最前面,词表在后面、很大。
const _head = 1 << 20;

/// 各种定长值占几个字节(GGUF 的类型编号 → 字节数);8 是字符串、9 是数组。
const _sizes = {
  0: 1,
  1: 1,
  2: 2,
  3: 2,
  4: 4,
  5: 4,
  6: 4,
  7: 1,
  10: 8,
  11: 8,
  12: 8,
};

/// 读 [path] 开头的信息;不是 GGUF 或读不了时为 null。同步执行,只读开头 1 MB。
GgufInfo? readGguf(String path) {
  final Uint8List bytes;
  try {
    final file = File(path).openSync();
    try {
      bytes = file.readSync(_head);
    } finally {
      file.closeSync();
    }
  } on FileSystemException {
    return null;
  }
  return parseGguf(bytes);
}

/// 从文件开头的 [bytes] 里取出架构、名字和宽度。读到词表或读到头就停。
GgufInfo? parseGguf(Uint8List bytes) {
  if (bytes.length < 24 ||
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'GGUF') {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  var at = 16; // 魔数、版本、张量个数
  final count = data.getUint64(at, Endian.little);
  at += 8;
  final strings = <String, String>{};
  final ints = <String, int>{};

  String text() {
    final n = data.getUint64(at, Endian.little);
    final s = utf8.decode(
      bytes.sublist(at + 8, at + 8 + n),
      allowMalformed: true,
    );
    at += 8 + n;
    return s;
  }

  void skip(int type) {
    if (type == 8) {
      at += 8 + data.getUint64(at, Endian.little);
    } else if (type == 9) {
      final element = data.getUint32(at, Endian.little);
      final n = data.getUint64(at + 4, Endian.little);
      at += 12;
      if (_sizes[element] case final size?) {
        at += n * size;
      } else {
        for (var i = 0; i < n; i++) {
          skip(element);
        }
      }
    } else {
      at += _sizes[type] ?? (throw const FormatException('GGUF 类型不认得'));
    }
  }

  try {
    for (var i = 0; i < count; i++) {
      final key = text();
      if (key.startsWith('tokenizer.')) break;
      final type = data.getUint32(at, Endian.little);
      at += 4;
      if (type == 8) {
        strings[key] = text();
      } else if (type == 4 || type == 5) {
        ints[key] = data.getUint32(at, Endian.little);
        skip(type);
      } else if (type == 10 || type == 11) {
        ints[key] = data.getUint64(at, Endian.little);
        skip(type);
      } else {
        skip(type);
      }
    }
  } on Object {
    // 读到 1 MB 的头了,或文件不完整:用已经读到的。
  }
  final arch = strings['general.architecture'];
  if (arch == null) return null;
  return (
    arch: arch,
    name: strings['general.basename'] ?? strings['general.name'] ?? '',
    width: arch == 'clip'
        ? ints['clip.vision.projection_dim'] ?? 0
        : ints['$arch.embedding_length'] ?? 0,
  );
}

/// 视觉组件 [mmproj] 能不能配模型 [model]:宽度都知道时看相不相等,有一个不知道时为 null。
bool? ggufFits(GgufInfo? model, GgufInfo? mmproj) {
  if (model == null || mmproj == null) return null;
  if (model.width == 0 || mmproj.width == 0) return null;
  return model.width == mmproj.width;
}

/// 视觉组件看着是不是给这个架构做的:名字里有架构名(Gemma-4-12B-It 对 gemma4)。
bool ggufNamed(GgufInfo model, GgufInfo mmproj) {
  String plain(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final arch = plain(model.arch);
  return arch.isNotEmpty && plain(mmproj.name).contains(arch);
}
