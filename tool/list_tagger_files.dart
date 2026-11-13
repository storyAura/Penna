// 列出 Tag 反推清单里每个要下载的文件(仓库、路径、是否要 Token),给 make_tagger_hashes.py 用。
import 'package:penna/core/harness/local/tagger_catalog.dart';
void main() {
  for (final m in taggerModels) {
    for (final f in m.files) print('${m.repo}\t$f\t${m.gated}');
  }
}
