#!/usr/bin/env bash
# 重新打包 Linux 版,按版本号放进 dist/main(正式版)或 dist/dev(测试版,版本号以 -dev 结尾),
# 产出一个 AppImage:dist/<频道>/Penna-<版本>-x86_64.AppImage。
# 用法(在项目根目录):  bash tool/build_release.sh
#
# 与 Windows 的 tool/build_release.ps1 对应:同样从 pubspec.yaml 读版本号、同样分 main/dev 两个频道、
# 产物同样落在 dist/ 下,两个平台互不覆盖。
#
# AppImage 需要 appimagetool(固定版本、核对 SHA256):脚本会自己下到 dist/cache(只下一次),
# 和 Windows 那边把 onnxruntime 压缩包缓存在 dist/cache 的做法一致。还要 patchelf。
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
# 文件名不带构建号,和 Penna-v1.0.2-windows-x64.zip 对齐;自动更新认 -linux-x86_64.AppImage 结尾。
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
if ! command -v patchelf >/dev/null 2>&1; then
  echo "找不到 patchelf,请先装上(比如 sudo apt install patchelf)" >&2
  exit 1
fi
if [ ! -f "$icon" ]; then
  echo "找不到图标 $icon" >&2
  exit 1
fi

echo "打包 Penna v$version($channel)..."

# onnxruntime:flutter_onnxruntime 插件从 github.com/microsoft/onnxruntime 下 Linux 的压缩包,
# 那个仓库 2026-11 起 404(v1.0.4-261123-1-dev、261125-6-dev 两次 Linux 打包都卡在这)。
# 插件看到解压目录里已有头文件就不下载,所以先从 NuGet 的 Microsoft.ML.OnnxRuntime 取头文件和 .so,
# 按插件要的样子摆好。NuGet 上没有 1.28.3,用 1.28.0:头文件和 Windows 用的 1.28.3 一字不差。
# ponytail: 目录名跟着插件写死的默认版本(flutter_onnxruntime 1.9.0 是 1.28.3),升插件时这里一起改。
ort_dir="$root/build/linux/x64/release/plugins/flutter_onnxruntime/onnxruntime/onnxruntime-linux-x64-1.28.3"
ort_pkg="$dist/cache/microsoft.ml.onnxruntime.1.28.0.nupkg"
ort_sha256=769d1d3ea8ab6cd69f737c9dd4d4462aa4ad0ccfa106eaf506efc40d7bead5db
if [ ! -f "$ort_dir/include/onnxruntime_cxx_api.h" ]; then
  if [ ! -f "$ort_pkg" ]; then
    mkdir -p "$dist/cache"
    echo "下载 onnxruntime 1.28.0(NuGet,只下这一次)"
    if ! curl -fL --retry 3 -o "$ort_pkg.part" \
      "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.28.0/microsoft.ml.onnxruntime.1.28.0.nupkg"; then
      rm -f "$ort_pkg.part"
      echo "下载 onnxruntime 失败" >&2
      exit 1
    fi
    if ! echo "$ort_sha256  $ort_pkg.part" | sha256sum -c --quiet; then
      rm -f "$ort_pkg.part"
      echo "onnxruntime 的 SHA256 对不上" >&2
      exit 1
    fi
    mv "$ort_pkg.part" "$ort_pkg"
  fi
  rm -rf "$ort_dir"
  mkdir -p "$ort_dir/include" "$ort_dir/lib"
  unzip -q -j -o "$ort_pkg" 'build/native/include/*' -d "$ort_dir/include"
  unzip -q -j -o "$ort_pkg" 'runtimes/linux-x64/native/libonnxruntime.so' -d "$ort_dir/lib"
  # 库的 SONAME 是 libonnxruntime.so.1,下面补进 AppDir 时按这个名字找。
  cp "$ort_dir/lib/libonnxruntime.so" "$ort_dir/lib/libonnxruntime.so.1"
fi

flutter build linux --release

# appimagetool:缓存一份在 dist/cache,之后直接用。
tool_version=1.9.1
tool_sha256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
tool="$dist/cache/appimagetool-$tool_version-x86_64.AppImage"
if [ ! -x "$tool" ]; then
  mkdir -p "$dist/cache"
  echo "下载 appimagetool(只下这一次,之后用 dist/cache 里的)"
  if ! curl -fL --retry 3 -o "$tool.part" \
    "https://github.com/AppImage/appimagetool/releases/download/$tool_version/appimagetool-x86_64.AppImage"; then
    rm -f "$tool.part"
    echo "下载 appimagetool 失败。可以自己下一份放到 $tool 再重试。" >&2
    exit 1
  fi
  if ! echo "$tool_sha256  $tool.part" | sha256sum -c --quiet; then
    rm -f "$tool.part"
    echo "appimagetool 的 SHA256 对不上" >&2
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

# 插件的 .so 记着编译机上的绝对路径(RUNPATH),onnxruntime 的库也只按不带版本号的名字打进来:
# 把插件要的 onnxruntime 按它要的名字补进 lib/,再让带 RUNPATH 的库只在自己旁边找。
lib="$appdir/usr/bin/lib"
# jni 包是 path_provider_android 带进来的,只有 Android 才用。机器上有 JDK 时它才编出这个库,
# 还要 libjvm.so;没有 JDK 的机器压根不编,Penna 也不调用,所以删掉,结果和没有 JDK 时一样。
rm -f "$lib/libdartjni.so"
for so in "$lib"/*.so*; do
  for need in $(patchelf --print-needed "$so" 2>/dev/null || true); do
    case "$need" in
      libonnxruntime*)
        if [ ! -e "$lib/$need" ]; then
          src="$(find "$root/build/linux" -name "$need" -path '*onnxruntime*' | head -1)"
          if [ -z "$src" ]; then
            echo "找不到 $need" >&2
            exit 1
          fi
          cp -L "$src" "$lib/$need"
        fi
        ;;
    esac
  done
  if [ -n "$(patchelf --print-rpath "$so" 2>/dev/null || true)" ]; then
    patchelf --set-rpath '$ORIGIN' "$so"
  fi
done
missing="$(ldd "$appdir/usr/bin/penna" "$lib"/*.so* 2>&1 | grep 'not found' || true)"
if [ -n "$missing" ]; then
  echo "AppDir 里有库找不到依赖:" >&2
  echo "$missing" >&2
  exit 1
fi

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
StartupWMClass=io.github.storyaura.penna
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
name="Penna-v$short-linux-x86_64.AppImage"
ARCH=x86_64 "$tool" "$appdir" "$out/$name"

echo
echo "完成。"
echo "  AppImage: $out/$name"
