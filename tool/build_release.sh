#!/usr/bin/env bash
# 重新打包 Linux 版,按版本号放进 dist/main(正式版)或 dist/dev(测试版,版本号以 -dev 结尾),
# 产出一个 AppImage:dist/<频道>/Penna-<版本>-x86_64.AppImage。
# 用法(在项目根目录):  bash tool/build_release.sh
#
# 与 Windows 的 tool/build_release.ps1 对应:同样从 pubspec.yaml 读版本号、同样分 main/dev 两个频道、
# 产物同样落在 dist/ 下,两个平台互不覆盖。
#
# AppImage 需要 appimagetool:脚本会自己下到 dist/cache(只下一次),和 Windows 那边把
# onnxruntime 压缩包缓存在 dist/cache 的做法一致。
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

version="$(sed -n 's/^version:[[:space:]]*\([^[:space:]]*\).*/\1/p' pubspec.yaml | head -1)"
if [ -z "$version" ]; then
  echo "读不到 pubspec.yaml 里的版本号" >&2
  exit 1
fi
case "$version" in
  *-dev | *-dev+*) channel=dev ;;
  *) channel=main ;;
esac
# 文件名不带构建号:发版产物是 Penna-v1.0.2-windows-x64.zip 这种写法,AppImage 跟着来。
short="${version%%+*}"

dist="$root/dist"
bundle="$root/build/linux/x64/release/bundle"
appdir="$root/build/appimage/Penna.AppDir"
out="$dist/$channel"
icon="$root/linux/penna.png"

if ! command -v flutter >/dev/null 2>&1; then
  echo "找不到 flutter,请先装 Flutter SDK 并把它加进 PATH" >&2
  exit 1
fi
if [ ! -f "$icon" ]; then
  echo "找不到图标 $icon" >&2
  exit 1
fi

echo "打包 Penna v$version($channel)..."
flutter build linux --release

# appimagetool:缓存一份在 dist/cache,之后直接用。
tool="$dist/cache/appimagetool-x86_64.AppImage"
if [ ! -x "$tool" ]; then
  mkdir -p "$dist/cache"
  echo "下载 appimagetool(只下这一次,之后用 dist/cache 里的)"
  if ! curl -fL --retry 3 -o "$tool.part" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage; then
    rm -f "$tool.part"
    echo "下载 appimagetool 失败。可以自己下一份放到 $tool 再重试。" >&2
    exit 1
  fi
  mv "$tool.part" "$tool"
  chmod +x "$tool"
fi

# 拼 AppDir:Flutter 的产物按可执行文件所在目录找 lib/ 和 data/,所以整份放进 usr/bin。
echo "拼 AppDir..."
rm -rf "$appdir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
  "$appdir/usr/share/icons/hicolor/256x256/apps"
cp -a "$bundle/." "$appdir/usr/bin/"
cp "$icon" "$appdir/penna.png"
cp "$icon" "$appdir/usr/share/icons/hicolor/256x256/apps/penna.png"
cp "$icon" "$appdir/.DirIcon"

cat >"$appdir/penna.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Penna
Name[zh_CN]=Penna 羽毛笔
GenericName=Prompt workbench
GenericName[zh_CN]=提示词工作台
Comment=Text-to-image prompt workbench
Comment[zh_CN]=文生图提示词工作台
Exec=penna %U
Icon=penna
Categories=Graphics;Utility;
Keywords=prompt;image;caption;
Terminal=false
StartupWMClass=com.example.penna
DESKTOP
cp "$appdir/penna.desktop" "$appdir/usr/share/applications/penna.desktop"

cat >"$appdir/AppRun" <<'APPRUN'
#!/bin/sh
# 资源按可执行文件所在目录找,所以先切到 usr/bin 再启动。
here="$(dirname "$(readlink -f "$0")")"
cd "$here/usr/bin"
exec ./penna "$@"
APPRUN
chmod +x "$appdir/AppRun"

echo "生成 AppImage..."
mkdir -p "$out"
name="Penna-$short-x86_64.AppImage"
ARCH=x86_64 "$tool" "$appdir" "$out/$name"

echo
echo "完成。"
echo "  AppImage: $out/$name"
