"""把用户的主美知识库(skill组/知识库相关,不进仓库)整理成内置 Skill「哈吉咪主美」的模块。

用法: python tool/make_hajimi_skill.py <skill组目录> [--dry]
结果写进 assets/skills/hajimi/:每个模块拆成 <代码>.md(铁律与做法)和 <代码>-母题.md(母题库,大);
和 Penna 冲突的小节(负面词、开场报头、交付面板、跨技能握手)整节删掉。
目录(SKILL 正文)在 lib/core/harness/skills/hajimi_skill.dart,模块名单 hajimiParts 也在那,
改了模块要一起改;分镜流程.md 是手写的,这个脚本不碰。
"""
import re
import sys
import zipfile
from pathlib import Path

KB = '知识库相关'
MODULES = {  # 代码: 源文件(每组只留最新版)
    'F00': '分镜头相关/动画电影级叙事场景 & 分镜构图导演系统 (v2.0 零画风污染 · 千里巨构纵深 · 故事板时空锁死版).md',
    'F01': '构图美学整合/00_master_orchestrator_skill.md',
    'F02': '构图美学整合/01_composition_and_rhythm_reference.md',
    'F03': '构图美学整合/02_sketch_and_value_matrix_reference.md',
    'F04': '构图美学整合/03_color_anti_muddy_guide_reference.md',
    'F05': '构图美学整合/04_prompt_and_layout_compiler_reference.md',
    'A01': '角色设计/哈吉咪的二次元角色设计 SKILL 0.2 增强版.md',
    'A02': '丝袜质感/哈吉咪的二次元丝袜与腿部微观光学质感 SKILL 0.2 (.md',
    'A03': '角色设计/哈吉咪的二次元角色设定表 SKILL 0.2 修正版.md',
    'A04': '精英化2立绘相关/二次元抽卡手游精英化2（精二）立绘导演系统 (v4.5 去眼球化焦点重构 & 万物拟人版).md',
    'A05': '怪物设计/哈吉咪的二次元怪物、敌方武装与异形BOSS设计 SKILL 0.2 .md',
    'A06': '地图设计/哈基米的地图SKILL0.3 .md',
    'T-EMO': '张力相关/哈吉咪的故事潜台词、宿命反差与情绪暗流张力导演系统 SKILL 0.1.md',
    'T-POV': 'P站大透视/p_cg_skill_0_2.md',
    'T-ACT': '张力相关/哈吉咪的张力战斗导演 SKILL 0.2 .md',
    'T-DUO': '张力相关/哈吉咪的双人宿命对峙、体型差压迫与主从纠缠调度系统 SKILL 0.1 .md',
    'T-ENV': '张力相关/哈吉咪的极端环境物理、天灾异变与失衡空间张力导演系统 SKILL 0.1.md',
    'T-PSY': '张力相关/哈吉咪的心理崩坏、颜艺爆发与光影象征演出导演系统 SKILL 0.1.md',
}
# 模块本身太小时不拆母题(构图那几份本来就是短的参考)。
SPLIT_MIN = 12000
# 二级标题:整节是交付格式、开场白、和别的技能对接的,删。
DROP = re.compile(
    r'交付面板|标准化交付|标准交付|Deliverable|开场|Onboarding|首次被调用|报头|联动管线|Pipeline|握手|Handshake|联合创作'
)
# 三级标题:负面词和对接协议,删;编译模板留着当写法参考。
DROP_SUB = re.compile(r'负面|Negative|握手|Handshake|联合创作')
CATALOG = re.compile(r'母题|全集|子分类|弹药库|速查|索引库|百科|Motif', re.I)


def sections(text, level):
    """按 level 级标题切开:[(标题行或'', 正文)]。代码块里的 # 不算标题。"""
    out, head, buf, fence = [], '', [], False
    mark = '#' * level + ' '
    for line in text.splitlines():
        if line.lstrip().startswith('```'):
            fence = not fence
        if not fence and line.startswith(mark):
            out.append((head, '\n'.join(buf)))
            head, buf = line, []
        else:
            buf.append(line)
    out.append((head, '\n'.join(buf)))
    return out


def strip_front(text):
    text = text.lstrip('﻿').replace('\\---', '---')
    m = re.match(r'\s*---\n.*?\n---\n', text, re.S)
    if m:
        text = text[m.end():]
    # 有一份的文件头被写成了「## name: …」加一行 description。
    text = re.sub(r'\A\s*## name:.*\n(description:.*\n)?', '', text)
    return text.strip() + '\n'


def drop_sub(body, log):
    """删掉正文里冲突的三级小节。"""
    kept = []
    for head, part in sections(body, 3):
        if head and DROP_SUB.search(head):
            log.append(f'      删 {head[:60]}')
            continue
        kept.append((head + '\n' if head else '') + part)
    return '\n'.join(kept)


def build(code, text, log):
    core, catalog = [], []
    small = len(text.encode()) < SPLIT_MIN
    for head, body in sections(strip_front(text), 2):
        if head and DROP.search(head):
            log.append(f'   删 {head[:70]}')
            continue
        body = drop_sub(body, log)
        piece = (head + '\n' if head else '') + body
        if head and not small and CATALOG.search(head):
            log.append(f'   母题 {head[:70]}')
            catalog.append(piece)
        else:
            if head:
                log.append(f'   核心 {head[:70]}')
            core.append(piece)
    tidy = lambda parts: re.sub(r'\n{3,}', '\n\n', '\n'.join(parts)).strip() + '\n'
    files = {f'{code}.md': tidy(core)}
    if catalog:
        files[f'{code}-母题.md'] = tidy(catalog)
        files[f'{code}.md'] += f'\n> 母题库在 `{code}-母题`,要挑母题时再加载。\n'
    return files


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    root = Path(sys.argv[1])
    dry = '--dry' in sys.argv
    out = {}
    for code, rel in MODULES.items():
        log = []
        text = (root / KB / rel).read_text(encoding='utf-8')
        files = build(code, text, log)
        sizes = ', '.join(f'{k} {len(v.encode()) // 1024}K' for k, v in files.items())
        print(f'{code}: {sizes}')
        if dry:
            print('\n'.join(log))
        out.update(files)
    if dry:
        return
    folder = Path(__file__).resolve().parent.parent / 'assets' / 'skills' / 'hajimi'
    folder.mkdir(parents=True, exist_ok=True)
    for name, text in out.items():
        (folder / name).write_text(text, encoding='utf-8', newline='\n')
    print(f'写好 {len(out)} 个模块 -> {folder}')
    print('名单:', ', '.join(sorted(n[:-3] for n in out)))


main()
