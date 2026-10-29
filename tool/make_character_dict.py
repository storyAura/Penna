"""把 dataset/ 里的 Danbooru 角色表(一份或分成几份都行)精简成内置的角色库 assets/danbooru_characters.tsv.gz。

用法(在项目根目录):
    python tool/make_character_dict.py [放着 danbooru_character_dedup*.csv 的文件夹,默认 dataset]
    python tool/make_character_dict.py dataset --review   # 另外打印两类词各有哪些,用来检查分得对不对
    python tool/make_character_dict.py dataset/danbooru_character_appearance.csv
        # 已经分好的整表(列是 name, series, looks, outfit, alias)直接打包,不再分词;
        # 现在内置的就是这张,来自 https://huggingface.co/datasets/StoryAura/Danbooru-Dataset-csv
        # 同一个文件夹里有 danbooru_character_forms.csv(tool/fetch_character_forms.py 抓的)时,
        # 每行多一列「是哪个角色的形态」

每行输出「角色名 \t 作品 \t 外貌 \t 服装与其他 \t 别名」,按图的数量从多到少排;名字里的下划线换成空格。
别名(中文、日文译名)来自同一个文件夹里的 danbooru_character_tags.csv,没有这个文件就留空;
它从 https://huggingface.co/datasets/StoryAura/Danbooru-Dataset-csv 下载。
表里的 core_tags 在这里就分成两半:
    外貌        发型发色、眼睛、体型、肤色、种族特征(兽耳、角、尾巴、翅膀……)
    服装与其他  衣服、饰品、道具,以及露肤、姿势这类跟着衣服和画面走的词
用户只要角色的长相、不要原来那身衣服时,只用「外貌」那一半。

太冷门又没有特征词的不收(少于 MIN_COUNT 张图且 core_tags 是空的):
只有一个名字的条目帮不上忙,还会把搜索结果挤乱。
"""

import csv
import glob
import gzip
import io
import os
import re
import sys
from collections import Counter

MIN_COUNT = 10
ALIASES = 'danbooru_character_tags.csv'
MAX_ALIAS = 200

# 人数、体型、年龄、种族这些整个词就是外貌的。
_WHOLE = {
    'no humans', 'loli', 'shota', 'bishounen', 'bara', 'plump', 'fat', 'petite',
    'ahoge', 'sidelocks', 'twintails', 'ponytail', 'heterochromia', 'freckles',
    'android', 'robot', 'cyborg', 'mecha', 'furry', 'elf', 'halo', 'tattoo',
    'bald', 'abs', 'dark skin', 'tan', 'albino', 'antlers', 'multiple tails',
    'virtual youtuber', 'pokemon (creature)', 'duel monster', 'mobile suit',
    'animal', 'cat', 'dog', 'bird', 'horse', 'dragon', 'monster', 'creature',
    'third eye', 'old', 'child', 'aged down', 'aged up', 'giant', 'giantess',
    'personification', 'humanization', 'mecha musume', 'ghost', 'zombie',
    'skeleton', 'slime (creature)', 'fairy', 'mermaid', 'centaur', 'lamia',
    'harpy', 'vampire', 'angel', 'demon', 'oni', 'kemonomimi mode',
}
_COUNT = re.compile(r'^(\d\+?|multiple )(girl|boy|other)s?$')
_LOOKS = re.compile(
    r'\b(hair|hairstyle|eyes?|bangs|braids?|buns?|drills?|pigtails|mohawk|afro|'
    r'dreadlocks|topknot|updo|locks|forelock|ringlets|ponytail|twintails|'
    r'(hime|bob|pixie|bowl|buzz|crew) cut|undercut|one side up|two side up|'
    r'breasts|pectorals|chest|skin|skinned|ears?|tails?|horns?|wings?|fangs?|'
    r'teeth|tooth|tusks?|moles?|scars?|pupils|sclera|eyebrows|eyelashes|lips|'
    r'nose|beard|mustache|goatee|stubble|sideburns|facial hair|muscular|'
    r'chubby|tall|mature|girl|boy|male|female|man|woman|furry|fur|claws?|scales|'
    r'beak|snout|tentacles|antennae|markings?|mark|whiskers?|whisker markings|'
    r'blush stickers|body|thick thighs|wide hips|curvy|slim|toned|joints|'
    r'humanoid|eyeshadow|eyeliner|makeup|colored tips|tanlines?|height)\b'
)
# 带着这些词的是穿戴上去的东西(兽耳发箍、毛领、耳环……),不是长在身上的。
_WORN = re.compile(
    r'\b(fake|hood|hooded|print|costume|hat|cap|headwear|helmet|headphones|'
    r'ornament|ribbon|bow|bell|piercing|ring|trim|trimmed|coat|collar|scarf|'
    r'jacket|dress|shirt|skirt|swimsuit|bikini|cosplay|mask|covers?|tag|cuffs?|'
    r'band|clip|pin|shorts|pants|gloves?|boots|shoes|socks|thighhighs|pantyhose|'
    r'leotard|kimono|uniform|armor|cape|cloak|sleeves?|necktie|choker|glasses|'
    r'eyewear|eyepatch|bag|sword|gun|holding|pasties|bandaid|bandages?|jewel|'
    r'tubes|bobbles|scrunchie|flower|tie|stick|beads|magical|topless|focus|'
    r'official alternate|alternate|window|strap|straps|grab|pull|between|'
    r'hairband|hairclip|hairpin|headband|necklace|earrings?|pov|another)\b'
)
# 上面那条会误伤的几个:它们说的还是头发、眼睛本身。
_STILL_LOOKS = re.compile(
    r'^(hair between eyes|hair over (one eye|eyes|shoulder|breasts)|hair rings|'
    r'hair bun|single hair bun|double bun|hair intakes|hair flaps|hair down|'
    r'hair up|eyes visible through hair|short hair with long locks|'
    r'low-tied long hair|sidelocks tied back|one eye covered|hair behind ear)$'
)


def is_looks(tag: str) -> bool:
    if tag in _WHOLE or _COUNT.match(tag) or _STILL_LOOKS.match(tag):
        return True
    return bool(_LOOKS.search(tag)) and not _WORN.search(tag)


def clean(text: str) -> str:
    return ' '.join(text.replace('\t', ' ').replace('_', ' ').split())


def cut(names: str) -> str:
    """别名太多的只留前面几个:整个整个地留,不把一个名字截成半个。"""
    out = ''
    for name in (' '.join(n.replace('\t', ' ').split()) for n in names.split(',')):
        if name and len(out) + len(name) <= MAX_ALIAS:
            out += (', ' if out else '') + name
    return out


def aliases(folder: str) -> dict[str, str]:
    path = os.path.join(folder, ALIASES)
    if not os.path.exists(path):
        print('没有', ALIASES, ',别名留空')
        return {}
    with io.open(path, encoding='utf-8-sig', newline='') as f:
        return {
            clean(row['character_tag']): cut(row['other_names'])
            for row in csv.DictReader(f)
            if row['other_names'].strip()
        }


def main(folder: str, review: bool) -> None:
    alias = aliases(folder)
    rows = {}
    for path in sorted(glob.glob(os.path.join(folder, 'danbooru_character_dedup*.csv'))):
        with io.open(path, encoding='utf-8-sig', newline='') as f:
            for row in csv.DictReader(f):
                name = clean(row['character'])
                try:
                    count = int(float(row['count'] or 0))
                except ValueError:
                    continue
                tags = [t.strip() for t in row['core_tags'].split(',') if t.strip()]
                if not name or (count < MIN_COUNT and not tags):
                    continue
                if name not in rows or rows[name][0] < count:
                    rows[name] = (count, clean(row['copyright']), tags)
    if not rows:
        sys.exit(f'{folder} 里没有 danbooru_character_dedup*.csv')

    ordered = sorted(rows.items(), key=lambda kv: -kv[1][0])
    seen = {True: Counter(), False: Counter()}
    lines = []
    for name, (_, series, tags) in ordered:
        looks = [t for t in tags if is_looks(t)]
        worn = [t for t in tags if not is_looks(t)]
        seen[True].update(looks)
        seen[False].update(worn)
        lines.append('\t'.join(
            [name, series, ', '.join(looks), ', '.join(worn), alias.get(name, '')]))
    out = os.path.join('assets', 'danbooru_characters.tsv.gz')
    with io.open(out, 'wb') as f:
        f.write(gzip.compress('\n'.join(lines).encode('utf-8'), 9))
    described = sum(1 for _, (_, _, tags) in ordered if tags)
    named = sum(1 for name, _ in ordered if name in alias)
    print(len(ordered), 'characters (', described, 'with tags,', named, 'with aliases) ->', out,
          round(os.path.getsize(out) / 1e6, 2), 'MB')
    if review:
        for looks, title in ((True, '外貌'), (False, '服装与其他')):
            print(f'\n== {title}:{len(seen[looks])} 种')
            print(', '.join(t for t, _ in seen[looks].most_common(260)))


FINISHED = ['name', 'series', 'looks', 'outfit', 'alias']
FORMS = 'danbooru_character_forms.csv'


def parents(folder: str, rows: list[list[str]]) -> dict[str, str]:
    """每个形态(变身、换装后的另一个角色标签)属于哪个角色,都换成表里的名字。

    两个来源,都在整表旁边:danbooru_character_tags.csv 的 parent_tag(Danbooru 的父标签),
    和 tool/fetch_character_forms.py 从角色 wiki 的「Appearance」这类小节抓的 FORMS。
    两边都要在表里、是同一部作品;一层层往上找到最上面那个(不成环),所以一个角色的
    所有形态都挂在同一个名字上。
    """
    series = {r[0]: r[1] for r in rows}
    # 角色表里的名字可能是旧的(改过名),旧名在别名里。
    renamed = {}
    for name, _, _, _, alias in rows:
        for a in alias.split(', '):
            if a.isascii() and a:
                renamed.setdefault(clean(a).lower(), name)

    def known(tag: str) -> str | None:
        name = clean(tag).lower()
        return name if name in series else renamed.get(name)

    links = []
    path = os.path.join(folder, ALIASES)
    if os.path.exists(path):
        with io.open(path, encoding='utf-8-sig', newline='') as f:
            links += [(r['parent_tag'], r['character_tag'])
                      for r in csv.DictReader(f) if r['parent_tag'].strip()]
    path = os.path.join(folder, FORMS)
    if os.path.exists(path):
        with io.open(path, encoding='utf-8-sig', newline='') as f:
            links += [(r['parent'], r['form']) for r in csv.DictReader(f)]
    else:
        print('没有', FORMS, ',只用父标签(先跑 tool/fetch_character_forms.py)')

    up = {}

    def top(name: str) -> str:
        seen = set()
        while name in up and name not in seen:
            seen.add(name)
            name = up[name]
        return name

    for parent, form in links:
        parent, form = known(parent), known(form)
        if not parent or not form or parent == form or form in up:
            continue
        a, b = series[parent], series[form]
        if a and b and a != b:
            continue
        if top(parent) != form:
            up[form] = parent
    return {form: top(form) for form in up}


def from_table(path: str) -> None:
    """已经分好外貌、服装的整表(列是 FINISHED 那五个,按热门程度排好)直接打包。
    每行最后多一列:它是哪个角色的形态(见 [parents]),不是形态的留空。"""
    rows = []
    with io.open(path, encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != FINISHED:
            sys.exit(f'{path} 的列应该是 {", ".join(FINISHED)}')
        for row in reader:
            name = clean(row['name'])
            if name:
                rows.append([
                    name, clean(row['series']), clean(row['looks']),
                    clean(row['outfit']), cut(row['alias'])])
    parent = parents(os.path.dirname(path), rows)
    lines = ['\t'.join([*r, parent.get(r[0], '')]) for r in rows]
    out = os.path.join('assets', 'danbooru_characters.tsv.gz')
    with io.open(out, 'wb') as f:
        f.write(gzip.compress('\n'.join(lines).encode('utf-8'), 9))
    print(len(lines), 'characters (', len(parent), 'forms of',
          len(set(parent.values())), 'characters) ->', out,
          round(os.path.getsize(out) / 1e6, 2), 'MB')


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if args and args[0].lower().endswith('.csv'):
        from_table(args[0])
    else:
        main(args[0] if args else 'dataset', '--review' in sys.argv)
