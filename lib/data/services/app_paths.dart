import 'dart:io';

/// 用户数据目录(「文档\Penna」),启动时由 main 设好;测试里没有。
///
/// 只给「把出问题的请求留在本机好排查」这类用途用;正经的读写还是走 [ConfigService.dir]。
Directory? pennaHome;
