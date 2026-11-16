import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/l10n.dart';
import '../../core/widgets.dart';

/// 用系统默认的程序打开一个文件(视频交给系统的播放器)。
Future<void> openWithSystem(String path) =>
    Process.run(Platform.isWindows ? 'explorer' : 'xdg-open', [path]);

/// 这次运行里的音量(0 到 1):下一个视频接着用。
double _volume = 1;

/// 一次前后跳多远(← →)。
const _skip = Duration(seconds: 5);

/// 在 Penna 里播放 [path] 这个视频(2026-11-16 用户要求:能来回拖、调音量)。
/// Windows 上用系统自带的解码(video_player_win,不另带解码库);
/// 别的系统没有这个播放器,交给系统的播放器。
// ponytail: Linux 上不在窗口里播(要带一整套 libmpv,没装时整个程序起不来);
// 要支持时换 media_kit 并把 libmpv 打进 AppImage。Windows 认不了的编码(少见)也交给系统播放器。
Future<void> showVideoPlayer(BuildContext context, String path) {
  if (!Platform.isWindows) return openWithSystem(path);
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _VideoDialog(path: path),
  );
}

class _VideoDialog extends StatefulWidget {
  const _VideoDialog({required this.path});

  final String path;

  @override
  State<_VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<_VideoDialog> {
  late final _player = VideoPlayerController.file(File(widget.path));
  bool _failed = false;

  /// 正拖着进度条时手指所在的位置(毫秒);没在拖是 null。
  double? _dragging;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      await _player.initialize();
      await _player.setLooping(true);
      await _player.setVolume(_volume);
      await _player.play();
    } on Object catch (e) {
      // 认不了的编码、文件没了:只记类型,界面上给「用系统播放器打开」。
      debugPrint('视频播放不了(${e.runtimeType})');
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _toggle() => _player.value.isPlaying ? _player.pause() : _player.play();

  void _seek(Duration to) {
    final end = _player.value.duration;
    _player.seekTo(
      to < Duration.zero
          ? Duration.zero
          : to > end
          ? end
          : to,
    );
  }

  void _setVolume(double v) {
    _volume = v.clamp(0, 1);
    _player.setVolume(_volume);
    setState(() {});
  }

  String _clock(Duration d) {
    String two(int n) => '$n'.padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final name = File(widget.path).uri.pathSegments.last;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _toggle,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _seek(_player.value.position - _skip),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _seek(_player.value.position + _skip),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _setVolume(_volume + 0.1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _setVolume(_volume - 0.1),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: const Color(0xFF111827),
          insetPadding: const EdgeInsets.all(32),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _titleBar(name),
                Flexible(child: _picture()),
                if (!_failed && _player.value.isInitialized) _controls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleBar(String name) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: Colors.white70),
          ),
        ),
        _button(
          tr('用系统播放器打开'),
          Icons.open_in_new,
          () => openWithSystem(widget.path),
        ),
        _button(tr('关闭'), Icons.close, () => Navigator.pop(context)),
      ],
    ),
  );

  Widget _picture() {
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('这个视频播放不了'),
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            PennaButton(
              label: tr('用系统播放器打开'),
              icon: Icons.open_in_new,
              foreground: Colors.white,
              borderColor: Colors.white30,
              onPressed: () => openWithSystem(widget.path),
            ),
          ],
        ),
      );
    }
    if (!_player.value.isInitialized) {
      return const Padding(
        padding: EdgeInsets.all(60),
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    // 点画面暂停 / 接着放。
    return GestureDetector(
      onTap: _toggle,
      child: AspectRatio(
        aspectRatio: _player.value.aspectRatio,
        child: VideoPlayer(_player),
      ),
    );
  }

  /// 播放 / 暂停、进度条(能拖)、时间、音量。
  Widget _controls() => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: _player,
    builder: (context, value, _) {
      final total = value.duration.inMilliseconds.toDouble();
      final at = (_dragging ?? value.position.inMilliseconds.toDouble()).clamp(
        0.0,
        total,
      );
      return SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white24,
          thumbColor: Colors.white,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 12, 4),
          child: Row(
            children: [
              _button(
                value.isPlaying ? tr('暂停') : tr('播放'),
                value.isPlaying ? Icons.pause : Icons.play_arrow,
                _toggle,
              ),
              Expanded(
                child: Slider(
                  value: at,
                  max: total <= 0 ? 1 : total,
                  onChanged: (v) => setState(() => _dragging = v),
                  onChangeEnd: (v) {
                    _seek(Duration(milliseconds: v.round()));
                    setState(() => _dragging = null);
                  },
                ),
              ),
              Text(
                '${_clock(Duration(milliseconds: at.round()))} / '
                '${_clock(value.duration)}',
                style: const TextStyle(fontSize: 11.5, color: Colors.white70),
              ),
              const SizedBox(width: 8),
              _button(
                tr('音量'),
                _volume == 0 ? Icons.volume_off : Icons.volume_up,
                () => _setVolume(_volume == 0 ? 1 : 0),
              ),
              SizedBox(
                width: 90,
                child: Slider(value: _volume, onChanged: _setVolume),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _button(String tip, IconData icon, VoidCallback onTap) => IconButton(
    tooltip: tip,
    iconSize: 18,
    color: Colors.white,
    icon: Icon(icon),
    onPressed: onTap,
  );
}
