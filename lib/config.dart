const bool product = bool.fromEnvironment('dart.vm.product');
const String debugCSV = '4.103.1';

class Config {
  Config._();

  /// The package name of the app
  static const String packageName = 'com.nightmare.code';

  static const String versionName = debugCSV;
  static const String defaultCodeServerVersion = debugCSV;
  static String codeServerVersion = debugCSV;

  static int port = 20000;

  static String ubuntuFileName = 'ubuntu-noble-aarch64-pd-v4.18.0.tar.xz';
}
