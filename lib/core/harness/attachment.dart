import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../l10n/l10n.dart';

/// 一条消息最多带几个附件。
const maxAttachments = 6;

/// 单张图片的大小上限(字节)。图片会整张编码进请求,太大接口会拒收。
const maxImageBytes = 10 * 1024 * 1024;

/// 给用户看的图片大小上限。
const maxImageLabel = '10 MB';

/// 开着压缩时能读进来的原图上限:压缩完再按 [maxImageBytes] 查。
const maxRawImageBytes = 40 * 1024 * 1024;
const maxRawImageLabel = '40 MB';

/// 比这个大的图片(开着压缩时)缩小并转成 WebP 再发。
const compressAboveBytes = 1024 * 1024;

/// 压缩后长边最多多少像素;模型看图时多半也会缩到这么大。
const compressMaxSide = 2048;

/// 单个文本附件的长度上限(字符数),和 Skill 正文的上限一致。
const maxFileChars = 60000;

/// 认得的图片扩展名和对应的类型。
const imageMimes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/gif',
};

/// 随消息发给模型的附件:图片([bytes] + [mime])或文本文件([text])。
@immutable
class Attachment {
  const Attachment.image({
    required this.name,
    required String this.mime,
    required Uint8List bytes,
    this.compressed = false,
    // 命名参数不能带下划线,写不成 this._bytes。
    // ignore: prefer_initializing_formals
  }) : _bytes = bytes,
       _text = null,
       file = null;

  const Attachment.text({required this.name, required String text})
    : mime = null,
      _bytes = null,
      // ignore: prefer_initializing_formals
      _text = text,
      compressed = false,
      file = null;

  /// 存过盘的附件(见 [AttachmentFiles]):内容在 [file] 里,用到时才读进来。
  /// [mime] 为 null 的是文本文件。
  const Attachment.saved({
    required this.name,
    required String this.file,
    this.mime,
    this.compressed = false,
  }) : _bytes = null,
       _text = null;

  final String name;
  final String? mime;
  final Uint8List? _bytes;
  final String? _text;

  /// 内容所在的文件;刚选上、还没存盘的是 null。
  final String? file;

  /// 这张图是被 [compressImage] 缩小、转成 WebP 的。
  final bool compressed;

  bool get isImage => mime != null;

  Uint8List? get bytes => isImage ? _bytes ?? _load() as Uint8List : null;

  String? get text => isImage ? null : _text ?? _load() as String;

  /// 从 [file] 读出来的内容,每个附件只读一次。
  static final _loaded = Expando<Object>();

  /// 文件没了(被删掉)时给空的,不让整条消息出错。
  Object _load() => _loaded[this] ??= () {
    final f = File(file!);
    try {
      return isImage ? f.readAsBytesSync() : f.readAsStringSync();
    } on FileSystemException catch (e) {
      debugPrint(tr('读不了附件「{0}」:{1}', [name, e.message]));
      return isImage ? Uint8List(0) : '';
    }
  }();
}

/// 把对话里的附件存成文件(工作台存盘时用):[dir] 里每个附件一个文件,
/// 文件名是内容的 SHA-1,所以同一张图只存一份。存盘的 JSON 里只记文件名。
// ponytail: 存盘时在界面线程里同步算哈希、写文件(一张最多 10 MB,只算一次);
// 读回时不读内容,显示或发送时才读。嫌卡再挪到后台。
class AttachmentFiles {
  AttachmentFiles(this.dir);

  final Directory dir;

  /// 读回时用到的文件名,[sweep] 留着它们。
  final _used = <String>{};

  static final _names = Expando<String>();

  /// 存好 [a](已经在 [dir] 里的不再写),返回记进 JSON 的那一项。
  Map<String, dynamic> put(Attachment a) {
    final name = _nameOf(a);
    final f = File('${dir.path}${Platform.pathSeparator}$name');
    if (!f.existsSync()) {
      dir.createSync(recursive: true);
      // 先写临时文件再改名:中途断电也不会留下半截的文件。
      File('${f.path}.tmp')
        ..writeAsBytesSync(a.bytes ?? utf8.encode(a.text ?? ''), flush: true)
        ..renameSync(f.path);
    }
    return {
      'name': a.name,
      'file': name,
      'mime': ?a.mime,
      if (a.compressed) 'compressed': true,
    };
  }

  String _nameOf(Attachment a) {
    final saved = a.file;
    if (saved != null && File(saved).parent.path == dir.path) {
      return saved.substring(dir.path.length + 1);
    }
    return _names[a] ??= () {
      final ext = switch (a.mime) {
        null => 'txt',
        'image/jpeg' => 'jpg',
        final m => m.substring(m.indexOf('/') + 1),
      };
      final content = a.bytes ?? utf8.encode(a.text ?? '');
      return '${sha1.convert(content)}.$ext';
    }();
  }

  /// [put] 记下的一项读回成附件;文件没了或这一项不对时返回 null。
  Attachment? get(Object? j) {
    if (j is! Map) return null;
    final name = j['file'];
    // 只认 [put] 起的文件名,不让 JSON 指到别的文件夹去。
    if (name is! String || !RegExp(r'^[0-9a-f]{40}\.[a-z]+$').hasMatch(name)) {
      return null;
    }
    final path = '${dir.path}${Platform.pathSeparator}$name';
    if (!File(path).existsSync()) return null;
    _used.add(name);
    return Attachment.saved(
      name: (j['name'] as String?) ?? name,
      file: path,
      mime: j['mime'] as String?,
      compressed: j['compressed'] == true,
    );
  }

  /// 读回存档后调:删掉存档里不再提到的文件(上次删掉、清空的对话留下的)。
  /// 不在存盘时删:操作记录的回滚还可能把删掉的对话拿回来,它只在内存里,重开就没了。
  void sweep() {
    try {
      if (dir.existsSync()) {
        for (final f in dir.listSync().whereType<File>()) {
          if (!_used.contains(f.uri.pathSegments.last)) f.deleteSync();
        }
      }
    } on FileSystemException catch (e) {
      debugPrint(tr('清理附件失败:{0}', [e.message]));
    }
    _used.clear();
  }
}

/// 给用户看的附件错误。
class AttachmentException implements Exception {
  const AttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 大图缩小、转成有损 WebP。不够大、是动图、解不开、转完反而更大时原样返回。
Future<Attachment> compressImage(Attachment a) async {
  final bytes = a.bytes;
  if (bytes == null || bytes.length <= compressAboveBytes) return a;
  if (a.mime == 'image/gif') return a;
  // 解码和编码都很费时,放到另一个线程,窗口不卡。
  final out = await Isolate.run(() => _toWebP(bytes));
  if (out == null || out.length >= bytes.length) return a;
  final dot = a.name.lastIndexOf('.');
  return Attachment.image(
    name: '${dot < 0 ? a.name : a.name.substring(0, dot)}.webp',
    mime: 'image/webp',
    bytes: out,
    compressed: true,
  );
}

/// 复制到剪贴板用:Windows 那边(GDI+)读不了 WebP,统一转成 PNG,在另一个线程里做。
/// 本来就是 PNG 的原样返回;读不了返回 null。
Future<Uint8List?> toPng(Attachment a) async {
  final bytes = a.bytes;
  if (bytes == null || bytes.isEmpty) return null;
  if (a.mime == 'image/png') return bytes;
  return Isolate.run(() {
    final image = img.decodeImage(bytes);
    return image == null ? null : img.encodePng(image);
  });
}

/// 档案库、角色库的预览图:长边缩到这么大。
const previewMaxSide = 768;

/// 把一张图转成预览用的 WebP(长边缩到 [previewMaxSide]),在另一个线程里做。
/// 读不了返回 null。
Future<Uint8List?> toPreviewWebP(Uint8List bytes) =>
    Isolate.run(() => _toWebP(bytes, maxSide: previewMaxSide));

Uint8List? _toWebP(Uint8List bytes, {int maxSide = compressMaxSide}) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  return _webP(_shrink(image, maxSide));
}

/// 长边超过 [maxSide] 时等比缩到 [maxSide]。
img.Image _shrink(img.Image image, int maxSide) {
  if (max(image.width, image.height) <= maxSide) return image;
  final wide = image.width >= image.height;
  return img.copyResize(
    image,
    width: wide ? maxSide : null,
    height: wide ? null : maxSide,
    interpolation: img.Interpolation.average,
  );
}

Uint8List _webP(img.Image image) =>
    img.encodeWebP(image, lossless: false, quality: 80, singleFrame: true);

/// 剪贴板里贴进来的图最大多少字节。Windows 上 `pasteboard` 给的是不压缩的 32 位 BMP
/// (宽 × 高 × 4),比原图大得多,所以这条线远高于图片文件的 [maxRawImageBytes]。
const maxPastedBytes = 512 * 1024 * 1024;

/// 把剪贴板里的图(Windows 上是不压缩的 BMP)转成能发给模型的附件:
/// [compress] 时缩到长边 [compressMaxSide] 的 WebP,否则原尺寸的 PNG。
/// 在另一个线程里做。读不了返回 null。
Future<Attachment?> pastedImage(Uint8List raw, {required bool compress}) async {
  final out = await Isolate.run(() {
    final image = img.decodeImage(raw);
    if (image == null) return null;
    return compress
        ? _webP(_shrink(image, compressMaxSide))
        : img.encodePng(image);
  });
  if (out == null) return null;
  final name = tr('粘贴的图片.png');
  return Attachment.image(
    name: compress ? name.replaceFirst(RegExp(r'\.png$'), '.webp') : name,
    mime: compress ? 'image/webp' : 'image/png',
    bytes: out,
    // 本来就小的截图转一下格式不算"压缩了大图",不提示。
    compressed: compress && raw.length > compressAboveBytes,
  );
}

/// 把一个文件读成附件:图片按扩展名认,其余的当 UTF-8 文本读。
/// [compress] 为真时大图先经 [compressImage] 缩小。
/// 太大、读不了、既不是图片也不是文本时抛 [AttachmentException]。
Future<Attachment> readAttachment(File file, {bool compress = false}) async {
  final name = file.uri.pathSegments.last;
  final dot = name.lastIndexOf('.');
  final mime = dot < 0
      ? null
      : imageMimes[name.substring(dot + 1).toLowerCase()];
  final Uint8List bytes;
  try {
    final size = await file.length();
    if (mime != null && size > (compress ? maxRawImageBytes : maxImageBytes)) {
      throw AttachmentException(
        tr('「{0}」超过 {1}', [name, compress ? maxRawImageLabel : maxImageLabel]),
      );
    }
    // UTF-8 一个字符最多 4 字节,超过这个数一定超长,不用读进来再数。
    if (mime == null && size > maxFileChars * 4) {
      throw AttachmentException(tr('「{0}」太长', [name]));
    }
    bytes = await file.readAsBytes();
  } on FileSystemException {
    throw AttachmentException(tr('读不了「{0}」', [name]));
  }
  if (mime != null) {
    final image = Attachment.image(name: name, mime: mime, bytes: bytes);
    final sent = compress ? await compressImage(image) : image;
    if (sent.bytes!.length > maxImageBytes) {
      throw AttachmentException(tr('「{0}」超过 {1}', [name, maxImageLabel]));
    }
    return sent;
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw AttachmentException(tr('「{0}」不是图片或文本', [name]));
  }
  // 二进制文件碰巧能按 UTF-8 解开时,里面通常有 NUL。
  if (text.contains('\u0000')) {
    throw AttachmentException(tr('「{0}」不是图片或文本', [name]));
  }
  if (text.length > maxFileChars) {
    throw AttachmentException(tr('「{0}」太长', [name]));
  }
  return Attachment.text(name: name, text: text);
}
