part of 'chat_pane.dart';

/// 点子前面轮流用的图标(样子照 ChatGPT 新对话下面那一列)。
const _ideaIcons = [
  Icons.image_outlined,
  Icons.brush_outlined,
  Icons.auto_stories_outlined,
  Icons.palette_outlined,
];

/// 空对话:一句提示,下面一列创作点子(设置里能关,见 [StudioIdeas])。
class _ChatIdeas extends StatelessWidget {
  const _ChatIdeas({required this.vm, required this.onPick});

  final StudioViewModel vm;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final ideas = vm.ideaList ?? const <String>[];
    final muted = TextStyle(fontSize: 13, color: PennaColors.slate400);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('描述画面,或贴上要改的提示词'),
                textAlign: TextAlign.center,
                style: muted,
              ),
              AnimatedSize(
                duration: Motion.of(context, Motion.base),
                curve: Motion.expand,
                alignment: Alignment.topCenter,
                child: vm.ideasBusy
                    ? Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox.square(
                              dimension: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: PennaColors.slate400,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(tr('正在想点子'), style: muted),
                          ],
                        ),
                      )
                    : ideas.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: PopIn(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, idea) in ideas.indexed)
                                _IdeaRow(
                                  icon: _ideaIcons[i % _ideaIcons.length],
                                  text: idea,
                                  onTap: () => onPick(idea),
                                ),
                              _IdeaRow(
                                icon: Icons.refresh,
                                text: tr('换一批'),
                                muted: true,
                                onTap: vm.refreshIdeas,
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdeaRow extends StatelessWidget {
  const _IdeaRow({
    required this.icon,
    required this.text,
    required this.onTap,
    this.muted = false,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 17, color: PennaColors.slate500),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: muted ? 12 : 13.5,
                color: muted ? PennaColors.slate400 : PennaColors.slate700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
