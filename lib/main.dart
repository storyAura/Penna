import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/harness/characters/character_dict.dart';
import 'core/harness/local/model_scan.dart';
import 'core/harness/providers/llm_router.dart';
import 'core/harness/tags/tag_dictionary.dart';
import 'core/harness/tags/tag_search.dart';
import 'core/harness/update/updater.dart';
import 'data/models/app_config.dart';
import 'data/services/archive_store.dart';
import 'data/services/notebook_store.dart';
import 'data/services/character_store.dart';
import 'data/services/config_service.dart';
import 'data/services/error_log.dart';
import 'data/services/skill_store.dart';
import 'ui/core/look_switcher.dart';
import 'ui/core/theme.dart';
import 'ui/features/local/local_model.dart';
import 'ui/features/layout/layout_board.dart';
import 'ui/features/studio/studio_view_model.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 藏掉系统标题栏,换成 PennaApp 里自己画的那条(能放 logo 和字标图片)。
  await windowManager.ensureInitialized();
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  // 所有用户数据都放在「文档\Penna」下,方便找到和备份。
  // 设了环境变量 PENNA_HOME 就改用它指的文件夹(便携使用,或不碰真实数据地试用)。
  final sep = Platform.pathSeparator;
  final override = Platform.environment['PENNA_HOME'];
  final home = override != null && override.trim().isNotEmpty
      ? Directory(override.trim())
      : Directory(
          '${(await getApplicationDocumentsDirectory()).path}${sep}Penna',
        );
  final config = ConfigService(
    dir: home,
    legacyFile: ConfigService.defaultLegacyFile(),
  );
  _logErrors(
    ErrorLog(
      File('${home.path}${sep}error.log'),
      secrets: () => config.config.secrets.values,
    ),
  );
  final skills = SkillStore(Directory('${home.path}${sep}skills'));
  await config.load();
  applyLook(config.config);
  await skills.load();
  unawaited(clearOldUpdates());
  // 内置的 Danbooru 词库(压缩过的文本):在线搜索连不上时用它查,也用它核对标签。
  final tagDictionary = TagDictionary.parse(
    utf8.decode(
      gzip.decode(
        (await rootBundle.load('assets/danbooru_tags.tsv.gz')).buffer
            .asUint8List(),
      ),
    ),
  );
  // 角色库:用户自己存的角色,和内置的 Danbooru 角色(同样是压缩过的文本)。
  final characters = CharacterStore(home);
  await characters.load();
  final characterDict = CharacterDict.parse(
    utf8.decode(
      gzip.decode(
        (await rootBundle.load('assets/danbooru_characters.tsv.gz')).buffer
            .asUint8List(),
      ),
    ),
  );
  // 布局画板(画布尺寸、框和描述)存在 layout.json。
  final layout = LayoutBoard(
    dir: home,
    quality: () => config.config.layoutQuality,
  );
  await layout.load();
  // 工作台(成稿、对话、历史提示词)存在 workspace.json,下次打开接着用。
  final vm = StudioViewModel(
    config: config,
    streamChat: streamChat,
    skills: skills,
    tagDictionary: tagDictionary,
    tagSearch: tagSearcher(() => config.config, tagDictionary),
    characters: characters,
    characterDict: characterDict,
    layout: layout,
    saveFile: File('${home.path}${sep}workspace.json'),
  );
  await vm.load();
  // 布局页右边那场对话:和工作台的对话分开,存在 layout_chat.json。
  final layoutChat = StudioViewModel(
    config: config,
    streamChat: streamChat,
    skills: skills,
    tagDictionary: tagDictionary,
    tagSearch: tagSearcher(() => config.config, tagDictionary),
    characters: characters,
    characterDict: characterDict,
    layout: layout,
    layoutOnly: true,
    saveFile: File('${home.path}${sep}layout_chat.json'),
  );
  await layoutChat.load();
  final archive = ArchiveStore(File('${home.path}${sep}archive.json'));
  await archive.load();
  final notebooks = NotebookStore(File('${home.path}${sep}notebooks.json'));
  await notebooks.load();
  final local = LocalModel(
    dir: home,
    streamChat: streamChat,
    hfToken: () => config.config.secrets[hfTokenSecret] ?? '',
    autoFolders: cacheFolders(Platform.environment),
  );
  await local.load();
  // Agent 在对话里要用本地模型反推时,交给本地反推页这一份。
  vm.local = local;
  // 主工作区要排布局时,交给区域控制工作台的 Agent。
  vm.layoutAgent = layoutChat;
  // 关窗前先停掉本地反推起的 llama-server:Windows 不会跟着把它关掉。
  await windowManager.setPreventClose(true);
  runApp(
    PennaApp(
      config: config,
      skills: skills,
      vm: vm,
      layoutChat: layoutChat,
      archive: archive,
      notebooks: notebooks,
      local: local,
    ),
  );
}

/// 出的错都记进 [log]:各处存盘失败写的 debugPrint、界面里的异常、没人接的异步异常。
/// 界面异常也走 debugPrint(dumpErrorToConsole),所以只在 debugPrint 这一处写文件。
void _logErrors(ErrorLog log) {
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) {
    original(message, wrapWidth: wrapWidth);
    if (message != null) log.write(message);
  };
  // forceReport:默认第二个起只打一行摘要,日志里要完整的。
  FlutterError.onError = (details) =>
      FlutterError.dumpErrorToConsole(details, forceReport: true);
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('$error\n$stack');
    return true;
  };
}

/// 「界面大小」:按缩小了 [scale] 倍的窗口排版,再整个放大铺满,
/// 文字、图标、间距一起变大。倍数是 1 时也套着,换倍数时下面的状态不丢。
class _Scaled extends StatelessWidget {
  const _Scaled({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size / scale;
    return MediaQuery(
      data: mq.copyWith(
        size: size,
        devicePixelRatio: mq.devicePixelRatio * scale,
      ),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: size, child: child),
      ),
    );
  }
}

/// 标题栏左边的字标。
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/wordmark.png',
      height: 17,
      filterQuality: FilterQuality.medium,
    );
    if (!isDevBuild) return mark;
    // 测试版:右下角(最后那个 a 的下面是空的)标一个红色的 dev,和字标右边对齐。
    return Stack(
      clipBehavior: Clip.none,
      children: [
        mark,
        const Positioned(
          right: 0,
          bottom: -2,
          child: Text(
            'dev',
            style: TextStyle(
              fontSize: 8.5,
              height: 1,
              fontWeight: FontWeight.w700,
              // 红色,深浅两套配色上都看得清。
              color: Color(0xFFE5484D),
            ),
          ),
        ),
      ],
    );
  }
}

class PennaApp extends StatefulWidget {
  const PennaApp({
    super.key,
    required this.config,
    required this.skills,
    required this.vm,
    required this.layoutChat,
    required this.archive,
    required this.notebooks,
    required this.local,
  });

  final StudioViewModel layoutChat;

  final ArchiveStore archive;
  final NotebookStore notebooks;
  final LocalModel local;
  final StudioViewModel vm;
  final ConfigService config;
  final SkillStore skills;

  @override
  State<PennaApp> createState() => _PennaAppState();
}

class _PennaAppState extends State<PennaApp> with WindowListener {
  StudioViewModel get _vm => widget.vm;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  Future<void> onWindowClose() async {
    try {
      await widget.local.stopServer();
    } finally {
      await windowManager.destroy();
    }
  }

  // 主题只在字体或深浅色变了的时候重建,不跟着每次设置改动重算。
  (String, String, bool)? _look;
  late ThemeData _theme;

  ThemeData _themeFor(String latin, String cjk) {
    final look = (latin, cjk, PennaColors.isDark);
    if (_look != look) {
      _look = look;
      _theme = pennaTheme(latin: latin, cjk: cjk);
    }
    return _theme;
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.config,
      builder: (context, _) {
        final cfg = widget.config.config;
        return MaterialApp(
          title: 'Penna 羽毛笔',
          debugShowCheckedModeBanner: false,
          theme: _themeFor(cfg.fontLatin, cfg.fontCjk),
          // 深浅色切换有自己的扩散动画(LookSwitcher),主题不再渐变一遍。
          themeAnimationDuration: Duration.zero,
          // 触控板和拖动滚到头时有回弹;滚轮的平滑见 smooth_scroll.dart。
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            physics: const BouncingScrollPhysics(),
          ),
          // 标题栏放在 Navigator 外面:弹窗的遮罩盖不到它,窗口随时能拖。
          // ponytail: 整个界面不出无障碍语义树。Flutter 3.47 的 Windows 无障碍桥有空指针崩溃
          // (flutter/flutter#175041,accessibility_bridge.cc:229):有读屏、输入法这类 UIA
          // 程序在读窗口时,切页就会闪退。代价是读屏软件读不到 Penna;引擎修好后去掉这层。
          builder: (context, child) => ExcludeSemantics(
            child: _Scaled(
              scale: cfg.uiScale,
              child: LookSwitcher(
                config: widget.config,
                child: Column(
                  children: [
                    SizedBox(
                      height: kWindowCaptionHeight,
                      child: WindowCaption(
                        brightness: PennaColors.isDark
                            ? Brightness.dark
                            : Brightness.light,
                        backgroundColor: PennaColors.sidebar,
                        title: const _Brand(),
                      ),
                    ),
                    Expanded(child: child!),
                  ],
                ),
              ),
            ),
          ),
          home: AppShell(
            vm: _vm,
            layoutChat: widget.layoutChat,
            config: widget.config,
            skills: widget.skills,
            archive: widget.archive,
            notebooks: widget.notebooks,
            local: widget.local,
            checkUpdates: kReleaseMode,
          ),
        );
      },
    );
  }
}
