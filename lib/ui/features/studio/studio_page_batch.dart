part of 'studio_view_model.dart';

/// 页签多选后的批量操作、跨系列拖动(2026-11-11 用户要求:Shift 多选,右键批量改名、
/// 出图、建立系列、删除;按住拖到别的系列的页上就挪过去)。下标都是 `_pages` 的下标。
extension StudioPageBatch on StudioViewModel {
  /// 把 [from] 这几页按原来的先后挪到第 [to] 页前面,并归进它的系列;
  /// 一个系列的页都挪走了,它的对话收进历史。眼前这页被挪走时人跟着它过去。
  String? movePages(Iterable<int> from, int to) {
    final moving = {
      for (final i in from)
        if (i >= 0 && i < _pages.length && i != to) i,
    };
    if (moving.isEmpty || to < 0 || to >= _pages.length) return null;
    if (isStreaming) return tr('正在生成,稍后再挪');
    final target = _pages[to].series;
    // 只是同系列里挪一页:走原来那条,记录写得具体些。
    if (moving.length == 1 && _pages[moving.single].series == target) {
      return movePage(moving.single, to);
    }
    _log(tr('挪 {0} 页到「{1}」', [moving.length, seriesName(target)]));
    final follow = moving.contains(_page);
    // 先站到不挪的那一页上,眼前这页才好拿走。
    if (follow) _show(to);
    final current = pages;
    final here = current[_page];
    final anchor = current[to];
    final moved = [
      for (final i in moving.toList()..sort())
        (
          series: target,
          name: current[i].name,
          blocks: current[i].blocks,
          pending: current[i].pending,
          queued: current[i].queued,
        ),
    ];
    final gone = {for (final i in moving) current[i].series};
    final rest = [
      for (final (k, p) in current.indexed)
        if (!moving.contains(k)) p,
    ];
    rest.insertAll(rest.indexWhere((p) => identical(p, anchor)), moved);
    _pages = List.unmodifiable(rest);
    _page = rest.indexWhere((p) => identical(p, here));
    for (final s in gone) {
      if (_pages.every((p) => p.series != s)) _forgetSeries(s);
    }
    if (follow) _show(_pages.indexWhere((p) => identical(p, moved.first)));
    _leftPage();
    return null;
  }

  /// 这几页一起另起一个系列(排到最后,对话从空白开始)。眼前这页在里面时人跟过去。
  String? groupPages(Iterable<int> which) {
    final picked = {
      for (final i in which)
        if (i >= 0 && i < _pages.length) i,
    };
    if (picked.isEmpty) return null;
    if (isStreaming) return tr('正在生成,稍后再试');
    if (seriesFull) return StudioPages.fullMessage;
    final stay = [
      for (var i = 0; i < _pages.length; i++)
        if (!picked.contains(i)) i,
    ].firstOrNull;
    if (stay == null) return tr('至少留一页在原来的系列');
    _log(tr('{0} 页建立系列', [picked.length]));
    final fresh =
        _pages.map((p) => p.series).reduce((a, b) => a > b ? a : b) + 1;
    final follow = picked.contains(_page);
    if (follow) _show(stay);
    final current = pages;
    final here = current[_page];
    final moved = [
      for (final i in picked.toList()..sort())
        (
          series: fresh,
          name: current[i].name,
          blocks: current[i].blocks,
          pending: current[i].pending,
          queued: current[i].queued,
        ),
    ];
    final gone = {for (final i in picked) current[i].series};
    _pages = List.unmodifiable([
      for (final (k, p) in current.indexed)
        if (!picked.contains(k)) p,
      ...moved,
    ]);
    _page = _pages.indexWhere((p) => identical(p, here));
    for (final s in gone) {
      if (_pages.every((p) => p.series != s)) _forgetSeries(s);
    }
    if (follow) _show(_pages.indexWhere((p) => identical(p, moved.first)));
    _leftPage();
    return null;
  }

  /// 删掉这几页;删完一页不剩时留一张空白页。
  String? removePages(Iterable<int> which) {
    final picked = {
      for (final i in which)
        if (i >= 0 && i < _pages.length) i,
    }.toList()..sort();
    if (picked.isEmpty) return null;
    if (isStreaming) return tr('正在生成,稍后再删');
    if (picked.length == _pages.length) return tr('至少留一页');
    return _asOneStep((_) => tr('删除 {0} 页', [picked.length]), () {
      // 从后往前删,前面的下标才不会变。
      for (final i in picked.reversed) {
        final problem = removePage(i);
        if (problem != null) return problem;
      }
      return null;
    });
  }

  /// 批量改名:按先后起成「名字 1」「名字 2」…;[base] 是空的就都去掉名字。
  void renamePages(Iterable<int> which, String base) {
    final picked = which.toList()..sort();
    final clean = base.trim();
    _asOneStep((_) => tr('{0} 页改名', [picked.length]), () {
      for (final (n, i) in picked.indexed) {
        renamePage(i, clean.isEmpty ? '' : '$clean ${n + 1}');
      }
    });
  }

  /// 第 [i] 页交付出去的提示词(出图用)。
  String finalPromptOf(int i) => i == _page
      ? finalPrompt
      : _joined(labels: false, blocks: _pages[i].blocks);
}
