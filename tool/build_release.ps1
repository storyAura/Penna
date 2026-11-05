# 重新打包,按版本号放进 dist\main(正式版)或 dist\dev(测试版,版本号以 -dev 结尾),
# 并在桌面放对应的快捷方式:「Penna 羽毛笔」和「Penna 羽毛笔 dev」,两个版本互不覆盖。
# 用法(在项目根目录):  pwsh tool/build_release.ps1
#
# 项目路径里有中文时 Flutter 的正式版编译会失败,所以这里临时把上一级文件夹
# 映射成一个纯英文盘符再编译。项目搬到纯英文路径后,这段映射可以删掉。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$drive = 'P:'
if (Get-Process penna -ErrorAction SilentlyContinue) {
  throw 'Penna 正在运行,程序文件被占用。请先关掉它再打包。'
}
if (Test-Path "$drive\") { throw "$drive 盘符已被占用,请改脚本里的 `$drive" }

$version = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$channel = if ($version -match '-dev(\+|$)') { 'dev' } else { 'main' }
$desktop = [Environment]::GetFolderPath('Desktop')
$release = Join-Path $root 'build\windows\x64\runner\Release'
$dist = Join-Path $root 'dist'

function Set-Shortcut($name, $exe, $description) {
  $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop $name))
  $shortcut.TargetPath = $exe
  $shortcut.WorkingDirectory = Split-Path $exe
  $shortcut.Description = $description
  $shortcut.Save()
  "已更新: $name -> $exe"
}

# 把 $from 整个文件夹镜像到 $to(多的删掉、旧的换掉)。robocopy 的退出码小于 8 都算成功。
function Copy-Build($from, $to) {
  robocopy $from $to /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "复制到 $to 失败(robocopy $LASTEXITCODE)" }
}

# 旧版脚本把快捷方式指向 build 里的 Release:先把那份正式版搬到 dist\main,
# 免得下面的 flutter clean 把它清掉、或被这次的测试版盖掉。
$mainLnk = Join-Path $desktop 'Penna 羽毛笔.lnk'
if ((Test-Path $mainLnk) -and -not (Test-Path "$dist\main\penna.exe") -and (Test-Path "$release\penna.exe")) {
  $old = (New-Object -ComObject WScript.Shell).CreateShortcut($mainLnk).TargetPath
  if ($old -eq "$release\penna.exe") {
    Copy-Build $release "$dist\main"
    Set-Shortcut 'Penna 羽毛笔.lnk' "$dist\main\penna.exe" 'Penna 羽毛笔 - 文生图提示词工作台'
  }
}

subst $drive (Split-Path $root -Parent)
try {
  Set-Location "$drive\$(Split-Path $root -Leaf)"
  flutter clean | Out-Null
  # flutter_onnxruntime 每次 clean 后都要在 CMake 里从 GitHub 下载 onnxruntime 的压缩包,
  # 不检查下没下成功:网络不稳时下成空文件,报 "extraction directory doesn't exist"。
  # 所以压缩包在 dist\cache 留一份(只下一次),编译前先解到它要找的地方,它看到就不下了。
  # 依赖都在本机缓存里时不联网:镜像(PUB_HOSTED_URL)偶尔卡住不动,打包就一直停在这。缺了才去下载。
  flutter pub get --offline | Out-Null
  if ($LASTEXITCODE -ne 0) { flutter pub get | Out-Null }
  $ortCmake = 'windows\flutter\ephemeral\.plugin_symlinks\flutter_onnxruntime\windows\CMakeLists.txt'
  $ortMatch = if (Test-Path $ortCmake) { Select-String -Path $ortCmake -Pattern 'set\(ONNXRUNTIME_VERSION "([^"]+)"\)' }
  if ($ortMatch) {
    $ortName = "onnxruntime-win-x64-$($ortMatch.Matches[0].Groups[1].Value)"
    $ortZip = Join-Path $dist "cache\$ortName.zip"
    try {
      if (-not (Test-Path $ortZip)) {
        New-Item -ItemType Directory -Force (Split-Path $ortZip) | Out-Null
        "下载 $ortName(只下这一次,之后用 dist\cache 里的)"
        $ver = $ortMatch.Matches[0].Groups[1].Value
        Invoke-WebRequest "https://github.com/microsoft/onnxruntime/releases/download/v$ver/$ortName.zip" -OutFile "$ortZip.part"
        Move-Item "$ortZip.part" $ortZip -Force
      }
      $ortDir = 'build\windows\x64\plugins\flutter_onnxruntime\onnxruntime'
      New-Item -ItemType Directory -Force $ortDir | Out-Null
      Expand-Archive $ortZip -DestinationPath $ortDir -Force
    } catch {
      # 下载失败或压缩包坏了:删掉缓存,交给插件自己去下(下面失败了还会重试一次)。
      "onnxruntime 预备失败,交给插件自己下载:$($_.Exception.Message)"
      Remove-Item "$ortZip.part", $ortZip -Force -ErrorAction SilentlyContinue
    }
  }
  flutter build windows --release --no-pub
  # flutter clean 之后,flutter_onnxruntime 的 CMake 第一次常报
  # "ONNX Runtime extraction directory doesn't exist",再编一次就好:自动重试一次。
  if ($LASTEXITCODE -ne 0) {
    '编译失败,自动再试一次'
    flutter build windows --release --no-pub
  }
  if ($LASTEXITCODE -ne 0) { throw '编译失败,见上方输出' }
} finally {
  Set-Location $root
  subst $drive /D
  # 这份缓存里记着临时盘符的路径,留着会让之后的 flutter test 崩溃。
  $stale = Join-Path $root '.dart_tool\hooks_runner'
  if (Test-Path $stale) { Remove-Item -Recurse -Force $stale -Confirm:$false }
}

Copy-Build $release "$dist\$channel"
if ($channel -eq 'dev') {
  Set-Shortcut 'Penna 羽毛笔 dev.lnk' "$dist\dev\penna.exe" "Penna 羽毛笔 测试版 v$version"
} else {
  Set-Shortcut 'Penna 羽毛笔.lnk' "$dist\main\penna.exe" 'Penna 羽毛笔 - 文生图提示词工作台'
}
