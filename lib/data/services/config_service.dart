import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_config.dart';
import 'dpapi.dart';
import '../../l10n/l10n.dart';

/// 读写用户设置,都放在 [dir](「文档\Penna」)下:
/// - `config.json`:普通设置,明文,可以直接打开看;
/// - `keys.dat`:API Key 等机密,用 Windows 数据保护加密,只有本机本用户能解开。
///
/// Windows 以外的平台没有 DPAPI,机密改放系统钥匙串(libsecret / Secret Service),
/// 同样是「只有本机本用户能解开」,也不落 `keys.dat`。
class ConfigService extends ChangeNotifier {
  ConfigService({required this.dir, this.legacyFile});

  final Directory dir;

  // ponytail: 旧版把设置放在 %APPDATA%\Penna、Key 放在系统凭据里;这里只在
  // 新位置还没有设置时搬一次。等没人再用旧版了,连同 flutter_secure_storage 一起删。
  /// 旧版的设置文件位置;传了就在首次启动时把旧设置和 Key 搬过来。
  final File? legacyFile;

  File get file => File('${dir.path}${Platform.pathSeparator}config.json');
  File get keysFile => File('${dir.path}${Platform.pathSeparator}keys.dat');

  /// 旧版的设置文件:%APPDATA%\Penna\config.json
  static File? defaultLegacyFile() {
    // 旧版只在 Windows 上有(%APPDATA%\Penna)。
    if (!Platform.isWindows) return null;
    final base = Platform.environment['APPDATA'];
    final sep = Platform.pathSeparator;
    return base == null ? null : File('$base${sep}Penna${sep}config.json');
  }

  AppConfig _config = const AppConfig();
  String? _loadError;
  String? _saveError;
  Future<void> _queue = Future.value();

  /// 已经确认写进 keys.dat 的机密;和它不一样才重写,失败的写入下次会重试。
  Map<String, String> _savedSecrets = const {};

  AppConfig get config => _config;

  /// 读写失败的说明,给界面展示。读取失败的提示会一直留到下次启动。
  String? get lastError => _saveError ?? _loadError;

  Future<void> load() async {
    await _migrateLegacy();
    var loaded = const AppConfig();
    try {
      if (await file.exists()) {
        loaded = AppConfig.fromJson(jsonDecode(await file.readAsString()));
      }
    } on Object catch (e) {
      _loadError = tr('读取设置失败,已改用默认设置:{0}', [e]);
      await _setAside(file);
    }
    // 机密单独读:Key 文件出问题时,不能连带丢掉读好的普通设置。
    try {
      _savedSecrets = await _readSecrets();
    } on Object {
      _loadError = Platform.isWindows
          ? tr('{0}已保存的 Key 读不出来(可能不是在这台电脑上保存的),请重新填写', [_loadError ?? ''])
          : tr('{0}读不了系统钥匙串,请装好 gnome-keyring 或 KWallet', [_loadError ?? '']);
      // 留底:否则下次填 Key 时会把这份读不了的文件直接覆盖掉。
      await _setAside(keysFile);
    }
    _config = loaded.copyWith(secrets: _savedSecrets);
    notifyListeners();
  }

  Future<void> _migrateLegacy() async {
    final old = legacyFile;
    if (old == null || await file.exists() || !await old.exists()) return;
    try {
      const storage = FlutterSecureStorage();
      final secrets = await storage.readAll();
      await dir.create(recursive: true);
      // 先写 Key,最后才放 config.json:它是"搬完了"的记号。
      // 中途失败的话 config.json 不存在,下次启动会整个重搬,Key 不会被落下。
      if (secrets.isNotEmpty) await _writeSecrets(secrets);
      await old.copy(file.path);
      // 新位置都写好了,才清掉旧的,免得 Key 留在两个地方。
      await old.rename('${old.path}.migrated');
      await storage.deleteAll();
    } on Object catch (e) {
      _loadError = tr('搬迁旧设置时出错:{0}。', [e.runtimeType]);
    }
  }

  /// 非 Windows 平台上机密在系统钥匙串里的条目名。带着数据文件夹的路径:
  /// 用 PENNA_HOME 换了文件夹(试用、测试)时不碰真实的 Key。
  String get _secretKey => 'penna.keys:${dir.absolute.path}';

  Future<Map<String, String>> _readSecrets() async {
    if (!Platform.isWindows) {
      final stored = await const FlutterSecureStorage().read(key: _secretKey);
      if (stored == null || stored.isEmpty) return const {};
      return Map.unmodifiable(
        (jsonDecode(stored) as Map).cast<String, String>(),
      );
    }
    if (!await keysFile.exists()) return const {};
    final cipher = base64.decode((await keysFile.readAsString()).trim());
    final json = jsonDecode(utf8.decode(dpapiUnprotect(cipher)));
    return Map.unmodifiable((json as Map).cast<String, String>());
  }

  Future<void> _writeSecrets(Map<String, String> secrets) async {
    if (!Platform.isWindows) {
      await const FlutterSecureStorage().write(
        key: _secretKey,
        value: jsonEncode(secrets),
      );
      return;
    }
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(secrets)));
    await _replace(keysFile, base64.encode(dpapiProtect(plain)));
  }

  /// 先写临时文件再改名:中途断电也不会留下半截的文件。
  Future<void> _replace(File target, String content) async {
    await dir.create(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(content, flush: true);
    await temp.rename(target.path);
  }

  /// 把读不了的设置文件改名留底,免得下次保存把它覆盖掉。
  Future<void> _setAside(File broken) async {
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      if (await broken.exists()) {
        await broken.rename('${broken.path}.bad-$stamp');
      }
    } on FileSystemException catch (e) {
      _loadError = tr('{0}(给原文件留底也失败:{1})', [_loadError, e.message]);
    }
  }

  /// 立即生效,并排队写盘(保证先后顺序)。
  void update(AppConfig next) {
    _config = next;
    notifyListeners();
    _queue = _queue
        .then((_) => _persist(next))
        .then(
          (_) => _setSaveError(null),
          onError: (Object e) =>
              _setSaveError(tr('保存设置失败:{0}', [e.runtimeType])),
        );
  }

  void _setSaveError(String? error) {
    if (_saveError == error) return;
    _saveError = error;
    notifyListeners();
  }

  /// 等所有排队的写入完成。
  Future<void> flushed() => _queue;

  Future<void> _persist(AppConfig next) async {
    await _replace(
      file,
      const JsonEncoder.withIndent('  ').convert(next.toJson()),
    );
    // 空值等于没填,不存。
    final secrets = {
      for (final e in next.secrets.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
    if (mapEquals(secrets, _savedSecrets)) return;
    await _writeSecrets(secrets);
    _savedSecrets = Map.unmodifiable(secrets);
  }
}
