"""生成 lib/core/harness/local/tagger_hashes.dart:Tag 反推各文件在 HuggingFace 上的大小和 SHA256。

    dart run tool/list_tagger_files.dart | python tool/make_tagger_hashes.py

大文件(LFS)的 SHA256 直接取接口给的;小文件接口只给 git 的 SHA1,公开的下载下来算。
要 Token 的仓库接口不给 SHA256,也不下载,只记大小。要联网。
"""
import hashlib
import json
import sys
import urllib.request
from collections import defaultdict

OUT = 'lib/core/harness/local/tagger_hashes.dart'


def fetch(url, data=None):
    req = urllib.request.Request(url, data=data, headers={'User-Agent': 'Penna', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def main():
    wanted = defaultdict(list)
    gated = set()
    for line in sys.stdin:
        repo, path, g = line.rstrip('\n').split('\t')
        wanted[repo].append(path)
        if g == 'true':
            gated.add(repo)
    rows = []
    for repo in sorted(wanted):
        if repo in gated:
            # 要 Token 的仓库不让查 paths-info,按文件夹列出来能看到大小。
            folders = sorted({p.rpartition('/')[0] for p in wanted[repo]})
            info = [x for d in folders for x in json.loads(fetch(
                f'https://huggingface.co/api/models/{repo}/tree/main/{d}'))]
        else:
            info = json.loads(fetch(
                f'https://huggingface.co/api/models/{repo}/paths-info/main',
                json.dumps({'paths': wanted[repo]}).encode()))
        found = {x['path']: x for x in info}
        for path in sorted(wanted[repo]):
            x = found.get(path)
            if x is None:
                sys.exit(f'找不到 {repo}/{path}')
            lfs = x.get('lfs') or {}
            sha = lfs.get('oid')
            if sha and not all(c in '0123456789abcdef' for c in sha):
                sha = None  # 要 Token 的仓库打了码
            if not lfs and repo not in gated:
                sha = hashlib.sha256(fetch(f'https://huggingface.co/{repo}/resolve/main/{path}')).hexdigest()
            rows.append((f'{repo}/{path}', x['size'], sha))
            print(repo, path, x['size'], sha or '-', file=sys.stderr)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('// 生成的文件:dart run tool/list_tagger_files.dart | python tool/make_tagger_hashes.py\n')
        f.write('// Tag 反推各文件在 HuggingFace 上的大小和 SHA256(要 Token 的仓库没有 SHA256)。别手改。\n\n')
        f.write('/// 键是「仓库/路径」。\n')
        f.write('const taggerFileInfo = <String, ({int size, String? sha256})>{\n')
        for key, size, sha in rows:
            f.write(f"  '{key}': (size: {size}, sha256: {repr(sha) if sha else 'null'}),\n")
        f.write('};\n')


main()
