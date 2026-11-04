import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../../core/harness/skills/builtin_skills.dart';
import '../models/app_config.dart';
import '../../l10n/l10n.dart';

/// 一个 Skill(内置的或用户导入的)。
@immutable
class UserSkill {
  const UserSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.body,
  });

  final String id;
  final String name;
  final String description;

  /// 去掉文件头之后的正文,也就是给模型看的指令。
  final String body;
}

/// 给用户看的 Skill 导入错误。
class SkillException implements Exception {
  const SkillException(this.message);

  final String message;

  @override
  String toString() => message;
}

const maxSkillBytes = 256 * 1024;
const maxZipBytes = 20 * 1024 * 1024;
const maxUnpackedBytes = 10 * 1024 * 1024;
const maxZipFiles = 500;
String get _unnamed => tr('未命名');
String get _tooBig => tr('压缩包解开后太大(上限 10 MB、500 个文件)');

/// 内置的 Skill,带上正文。
final List<UserSkill> builtinSkillList = List.unmodifiable([
  for (final s in builtinSkills)
    UserSkill(
      id: s.id,
      name: s.label,
      description: s.hint,
      body: builtinSkillBodies[s.id] ?? '',
    ),
]);

bool _indented(String line) => line.startsWith(' ') || line.startsWith('\t');

/// 读文件头(`---` 之间那几行)里最外层的 `键: 值`。
/// 值写成多行(`>`、`|` 或直接换行缩进)时,把缩进的那几行接成一句。
Map<String, String> _parseHeader(List<String> lines) {
  final header = <String, String>{};
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final colon = line.indexOf(':');
    if (colon <= 0 || _indented(line) || line.startsWith('#')) continue;
    var value = line.substring(colon + 1).trim();
    if (value.isEmpty || RegExp(r'^[>|][+-]?$').hasMatch(value)) {
      final block = <String>[];
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].trim().isNotEmpty && !_indented(lines[j])) break;
        block.add(lines[j].trim());
      }
      value = block.where((l) => l.isNotEmpty).join(' ');
    }
    header[line.substring(0, colon).trim().toLowerCase()] = value.replaceAll(
      RegExp('^["\']|["\']\$'),
      '',
    );
  }
  return header;
}

/// 解析 SKILL.md:开头可以有 `---` 包起来的文件头(name / description),
/// 没有就用第一个标题、再没有就用 [fallbackName] 当名字。
UserSkill parseSkill(String text, {required String fallbackName}) {
  final lines = const LineSplitter().convert(
    text.startsWith('﻿') ? text.substring(1) : text,
  );
  var header = const <String, String>{};
  var bodyStart = 0;
  if (lines.isNotEmpty && lines.first.trim() == '---') {
    final end = lines.indexWhere((l) => l.trim() == '---', 1);
    // 第一行的 --- 也可能只是一条分隔线:它后面紧跟着「键: 值」才算文件头。
    final first = lines
        .skip(1)
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (end > 0 && RegExp(r'^[A-Za-z_][\w-]*\s*:').hasMatch(first)) {
      header = _parseHeader(lines.sublist(1, end));
      bodyStart = end + 1;
    }
  }
  final body = lines.sublist(bodyStart).join('\n').trim();
  if (body.isEmpty) throw SkillException(tr('SKILL.md 里没有正文'));
  final heading = lines
      .skip(bodyStart)
      .map((l) => l.trim())
      .firstWhere((l) => l.startsWith('# '), orElse: () => '');
  final name = [
    header['name'] ?? '',
    heading.replaceFirst('# ', '').trim(),
    fallbackName,
  ].firstWhere((s) => s.isNotEmpty, orElse: () => _unnamed);
  return UserSkill(
    id: skillIdFor(name),
    name: name,
    description: (header['description'] ?? '').isEmpty
        ? _firstSentence(body)
        : header['description']!,
    body: body,
  );
}

/// 没写简介时,拿正文里第一行不是标题的文字顶上。
String _firstSentence(String body) {
  final line = const LineSplitter()
      .convert(body)
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty && !l.startsWith('#'), orElse: () => '');
  return line.length > 80 ? '${line.substring(0, 80)}…' : line;
}

/// 由名字得出文件夹名:只留小写字母、数字和短横线,所以不会跳出技能目录。
/// 中文名没有可用字符时用名字算出的固定编号;不与内置 Skill 重名。
String skillIdFor(String name) {
  final lower = name.trim().toLowerCase();
  final full = lower
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final slug = full.length > _maxSlug ? full.substring(0, _maxSlug) : full;
  final hash = name.codeUnits
      .fold(0, (a, b) => (a * 31 + b) & 0xffffffff)
      .toRadixString(16);
  // 名字里有被丢掉的字符(中文、符号)或被截短时,不同名字可能得到同一个结果
  // (比如 C++ 和 C#),带上名字算出的编号来区分。
  final lossless = slug == lower.replaceAll(RegExp(r'[\s_]+'), '-');
  final id = slug.isEmpty
      ? 'skill-$hash'
      : lossless
      ? slug
      : '$slug-$hash';
  // con、nul 这类是 Windows 的保留名,不能当文件夹名。
  final reserved =
      builtinSkills.any((s) => s.id == id) || _windowsReserved.hasMatch(id);
  return reserved ? 'user-$id' : id;
}

const _maxSlug = 40;
final _windowsReserved = RegExp(r'^(con|prn|aux|nul|com\d|lpt\d)$');
// 含 $ 是为了挡住 CONIN$、CONOUT$ 这类设备名。
final _illegalInName = RegExp(r'[<>:"|?*$\x00-\x1f]');

/// 把压缩包里的路径整理成用 `/` 分隔的安全相对路径。
/// 系统垃圾文件返回空串(跳过);想跳出目录或含非法字符的返回 null(整个包拒收)。
String? safeZipPath(String raw) {
  final path = raw.replaceAll('\\', '/');
  if (path.startsWith('/')) return null;
  final parts = [
    for (final p in path.split('/'))
      if (p.isNotEmpty && p != '.') p,
  ];
  if (parts.isEmpty) return '';
  if (parts.first == '__MACOSX' || parts.last == '.DS_Store') return '';
  for (final part in parts) {
    // 「con .txt」这种带空格的写法,Windows 一样当成保留名。
    final stem = part.split('.').first.trim().toLowerCase();
    if (part == '..' ||
        part.endsWith('.') ||
        part.endsWith(' ') ||
        _illegalInName.hasMatch(part) ||
        _windowsReserved.hasMatch(stem)) {
      return null;
    }
  }
  return parts.join('/');
}

String _folderOf(String path) =>
    path.contains('/') ? path.substring(0, path.lastIndexOf('/') + 1) : '';

String _baseName(File file) =>
    file.uri.pathSegments.last.replaceFirst(RegExp(r'\.[^.]+$'), '');

/// 管理「文档\Penna\skills」下用户导入的 Skill:每个 Skill 一个文件夹,
/// 里面是 SKILL.md,以及压缩包里跟它放在一起的其他文件。
class SkillStore extends ChangeNotifier {
  SkillStore(this.dir);

  final Directory dir;

  List<UserSkill> _skills = const [];

  /// 用户导入的。
  List<UserSkill> get skills => _skills;

  /// 内置的加上用户导入的。
  List<UserSkill> get all => [...builtinSkillList, ..._skills];

  Directory _folderFor(String id) =>
      Directory('${dir.path}${Platform.pathSeparator}$id');

  File _fileOf(String id) =>
      File('${_folderFor(id).path}${Platform.pathSeparator}SKILL.md');

  /// 读出目录里所有能解析的 Skill;坏掉的文件跳过,不影响其他的。
  Future<void> load() async {
    final found = <UserSkill>[];
    if (await dir.exists()) {
      await for (final entry in dir.list()) {
        if (entry is! Directory) continue;
        final id = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        // 带点的是导入中断留下的临时文件夹,不是 Skill。
        if (id.contains('.')) continue;
        try {
          final parsed = parseSkill(
            await _fileOf(id).readAsString(),
            fallbackName: id,
          );
          found.add(
            UserSkill(
              id: id,
              name: parsed.name,
              description: parsed.description,
              body: parsed.body,
            ),
          );
        } on Object {
          continue;
        }
      }
    }
    found.sort((a, b) => a.name.compareTo(b.name));
    _skills = List.unmodifiable(found);
    notifyListeners();
  }

  /// 导入一个 SKILL.md 或一个 ZIP 压缩包(里面可以有多个 Skill)。
  /// 同名的会被覆盖。返回导入的 Skill。
  Future<List<UserSkill>> import(File source) async {
    final isZip = source.path.toLowerCase().endsWith('.zip');
    final List<UserSkill> imported;
    try {
      imported = isZip
          ? await _importZip(source)
          : [await _importMarkdown(source)];
    } on FileSystemException {
      throw SkillException(tr('读写文件失败'));
    }
    await load();
    return imported;
  }

  /// 存一个在对话里写出来的 Skill;[text] 是整篇 SKILL.md。
  /// 同名的只换掉 SKILL.md,它附带的其他文件不动。
  /// 没有名字、没有正文或太大时抛 [SkillException]。
  Future<UserSkill> addText(String text) async {
    final bytes = utf8.encode(text);
    if (bytes.length > maxSkillBytes) {
      throw SkillException(tr('Skill 太长(上限 256 KB)'));
    }
    final skill = parseSkill(text, fallbackName: '');
    if (skill.name == _unnamed) throw SkillException(tr('Skill 没有名字'));
    try {
      final file = _fileOf(skill.id);
      if (await file.parent.exists()) {
        // 已有这个 Skill:只换 SKILL.md,压缩包带来的其他文件留着。
        final temp = File('${file.path}.tmp');
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(file.path);
      } else {
        await _writePackage(skill.id, {'SKILL.md': bytes});
      }
      await load();
    } on FileSystemException {
      throw SkillException(tr('读写文件失败'));
    }
    return skill;
  }

  Future<UserSkill> _importMarkdown(File source) async {
    if (await source.length() > maxSkillBytes) {
      throw SkillException(tr('文件太大(上限 256 KB)'));
    }
    final String text;
    try {
      text = await source.readAsString();
    } on FormatException {
      throw SkillException(tr('不是 UTF-8 文本文件'));
    }
    final fileName = _baseName(source);
    final skill = parseSkill(
      text,
      // 文件就叫 SKILL.md 时名字没有信息量,交给解析结果里的"未命名"。
      fallbackName: fileName.toLowerCase() == 'skill' ? '' : fileName,
    );
    await _writePackage(skill.id, {'SKILL.md': utf8.encode(text)});
    return skill;
  }

  Future<List<UserSkill>> _importZip(File source) async {
    if (await source.length() > maxZipBytes) {
      throw SkillException(tr('压缩包太大(上限 20 MB)'));
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await source.readAsBytes());
    } on Object {
      throw SkillException(tr('不是有效的 ZIP 压缩包'));
    }

    // 第一步:只看清单。路径不安全、太大、有大小写撞名的,整个包拒收。
    final entries = <String, ArchiveFile>{};
    final seen = <String>{};
    var declared = 0;
    for (final entry in archive.files) {
      // 符号链接(指向别处的"快捷方式")不要。
      if (!entry.isFile || entry.isSymbolicLink) continue;
      final path = safeZipPath(entry.name);
      if (path == null) throw SkillException(tr('压缩包里有不安全的路径,已拒绝导入'));
      if (path.isEmpty) continue;
      // Windows 不分大小写,A.txt 和 a.txt 会互相覆盖。
      if (!seen.add(path.toLowerCase())) {
        throw SkillException(tr('压缩包里有重名的文件:{0}', [path]));
      }
      declared += entry.size;
      if (declared > maxUnpackedBytes || entries.length >= maxZipFiles) {
        throw SkillException(_tooBig);
      }
      entries[path] = entry;
    }

    // 每个 SKILL.md 所在的文件夹就是一个 Skill;嵌套时文件归最里层的那个。
    // SKILL.md 在包的根目录时,根目录(空串)排在最后,收下没被认领的文件。
    final roots = [
      for (final path in entries.keys)
        if (path.split('/').last.toLowerCase() == 'skill.md') _folderOf(path),
    ]..sort((a, b) => b.length.compareTo(a.length));
    if (roots.isEmpty) throw SkillException(tr('压缩包里没有 SKILL.md'));

    // 第二步:全部解开、全部解析。这一步出任何问题都还没有动磁盘。
    final packages = <String, Map<String, List<int>>>{
      for (final r in roots) r: {},
    };
    var unpacked = 0;
    for (final MapEntry(key: path, value: entry) in entries.entries) {
      final root = roots.firstWhere(path.startsWith, orElse: () => '\x00');
      if (!packages.containsKey(root)) continue;
      final List<int> bytes;
      try {
        bytes = entry.content;
      } on Object {
        throw SkillException(tr('压缩包里的文件损坏:{0}', [path]));
      }
      // 条目头里写的大小可以造假,按真正解出来的字节数再卡一次。
      unpacked += bytes.length;
      if (unpacked > maxUnpackedBytes) throw SkillException(_tooBig);
      final relative = path.substring(root.length);
      final isSkillFile = relative.toLowerCase() == 'skill.md';
      if (isSkillFile && bytes.length > maxSkillBytes) {
        throw SkillException(tr('{0} 太大(上限 256 KB)', [path]));
      }
      packages[root]![isSkillFile ? 'SKILL.md' : relative] = bytes;
    }

    final parsed = <UserSkill, Map<String, List<int>>>{};
    for (final MapEntry(key: root, value: files) in packages.entries) {
      final String text;
      try {
        text = utf8.decode(files['SKILL.md']!);
      } on FormatException {
        throw SkillException(tr('{0}SKILL.md 不是 UTF-8 文本', [root]));
      }
      // 没写名字时用它所在的文件夹名;在包的根目录就用压缩包的文件名。
      final folder = root.isEmpty
          ? _baseName(source)
          : root.substring(0, root.length - 1).split('/').last;
      final skill = parseSkill(text, fallbackName: folder);
      if (parsed.keys.any((s) => s.id == skill.id)) {
        throw SkillException(tr('压缩包里有两个同名的 Skill:{0}', [skill.name]));
      }
      parsed[skill] = files;
    }

    // 第三步:才开始写盘。
    for (final MapEntry(key: skill, value: files) in parsed.entries) {
      await _writePackage(skill.id, files);
    }
    return parsed.keys.toList();
  }

  /// 把一个 Skill 的全部文件写进它的文件夹。
  /// 先完整写到旁边的临时文件夹,写成了才换掉旧的;中途失败的话旧的原样保留。
  /// [files] 的键是用 `/` 分隔、已经检查过的相对路径。
  Future<void> _writePackage(String id, Map<String, List<int>> files) async {
    final folder = _folderFor(id);
    final staging = Directory(
      '${folder.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    Directory? previous;
    try {
      for (final MapEntry(key: relative, value: bytes) in files.entries) {
        final target = File(
          '${staging.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        );
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes, flush: true);
      }
      if (await folder.exists()) {
        previous = await folder.rename(
          '${folder.path}.old-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      try {
        await staging.rename(folder.path);
      } on FileSystemException {
        await previous?.rename(folder.path);
        rethrow;
      }
    } on FileSystemException {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
    if (previous != null) {
      try {
        await previous.delete(recursive: true);
      } on FileSystemException catch (e) {
        // 新版已换好,清理失败时保留旧目录,load 会跳过带点的备份。
        debugPrint('清理旧 Skill 备份失败:${e.message}');
      }
    }
  }

  Future<void> remove(String id) async {
    // 只删我们列出来的,不拿外面传进来的字符串去拼路径。
    if (!_skills.any((s) => s.id == id)) return;
    final folder = _folderFor(id);
    if (await folder.exists()) await folder.delete(recursive: true);
    await load();
  }
}
