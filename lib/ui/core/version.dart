/// 当前版本号:窗口右下角显示,检查更新时拿它比。
/// 要和 pubspec.yaml 的 version 一致(version_test.dart 会查)。
const appVersion = '1.0.3-261027-1-dev';

/// 测试版(版本号以 -dev 结尾):标题栏的字标右下角标一个红色的 dev。
final isDevBuild = appVersion.endsWith('-dev');
