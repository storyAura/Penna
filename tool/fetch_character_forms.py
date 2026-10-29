"""从 Danbooru 的角色 wiki 里抓出「同一个角色的各个形态」,写成 dataset/danbooru_character_forms.csv。

用法(在项目根目录,要联网,十来分钟):
    python tool/fetch_character_forms.py [输出的 csv,默认 dataset/danbooru_character_forms.csv]

有的角色变身、换装后是另一个角色标签,名字和本名对不上,也不挂父标签,
比如 moria_luluka 的 wiki 在「Appearance」一节列着 cure_arcana_shadow、cure_arcana。
这里把每个角色 wiki 里讲外观、服装、形态的那几节(_FORM_HEADING)里链接到的标签记下来,
每行「parent, form」(Danbooru 标签原样,带下划线)。
是不是角色、是不是同一部作品,留给 make_character_dict.py 对着角色表再筛。

wiki 按编号分成一段段(CHUNK),几段同时抓(WORKERS);抓完的段记在 <out>.done,
中途断了再跑一次只抓没抓完的。
"""

import csv
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = 'https://danbooru.donmai.us/wiki_pages.json'
PAGE = 1000
CHUNK = 10000
WORKERS = 4
_HEADING = re.compile(r'^h[1-6](?:#[\w-]+)?\.\s*(.*?)\s*$', re.M)
_FORM_HEADING = re.compile(
    r'appearance|costume|outfit|form|version|variant|alternate|attire|skin|'
    r'transformation|incarnation|design', re.I)
_NOT_FORMS = re.compile(r'related|see also|external|unit|group|family|song', re.I)
_LINK = re.compile(r'\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|[^\]]*)?\]\]')


def tag_of(link: str) -> str:
    return '_'.join(link.strip().lower().split())


def forms_in(body: str) -> list[str]:
    """wiki 正文里讲外观、形态的那几节链接到的标签。"""
    parts = _HEADING.split(body)
    # split 之后是 [开头, 标题1, 正文1, 标题2, 正文2, ...]
    found = []
    for heading, text in zip(parts[1::2], parts[2::2]):
        if _FORM_HEADING.search(heading) and not _NOT_FORMS.search(heading):
            found += [tag_of(m) for m in _LINK.findall(text)]
    return list(dict.fromkeys(found))


def get(query: dict[str, str]) -> list[dict]:
    url = f'{API}?{urllib.parse.urlencode(query)}'
    request = urllib.request.Request(url, headers={'User-Agent': 'Penna-tools'})
    for attempt in range(8):
        try:
            with urllib.request.urlopen(request, timeout=90) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError) as e:
            print('重试', attempt + 1, e, flush=True)
            time.sleep(3 * (attempt + 1))
    raise RuntimeError('Danbooru 连不上:再跑一次会接着抓')


def newest() -> int:
    """最大的 wiki 编号(默认排序是按修改时间,第一条不一定最大)。"""
    # 编号超过 int4 的上限服务器报 500。
    return get({'limit': '1', 'only': 'id', 'page': f'b{2**31 - 1}'})[0]['id']


def chunk(lo: int) -> list[tuple[str, str]]:
    """编号在 [lo, lo + CHUNK) 的角色 wiki 里的形态链接。"""
    rows = []
    # 「b 编号」是按编号从大到小、取比它小的;不带它时的默认排序不是按编号,没法往下翻。
    before = lo + CHUNK
    while True:
        batch = get({
            'search[tag][category]': '4',
            'search[is_deleted]': 'false',
            'search[id]': f'{lo}..{lo + CHUNK - 1}',
            'limit': str(PAGE),
            'only': 'id,title,body',
            'page': f'b{before}',
        })
        rows += [
            (wiki['title'], form)
            for wiki in batch
            for form in forms_in(wiki['body'] or '')
            if form != wiki['title']
        ]
        if len(batch) < PAGE:
            return rows
        before = min(w['id'] for w in batch)


def main(out: str) -> None:
    part, done_file = out + '.part', out + '.done'
    os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
    resume = os.path.exists(part) and os.path.exists(done_file)
    done = set(json.load(io.open(done_file))) if resume else set()
    if not resume:
        with io.open(part, 'w', encoding='utf-8', newline='') as f:
            csv.writer(f).writerow(['parent', 'form'])
    todo = [lo for lo in range(0, newest() + 1, CHUNK) if lo not in done]
    print('要抓', len(todo), '段', flush=True)
    with ThreadPoolExecutor(WORKERS) as pool:
        for lo, rows in zip(todo, pool.map(chunk, todo)):
            # pool.map 按顺序交回结果,写文件只在这一个线程里。
            with io.open(part, 'a', encoding='utf-8', newline='') as f:
                csv.writer(f).writerows(rows)
            done.add(lo)
            json.dump(sorted(done), io.open(done_file, 'w'))
            print('编号', lo, '起的一段:', len(rows), 'links', flush=True)
    os.replace(part, out)
    os.remove(done_file)
    print('->', out)


if __name__ == '__main__':
    try:
        main(sys.argv[1] if len(sys.argv) > 1 else 'dataset/danbooru_character_forms.csv')
    except RuntimeError as e:
        sys.exit(str(e))
