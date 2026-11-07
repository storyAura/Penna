part of 'comfy_runner.dart';

/// 出图队列里的一单处在哪一步。
enum ComfyJobState { waiting, running, done, failed, canceled }

/// 一次出图结果:出的图和出错的原因(停止了两个都是空的)。
typedef ComfyResult = ({List<GeneratedImage> images, String? error});

/// 出图队列里的一单(2026-11-08 用户要求:正在出图时再点不报错,排进队列)。
@immutable
class ComfyJob {
  const ComfyJob({
    required this.id,
    required this.prompt,
    required this.queued,
    this.owner,
    this.started,
    this.finished,
    this.images = const [],
    this.error,
    this.state = ComfyJobState.waiting,
  });

  final int id;
  final String prompt;

  /// 谁要的(对话里那条回复的时刻;工作台的按钮是 null)。不存盘。
  final Object? owner;
  final DateTime queued;
  final DateTime? started;
  final DateTime? finished;

  /// 出的图的路径。
  final List<String> images;
  final String? error;
  final ComfyJobState state;

  /// 出这一张用了多久(从开始出到出完,不算排队);没出完是 null。
  Duration? get took => started == null || finished == null
      ? null
      : finished!.difference(started!);

  ComfyJob copyWith({
    DateTime? started,
    DateTime? finished,
    List<String>? images,
    String? error,
    ComfyJobState? state,
  }) => ComfyJob(
    id: id,
    prompt: prompt,
    owner: owner,
    queued: queued,
    started: started ?? this.started,
    finished: finished ?? this.finished,
    images: images == null ? this.images : List.unmodifiable(images),
    error: error ?? this.error,
    state: state ?? this.state,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'prompt': prompt,
    'queued': queued.toIso8601String(),
    if (started != null) 'started': started!.toIso8601String(),
    if (finished != null) 'finished': finished!.toIso8601String(),
    if (images.isNotEmpty) 'images': images,
    if (error != null) 'error': error,
    'state': state.name,
  };

  static ComfyJob fromJson(Map<String, dynamic> j) {
    DateTime? at(String key) =>
        j[key] == null ? null : DateTime.tryParse('${j[key]}');
    return ComfyJob(
      id: (j['id'] as num).toInt(),
      prompt: '${j['prompt'] ?? ''}',
      queued: at('queued') ?? DateTime(2000),
      started: at('started'),
      finished: at('finished'),
      images: List.unmodifiable([
        for (final p in j['images'] as List? ?? const []) '$p',
      ]),
      error: j['error'] as String?,
      state: ComfyJobState.values.firstWhere(
        (s) => s.name == j['state'],
        orElse: () => ComfyJobState.done,
      ),
    );
  }
}

/// 队列记录最多留几单(图的文件都还在文件夹里)。
const _maxJobs = 100;

extension ComfyQueue on ComfyRunner {
  /// 排进队列,轮到时出图;等它出完再返回。前面没有在出的就马上出。
  Future<ComfyResult> generate(String prompt, {Object? owner}) {
    if (prompt.trim().isEmpty) {
      return Future.value((
        images: const <GeneratedImage>[],
        error: tr('没有可出图的提示词'),
      ));
    }
    final job = ComfyJob(
      id: ++_jobSeq,
      prompt: prompt,
      owner: owner,
      queued: DateTime.now(),
    );
    final done = Completer<ComfyResult>();
    _waiters[job.id] = done;
    _jobs = List.unmodifiable([job, ..._jobs]);
    _changed();
    unawaited(_pump());
    return done.future;
  }

  /// 还在排队、没轮到的有几单。
  int get waiting =>
      _jobs.where((j) => j.state == ComfyJobState.waiting).length;

  /// 排在 [owner] 那单前面还有几单在等(含正在出的);它不在排队时是 null。
  int? aheadOf(Object owner) {
    final waiting = _jobs.reversed
        .where((j) => j.state == ComfyJobState.waiting)
        .toList();
    final i = waiting.indexWhere((j) => j.owner == owner);
    if (i < 0) return null;
    return i + (_running ? 1 : 0);
  }

  /// 撤掉一单:还在排队的直接撤,正在出的停下。
  void cancel(int id) {
    final job = _jobs.where((j) => j.id == id).firstOrNull;
    if (job == null) return;
    if (job.state == ComfyJobState.running) return stop();
    if (job.state != ComfyJobState.waiting) return;
    _setJob(id, (j) => j.copyWith(state: ComfyJobState.canceled));
    _waiters.remove(id)?.complete((
      images: const <GeneratedImage>[],
      error: null,
    ));
    _changed();
    _saveJobs();
  }

  /// 从记录里去掉出完的(排队的、正在出的留着)。
  void clearFinished() {
    _jobs = List.unmodifiable(
      _jobs.where(
        (j) =>
            j.state == ComfyJobState.waiting ||
            j.state == ComfyJobState.running,
      ),
    );
    _changed();
    _saveJobs();
  }

  /// 没在出图时,取最早排进来的一单出;出完接着下一单。
  Future<void> _pump() async {
    if (_running) return;
    final next = _jobs.reversed
        .where((j) => j.state == ComfyJobState.waiting)
        .firstOrNull;
    if (next == null) return;
    _setJob(
      next.id,
      (j) => j.copyWith(state: ComfyJobState.running, started: DateTime.now()),
    );
    final result = await _execute(next.prompt, owner: next.owner);
    _setJob(
      next.id,
      (j) => j.copyWith(
        finished: DateTime.now(),
        images: [for (final g in result.images) g.path],
        error: result.error,
        state: result.error != null
            ? ComfyJobState.failed
            : result.images.isEmpty
            ? ComfyJobState.canceled
            : ComfyJobState.done,
      ),
    );
    _trimJobs();
    _changed();
    _saveJobs();
    _waiters.remove(next.id)?.complete(result);
    await _pump();
  }

  /// 出完的最多留 [_maxJobs] 单;排着的、正在出的都留着。
  void _trimJobs() {
    var kept = 0;
    _jobs = List.unmodifiable([
      for (final j in _jobs)
        if (j.state == ComfyJobState.waiting ||
            j.state == ComfyJobState.running ||
            kept++ < _maxJobs)
          j,
    ]);
  }

  void _setJob(int id, ComfyJob Function(ComfyJob) change) {
    _jobs = List.unmodifiable([
      for (final j in _jobs) j.id == id ? change(j) : j,
    ]);
  }

  File get _jobsFile =>
      File('${config.dir.path}${Platform.pathSeparator}comfy_queue.json');

  /// 读回上次的记录。读不了的改名留底,从空的开始。
  Future<void> _loadJobs() async {
    final file = _jobsFile;
    if (!file.existsSync()) return;
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      final old = [
        for (final j in list.cast<Map<String, dynamic>>()) ComfyJob.fromJson(j),
      ];
      // 上次没出完就关了的,算撤掉。
      final loaded = [
        for (final j in old)
          j.state == ComfyJobState.waiting || j.state == ComfyJobState.running
              ? j.copyWith(state: ComfyJobState.canceled)
              : j,
      ];
      _jobs = List.unmodifiable([..._jobs, ...loaded]);
      _jobSeq = [_jobSeq, for (final j in _jobs) j.id].reduce(max);
      _changed();
    } on Object catch (e) {
      debugPrint(tr('出图队列读不了:{0}', [e.runtimeType]));
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.rename('${file.path}.bad-$stamp');
    }
  }

  /// 只存出完的,最多 [_maxJobs] 单;排着写,不会两次写串了。
  void _saveJobs() {
    final finished = [
      for (final j in _jobs)
        if (j.state != ComfyJobState.waiting &&
            j.state != ComfyJobState.running)
          j.toJson(),
    ].take(_maxJobs).toList();
    final text = jsonEncode(finished);
    _saving = _saving.then((_) async {
      try {
        await _jobsFile.writeAsString(text);
      } on FileSystemException catch (e) {
        debugPrint(tr('出图队列没存上:{0}', [e.message]));
      }
    });
  }
}
