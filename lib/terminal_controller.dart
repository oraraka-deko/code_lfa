import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';
import 'package:xterm/xterm.dart';
import 'config.dart';
import 'generated/l10n.dart';
import 'script.dart';
import 'utils.dart';
import 'workspace.dart';

class TerminalTab {
  final String id;
  String title;
  final Pty pty;
  final Terminal terminal;

  TerminalTab({
    required this.id,
    required this.title,
    required this.pty,
    required this.terminal,
  });
}

class HomeController extends GetxController {
  final Workspace? workspace;

  HomeController({this.workspace});

  Workspace get currentWorkspace =>
      workspace ??
      WorkspaceManager.activeWorkspace ??
      Workspace(
        id: Config.activeWorkspaceId,
        name: 'Default',
        port: Config.port,
        createTime: '',
        type: 'vscode',
      );

  bool isRunning = false;
  bool vsCodeStaring = false;
  Setting privacySetting = 'privacy'.setting;

  final List<TerminalTab> tabs = [];
  int activeTabIndex = 0;

  TerminalTab? get currentTab => tabs.isNotEmpty && activeTabIndex < tabs.length ? tabs[activeTabIndex] : null;

  late final Terminal _fallbackTerminal = Terminal(
    maxLines: 10000,
    onResize: (width, height, pixelWidth, pixelHeight) {
      pseudoTerminal?.resize(height, width);
    },
    onOutput: (data) {
      pseudoTerminal?.writeString(data);
    },
  );

  Terminal get terminal => currentTab?.terminal ?? _fallbackTerminal;
  Pty? get pseudoTerminal => currentTab?.pty;

  bool webviewHasOpen = false;
  bool get isShellOnly => currentWorkspace.type == 'shell';

  File get progressFile => File('${RuntimeEnvir.tmpPath}/progress_${currentWorkspace.id}');
  File get progressDesFile => File('${RuntimeEnvir.tmpPath}/progress_des_${currentWorkspace.id}');
  double progress = 0.0;
  double step = 17;
  String currentProgress = '';

  void bumpProgress() {
    try {
      int current = 0;
      if (progressFile.existsSync()) {
        final content = progressFile.readAsStringSync().trim();
        if (content.isNotEmpty) {
          current = int.tryParse(content) ?? 0;
        }
      } else {
        progressFile.createSync(recursive: true);
      }
      progressFile.writeAsStringSync('${current + 1}');
    } catch (e) {
      try {
        progressFile.writeAsStringSync('1');
      } catch (_) {}
    }
    update();
  }

  void addNewTerminalTab({String? title}) {
    if (!isRunning) return;
    final tabIndex = tabs.length + 1;
    final tabTitle = title ?? 'Terminal $tabIndex';
    final newPty = createPTY(
      rows: terminal.viewHeight > 0 ? terminal.viewHeight : 25,
      columns: terminal.viewWidth > 0 ? terminal.viewWidth : 80,
    );
    late final Terminal newTerminal;
    newTerminal = Terminal(
      maxLines: 10000,
      onResize: (width, height, pixelWidth, pixelHeight) {
        newPty.resize(height, width);
      },
      onOutput: (data) {
        newPty.writeString(data);
      },
    );

    final newTab = TerminalTab(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
      title: tabTitle,
      pty: newPty,
      terminal: newTerminal,
    );

    Utf8Decoder decoder = const Utf8Decoder();
    newPty.output.cast<List<int>>().transform(decoder).listen((event) {
      newTerminal.write(event);
    });

    tabs.add(newTab);
    activeTabIndex = tabs.length - 1;

    newPty.writeString('source ${RuntimeEnvir.homePath}/common_${currentWorkspace.id}.sh\nlogin_shell_tab\n');
    update();
  }

  void closeTerminalTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    try {
      tabs[index].pty.writeString('exit\n');
      tabs[index].pty.writeString('\x03');
    } catch (_) {}
    tabs.removeAt(index);
    if (activeTabIndex >= tabs.length) {
      activeTabIndex = tabs.length - 1;
    }
    if (tabs.isEmpty) {
      if (isShellOnly) {
        stop();
      } else {
        addNewTerminalTab(title: 'Terminal 1');
      }
    }
    update();
  }

  void selectTerminalTab(int index) {
    if (index >= 0 && index < tabs.length) {
      activeTabIndex = index;
      update();
    }
  }

  Future<void> vsCodeStartWhenSuccessBind(Pty primaryPty, Terminal primaryTerminal) async {
    if (isShellOnly) {
      primaryTerminal.writeProgress('Launching Shell...');
    } else {
      primaryTerminal.writeProgress('${S.current.listen_vscode_start}...');
    }
    final Completer completer = Completer();
    Utf8Decoder decoder = const Utf8Decoder();
    primaryPty.output.cast<List<int>>().transform(decoder).listen((event) async {
      if (isShellOnly) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      } else {
        if (event.contains('http://0.0.0.0:${currentWorkspace.port}') ||
            event.contains('http://0.0.0.0:${Config.port}') ||
            event.contains('already')) {
          Log.e(event);
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      }
      primaryTerminal.write(event);
    });
    await completer.future;
    bumpProgress();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!isShellOnly) {
      webviewHasOpen = true;
      openWebView(port: currentWorkspace.port);
    }
    Future.delayed(const Duration(milliseconds: 2000), () {
      vsCodeStaring = false;
      update();
    });
  }

  Future<void> initEnvir() async {
    List<String> androidFiles = ['libbash.so', 'libbusybox.so', 'liblibtalloc.so.2.so', 'libloader.so', 'libproot.so', 'libsudo.so'];
    String libPath = await getLibPath();
    Log.i('libPath -> $libPath');

    for (int i = 0; i < androidFiles.length; i++) {
      final sourcePath = '$libPath/${androidFiles[i]}';
      String fileName = androidFiles[i].replaceAll(RegExp('^lib|\\.so\$'), '');
      String filePath = '${RuntimeEnvir.binPath}/$fileName';
      File file = File(filePath);
      FileSystemEntityType type = await FileSystemEntity.type(filePath);
      Log.i('$fileName type -> $type');
      if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.link) {
        Log.i('find plain file -> $fileName, delete it');
        await file.delete();
      }
      Link link = Link(filePath);
      if (link.existsSync()) {
        link.deleteSync();
      }
      try {
        Log.i('create link -> $fileName ${link.path}');
        link.createSync(sourcePath);
      } catch (e) {
        Log.e('installAdbToEnvir error -> $e');
      }
    }
  }

  void syncProgress() {
    try {
      progressFile.createSync(recursive: true);
      progressFile.writeAsStringSync('0');
      progressFile.watch(events: FileSystemEvent.all).listen((event) async {
        if (event.type == FileSystemEvent.modify) {
          String content = await progressFile.readAsString();
          Log.e('content -> $content');
          if (content.isEmpty) {
            return;
          }
          progress = (int.tryParse(content) ?? 0) / step;
          Log.e('progress -> $progress');
          update();
        }
      });
      progressDesFile.createSync(recursive: true);
      progressDesFile.writeAsStringSync('');
      progressDesFile.watch(events: FileSystemEvent.all).listen((event) async {
        if (event.type == FileSystemEvent.modify) {
          String content = await progressDesFile.readAsString();
          currentProgress = content;
          update();
        }
      });
    } catch (e) {
      Log.e('syncProgress error: $e');
    }
  }

  void createBusyboxLink() {
    try {
      List<String> links = [
        ...['awk', 'ash', 'basename', 'bzip2', 'curl', 'cp', 'chmod', 'cut', 'cat', 'du', 'dd', 'find', 'grep', 'gzip'],
        ...['hexdump', 'head', 'id', 'lscpu', 'mkdir', 'realpath', 'rm', 'sed', 'stat', 'sh', 'tr', 'tar', 'uname', 'xargs', 'xz', 'xxd']
      ];

      for (String linkName in links) {
        Link link = Link('${RuntimeEnvir.binPath}/$linkName');
        if (!link.existsSync()) {
          link.createSync('${RuntimeEnvir.binPath}/busybox');
        }
      }
      Link link = Link('${RuntimeEnvir.binPath}/file');
      if (!link.existsSync()) {
        link.createSync('/system/bin/file');
      }
    } catch (e) {
      Log.e('Create link failed -> $e');
    }
  }

  Future<void> loadCodeVersion() async {
    if (GetPlatform.isAndroid) {
      PermissionStatus status = await Permission.manageExternalStorage.request();
      Log.i('status -> $status');
      if (!status.isGranted) {
        return;
      }
    }
    File file = File('/sdcard/code_version');
    try {
      if (!file.existsSync()) {
        file.createSync();
        file.writeAsStringSync(Config.defaultCodeServerVersion);
      }
    } catch (e) {
      Log.e('Create code_version file failed -> $e');
    }
    if (file.existsSync()) Config.codeServerVersion = file.readAsStringSync();
    if (Config.codeServerVersion.isEmpty) {
      Config.codeServerVersion = Config.defaultCodeServerVersion;
    }
  }

  bool get useCustomCodeServer => Config.codeServerVersion != Config.defaultCodeServerVersion;

  void setProgress(String description) {
    currentProgress = description;
    terminal.writeProgress(currentProgress);
  }

  Future<void> loadCodeServer() async {
    if (isRunning) return;
    isRunning = true;
    vsCodeStaring = true;
    update();

    Config.activeWorkspaceId = currentWorkspace.id;
    Config.port = currentWorkspace.port;

    loadCodeVersion();
    syncProgress();
    bumpProgress();

    Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);
    Directory(RuntimeEnvir.homePath).createSync(recursive: true);
    Directory(RuntimeEnvir.binPath).createSync(recursive: true);
    bumpProgress();
    await initEnvir();
    bumpProgress();

    setProgress('${S.current.create_terminal_obj}...');
    final primaryPty = createPTY(rows: 25, columns: 80);
    late final Terminal primaryTerminal;
    primaryTerminal = Terminal(
      maxLines: 10000,
      onResize: (width, height, pixelWidth, pixelHeight) {
        primaryPty.resize(height, width);
      },
      onOutput: (data) {
        primaryPty.writeString(data);
      },
    );

    final primaryTab = TerminalTab(
      id: 'tab_1',
      title: 'Terminal 1',
      pty: primaryPty,
      terminal: primaryTerminal,
    );
    tabs.clear();
    tabs.add(primaryTab);
    activeTabIndex = 0;
    bumpProgress();

    primaryTerminal.writeProgress('${S.current.current_code_version}:${Config.codeServerVersion} [${useCustomCodeServer ? 'custom' : ''}]');
    setProgress('${S.current.copy_proot_distro}...');
    await AssetsUtils.copyAssetToPath('assets/proot-distro.zip', '${RuntimeEnvir.homePath}/proot-distro.zip');
    bumpProgress();

    setProgress('${S.current.copy_ubuntu}...');
    await AssetsUtils.copyAssetToPath('assets/${Config.ubuntuFileName}', '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}');
    bumpProgress();

    setProgress('${S.current.create_busybox_symlink}...');
    createBusyboxLink();
    bumpProgress();

    String codeServerName = 'code-server-${Config.codeServerVersion}-linux-arm64.tar.gz';
    String sourcePath = useCustomCodeServer ? '/sdcard/$codeServerName' : 'assets/$codeServerName';
    setProgress('${S.current.copy_code_server('[$sourcePath]')} ${RuntimeEnvir.tmpPath}...');
    try {
      if (useCustomCodeServer) {
        File codeServerOnSdcard = File(sourcePath);
        File targetFile = File('${RuntimeEnvir.tmpPath}/$codeServerName');
        if (targetFile.lengthSync() == codeServerOnSdcard.lengthSync()) {
          Log.i('code server already copied, skip');
        }
        await codeServerOnSdcard.copy(targetFile.path);
      } else {
        await AssetsUtils.copyAssetToPath(
          sourcePath,
          '${RuntimeEnvir.tmpPath}/$codeServerName',
        );
      }
    } catch (e) {
      Log.e('Copy code server failed -> $e');
      primaryTerminal.write('Copy code server failed -> $e');
      isRunning = false;
      vsCodeStaring = false;
      update();
      return;
    }

    final codeServerPath = '${RuntimeEnvir.tmpPath}/$codeServerName';
    setProgress('${S.current.gen_script}...');
    String fixHardLinkShell = '';
    try {
      Map<String, String> hardLinks = await getHardLinkMap(codeServerPath);
      fixHardLinkShell = genFixCodeServerHardLinkShell(hardLinks);
      Log.i('fixHardLinkShell -> $fixHardLinkShell');
    } catch (e) {
      primaryTerminal.write('Get hard link failed, will cause code-server start failed -> $e\r\n');
      isRunning = false;
      vsCodeStaring = false;
      update();
      return;
    }
    bumpProgress();
    bumpProgress();

    vsCodeStartWhenSuccessBind(primaryPty, primaryTerminal);
    bumpProgress();

    final scriptContent = '${getCommonScript(currentWorkspace)}\n$fixHardLinkShell';
    File('${RuntimeEnvir.homePath}/common_${currentWorkspace.id}.sh').writeAsStringSync(scriptContent);
    File('${RuntimeEnvir.homePath}/common.sh').writeAsStringSync(scriptContent);
    bumpProgress();
    startVsCode(primaryPty);
  }

  Future<void> startVsCode(Pty pty) async {
    vsCodeStaring = true;
    update();
    pty.writeString('source ${RuntimeEnvir.homePath}/common_${currentWorkspace.id}.sh\nstart_vs_code\n');
  }

  Future<void> stop() async {
    Log.i('Stopping workspace session: ${currentWorkspace.name} (${currentWorkspace.id})');
    for (final tab in tabs) {
      try {
        tab.pty.writeString('exit\n');
        tab.pty.writeString('\x03');
      } catch (_) {}
    }

    try {
      final binPath = RuntimeEnvir.binPath;
      final bashFile = File('$binPath/bash');
      String executable = bashFile.existsSync() ? bashFile.path : 'sh';

      final Map<String, String> env = Map.from(Platform.environment);
      env['HOME'] = RuntimeEnvir.homePath;
      env['TERMUX_PREFIX'] = RuntimeEnvir.usrPath;
      env['PATH'] = '${RuntimeEnvir.binPath}:${env['PATH'] ?? ''}';

      await Process.run(
        executable,
        ['-c', 'pkill -9 -f "${currentWorkspace.id}" 2>/dev/null || true'],
        environment: env,
      );
      await Process.run(
        executable,
        ['-c', 'fuser -k ${currentWorkspace.port}/tcp 2>/dev/null || true'],
        environment: env,
      );
    } catch (e) {
      Log.e('Error killing processes for ${currentWorkspace.id}: $e');
    }

    tabs.clear();
    isRunning = false;
    vsCodeStaring = false;
    webviewHasOpen = false;
    update();
  }

  @override
  void onInit() {
    super.onInit();
    Future.delayed(Duration.zero, () async {
      if (privacySetting.get() == null) {
        privacySetting.set(true);
      }
    });
  }
}

