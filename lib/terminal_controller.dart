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

class ShellTab {
  final String id;
  String name;
  final Pty pty;
  final Terminal terminal;
  final TerminalController terminalController;

  ShellTab({
    required this.id,
    required this.name,
    required this.pty,
    required this.terminal,
    required this.terminalController,
  });
}

class HomeController extends GetxController {
  final Workspace workspace;
  HomeController({required this.workspace});

  bool isRunning = true;
  bool vsCodeStaring = false;
  Setting privacySetting = 'privacy'.setting;
  Pty? pseudoTerminal;
  late final TerminalController defaultTerminalController = TerminalController();

  late Terminal terminal = Terminal(
    maxLines: 10000,
    onResize: (width, height, pixelWidth, pixelHeight) {
      pseudoTerminal?.resize(height, width);
    },
    onOutput: (data) {
      pseudoTerminal?.writeString(data);
    },
  );

  final List<ShellTab> shellTabs = [];
  int activeTabIndex = 0;

  Terminal get activeTerminal {
    if (isShellOnly && shellTabs.isNotEmpty && activeTabIndex < shellTabs.length) {
      return shellTabs[activeTabIndex].terminal;
    }
    return terminal;
  }

  TerminalController get activeTerminalController {
    if (isShellOnly && shellTabs.isNotEmpty && activeTabIndex < shellTabs.length) {
      return shellTabs[activeTabIndex].terminalController;
    }
    return defaultTerminalController;
  }

  Pty? get activePty {
    if (isShellOnly && shellTabs.isNotEmpty && activeTabIndex < shellTabs.length) {
      return shellTabs[activeTabIndex].pty;
    }
    return pseudoTerminal;
  }

  bool webviewHasOpen = false;
  bool get isShellOnly => workspace.type == 'shell';

  File get progressFile => File('${RuntimeEnvir.tmpPath}/progress_${workspace.id}');
  File get progressDesFile => File('${RuntimeEnvir.tmpPath}/progress_des_${workspace.id}');
  double progress = 0.0;
  double step = 17;
  String currentProgress = '';
  StreamSubscription? _progressSub;
  StreamSubscription? _progressDesSub;

  // 进度 +1
  // Progress +1
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
      progressFile.writeAsStringSync('1');
    }
    update();
  }

  // 监听输出，当输出中包含启动成功的标志时，启动 Code Server
  // Listen for output and start the Code Server when the success flag is detected
  Future<void> vsCodeStartWhenSuccessBind() async {
    if (isShellOnly) {
      terminal.writeProgress('Launching Shell...');
    } else {
      terminal.writeProgress('${S.current.listen_vscode_start}...');
    }
    final Completer completer = Completer();
    Utf8Decoder decoder = const Utf8Decoder(allowMalformed: true);
    pseudoTerminal!.output.cast<List<int>>().transform(decoder).listen((event) async {
      if (isShellOnly) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      } else {
        if (event.contains('http://0.0.0.0:${workspace.port}')) {
          Log.e(event);
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
        if (event.contains('already')) {
          Log.e(event);
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      }
      terminal.write(event);
    });
    await completer.future;
    bumpProgress();

    if (isShellOnly && shellTabs.isEmpty && pseudoTerminal != null) {
      shellTabs.add(ShellTab(
        id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Shell 1',
        pty: pseudoTerminal!,
        terminal: terminal,
        terminalController: defaultTerminalController,
      ));
    }

    await Future.delayed(const Duration(milliseconds: 100));
    if (!isShellOnly) {
      webviewHasOpen = true;
      openWebView(port: workspace.port);
    }
    Future.delayed(const Duration(milliseconds: 2000), () {
      vsCodeStaring = false;
      update();
    });
  }

  void addNewTab([String? customName]) {
    if (!isShellOnly) return;
    final tabIndex = shellTabs.length + 1;
    final tabName = customName ?? 'Shell $tabIndex';
    final newTerminalController = TerminalController();

    Pty? newPty;
    final newTerminal = Terminal(
      maxLines: 10000,
      onResize: (width, height, pixelWidth, pixelHeight) {
        newPty?.resize(height, width);
      },
      onOutput: (data) {
        newPty?.writeString(data);
      },
    );

    newPty = createPTY(rows: newTerminal.viewHeight, columns: newTerminal.viewWidth);

    final tab = ShellTab(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}_${shellTabs.length}',
      name: tabName,
      pty: newPty,
      terminal: newTerminal,
      terminalController: newTerminalController,
    );

    const Utf8Decoder decoder = Utf8Decoder(allowMalformed: true);
    newPty.output.cast<List<int>>().transform(decoder).listen((event) {
      newTerminal.write(event);
    });

    newPty.writeString('source ${RuntimeEnvir.homePath}/common_${workspace.id}.sh\nlogin_ubuntu\n');

    shellTabs.add(tab);
    activeTabIndex = shellTabs.length - 1;
    update();
  }

  void selectTab(int index) {
    if (index >= 0 && index < shellTabs.length) {
      activeTabIndex = index;
      update();
    }
  }

  void closeTab(int index) {
    if (index >= 0 && index < shellTabs.length) {
      final tab = shellTabs[index];
      try {
        tab.pty.writeString('exit\n');
      } catch (_) {}
      shellTabs.removeAt(index);
      if (activeTabIndex >= shellTabs.length) {
        activeTabIndex = (shellTabs.length - 1).clamp(0, 9999);
      }
      if (shellTabs.isEmpty) {
        addNewTab();
      }
      update();
    }
  }

  void renameTab(int index, String newName) {
    if (index >= 0 && index < shellTabs.length && newName.trim().isNotEmpty) {
      shellTabs[index].name = newName.trim();
      update();
    }
  }

  // 初始化环境，将动态库中的文件链接到数据目录
  // Init environment and link files from the dynamic library to the data directory
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

  // 同步当前进度
  // Sync the current progress
  void syncProgress() {
    progressFile.createSync(recursive: true);
    progressFile.writeAsStringSync('0');
    _progressSub?.cancel();
    _progressSub = progressFile.watch(events: FileSystemEvent.all).listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressFile.readAsString();
        Log.e('content -> $content');
        if (content.isEmpty) {
          return;
        }
        progress = int.parse(content) / step;
        Log.e('progress -> $progress');
        update();
      }
    });
    progressDesFile.createSync(recursive: true);
    progressDesFile.writeAsStringSync('');
    _progressDesSub?.cancel();
    _progressDesSub = progressDesFile.watch(events: FileSystemEvent.all).listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressDesFile.readAsString();
        currentProgress = content;
        update();
      }
    });
  }

  // 创建 busybox 的软连接，来确保 proot-distro 会用到的命令正常运行
  // create busybox symlinks, to ensure proot-distro can use the commands normally
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
      link.createSync('/system/bin/file');
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
    isRunning = true;
    vsCodeStaring = true;
    update();
    Config.activeWorkspaceId = workspace.id;
    Config.port = workspace.port;

    loadCodeVersion();
    bumpProgress();
    Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);
    Directory(RuntimeEnvir.homePath).createSync(recursive: true);
    Directory(RuntimeEnvir.binPath).createSync(recursive: true);
    bumpProgress();
    await initEnvir();
    bumpProgress();
    setProgress('${S.current.create_terminal_obj}...');
    pseudoTerminal = createPTY(rows: terminal.viewHeight, columns: terminal.viewWidth);
    bumpProgress();
    terminal.writeProgress('${S.current.current_code_version}:${Config.codeServerVersion} [${useCustomCodeServer ? 'custom' : ''}]');
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
      terminal.write('Copy code server failed -> $e');
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
      terminal.write('Get hard link failed, will cause code-server start failed -> $e\r\n');
      return;
    }
    bumpProgress();
    bumpProgress();
    vsCodeStartWhenSuccessBind();
    bumpProgress();
    final scriptContent = '${getCommonScript(workspace)}\n$fixHardLinkShell';
    File('${RuntimeEnvir.homePath}/common_${workspace.id}.sh').writeAsStringSync(scriptContent);
    bumpProgress();
    startVsCode(pseudoTerminal!);
  }

  Future<void> startVsCode(Pty pseudoTerminal) async {
    vsCodeStaring = true;
    update();
    pseudoTerminal.writeString('source ${RuntimeEnvir.homePath}/common_${workspace.id}.sh\nstart_vs_code\n');
  }

  Future<void> powerOff() async {
    isRunning = false;
    vsCodeStaring = false;
    // 1. Exit all shell tabs cleanly
    for (final tab in shellTabs) {
      try {
        tab.pty.writeString('exit\n');
      } catch (_) {}
    }
    // 2. Stop code-server if vscode workspace and exit primary pty
    try {
      if (pseudoTerminal != null) {
        if (!isShellOnly) {
          pseudoTerminal!.writeString('pkill -9 -f code-server\nexit\n');
        } else {
          pseudoTerminal!.writeString('exit\n');
        }
      }
    } catch (_) {}
    // 3. Cancel watchers
    _progressSub?.cancel();
    _progressDesSub?.cancel();
    await Future.delayed(const Duration(milliseconds: 300));
    update();
  }

  @override
  void onInit() {
    super.onInit();
    Future.delayed(Duration.zero, () async {
      if (privacySetting.get() == null) {
        privacySetting.set(true);
      }
      syncProgress();
      loadCodeServer();
    });
  }

  @override
  void onClose() {
    _progressSub?.cancel();
    _progressDesSub?.cancel();
    super.onClose();
  }
}

