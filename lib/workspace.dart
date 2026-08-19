import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'terminal_controller.dart';

class Workspace {
  final String id;
  final String name;
  final int port;
  final String createTime;
  final String type;

  Workspace({
    required this.id,
    required this.name,
    required this.port,
    required this.createTime,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'port': port,
        'createTime': createTime,
        'type': type,
      };

  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
        id: json['id'],
        name: json['name'],
        port: json['port'],
        createTime: json['createTime'],
        type: json['type'] ?? 'vscode',
      );
}

class WorkspaceManager {
  WorkspaceManager._();

  static List<Workspace> _workspaces = [];
  static Workspace? activeWorkspace;

  static List<Workspace> get workspaces => _workspaces;

  static File get _storageFile => File('${RuntimeEnvir.configPath}/workspaces.json');

  static bool isWorkspaceRunning(String id) {
    if (!Get.isRegistered<HomeController>(tag: id)) return false;
    final controller = Get.find<HomeController>(tag: id);
    return controller.isRunning;
  }

  static Future<void> load() async {
    try {
      if (!_storageFile.existsSync()) {
        _workspaces = [];
        // Check if there is an existing legacy 'ubuntu' workspace setup
        final legacyRootfs = Directory('${RuntimeEnvir.usrPath}/var/lib/proot-distro/installed-rootfs/ubuntu');
        if (legacyRootfs.existsSync()) {
          // Import the existing legacy container as the default workspace
          final legacyWorkspace = Workspace(
            id: 'ubuntu',
            name: 'Default Workspace',
            port: 20000,
            createTime: DateTime.now().toIso8601String(),
            type: 'vscode',
          );
          _workspaces.add(legacyWorkspace);
          await save();
        }
      } else {
        final content = _storageFile.readAsStringSync();
        if (content.isNotEmpty) {
          final List<dynamic> list = json.decode(content);
          _workspaces = list.map((item) => Workspace.fromJson(item)).toList();
        }
      }
    } catch (e) {
      Log.e('Failed to load workspaces: $e');
      _workspaces = [];
    }
  }

  static Future<void> save() async {
    try {
      if (!_storageFile.parent.existsSync()) {
        _storageFile.parent.createSync(recursive: true);
      }
      final content = json.encode(_workspaces.map((w) => w.toJson()).toList());
      _storageFile.writeAsStringSync(content);
    } catch (e) {
      Log.e('Failed to save workspaces: $e');
    }
  }

  static Future<Workspace> createWorkspace(String name, String type) async {
    final id = 'ws_${DateTime.now().millisecondsSinceEpoch}';
    
    // Find an unused port starting from 20000
    int port = 20000;
    final activePorts = _workspaces.map((w) => w.port).toSet();
    while (activePorts.contains(port)) {
      port++;
    }

    final newWorkspace = Workspace(
      id: id,
      name: name,
      port: port,
      createTime: DateTime.now().toIso8601String(),
      type: type,
    );

    _workspaces.add(newWorkspace);
    await save();
    return newWorkspace;
  }

  static Future<void> powerOff(Workspace workspace) async {
    if (Get.isRegistered<HomeController>(tag: workspace.id)) {
      try {
        final controller = Get.find<HomeController>(tag: workspace.id);
        await controller.powerOff();
        Get.delete<HomeController>(tag: workspace.id, force: true);
      } catch (e) {
        Log.e('Error during powerOff: $e');
      }
    }
    if (activeWorkspace?.id == workspace.id) {
      activeWorkspace = null;
    }
  }

  static Future<void> powerOn(Workspace workspace) async {
    if (!Get.isRegistered<HomeController>(tag: workspace.id)) {
      Get.put(
        HomeController(workspace: workspace),
        tag: workspace.id,
        permanent: true,
      );
    } else {
      final controller = Get.find<HomeController>(tag: workspace.id);
      if (!controller.isRunning) {
        Get.delete<HomeController>(tag: workspace.id, force: true);
        Get.put(
          HomeController(workspace: workspace),
          tag: workspace.id,
          permanent: true,
        );
      }
    }
  }

  static Future<void> deleteWorkspace(
    Workspace workspace, {
    void Function(String step)? onProgress,
  }) async {
    // 1. Power off and terminate all processes completely first
    onProgress?.call('Stopping running processes...');
    await powerOff(workspace);
    await Future.delayed(const Duration(milliseconds: 200));

    // 2. Purge all workspace files from physical phone storage
    onProgress?.call('Removing Ubuntu rootfs from storage...');
    try {
      final rootfsPath = '${RuntimeEnvir.usrPath}/var/lib/proot-distro/installed-rootfs/${workspace.id}';
      final rootfsDir = Directory(rootfsPath);
      if (rootfsDir.existsSync()) {
        try {
          // Use busybox chmod and rm -rf to force delete read-only files, symlinks and sockets
          final busyboxPath = '${RuntimeEnvir.binPath}/busybox';
          if (File(busyboxPath).existsSync()) {
            Process.runSync(busyboxPath, ['chmod', '-R', '777', rootfsPath]);
            Process.runSync(busyboxPath, ['rm', '-rf', rootfsPath]);
          }
        } catch (e) {
          Log.e('Busybox cleanup error: $e');
        }

        // Secondary fallback via Dart
        if (rootfsDir.existsSync()) {
          try {
            rootfsDir.deleteSync(recursive: true);
          } catch (e) {
            Log.e('Dart deleteSync error: $e');
          }
        }
      }

      onProgress?.call('Removing configuration scripts...');
      // 2.1 Delete proot-distro script file
      final scriptFile = File('${RuntimeEnvir.usrPath}/etc/proot-distro/${workspace.id}.sh');
      if (scriptFile.existsSync()) {
        scriptFile.deleteSync();
      }

      // 2.2 Delete workspace-specific common script
      final commonFile = File('${RuntimeEnvir.homePath}/common_${workspace.id}.sh');
      if (commonFile.existsSync()) {
        commonFile.deleteSync();
      }

      // 2.3 Delete workspace-specific progress files
      final progressFile = File('${RuntimeEnvir.tmpPath}/progress_${workspace.id}');
      if (progressFile.existsSync()) {
        progressFile.deleteSync();
      }
      final progressDesFile = File('${RuntimeEnvir.tmpPath}/progress_des_${workspace.id}');
      if (progressDesFile.existsSync()) {
        progressDesFile.deleteSync();
      }

      // 2.4 Delete any temporary socket or session files
      final tmpDir = Directory(RuntimeEnvir.tmpPath);
      if (tmpDir.existsSync()) {
        tmpDir.listSync().forEach((entity) {
          if (entity.path.contains(workspace.id)) {
            try {
              entity.deleteSync(recursive: true);
            } catch (_) {}
          }
        });
      }
    } catch (e) {
      Log.e('Error cleaning up workspace files from storage: $e');
    }

    // 3. Remove from configuration and save
    onProgress?.call('Updating workspace registry...');
    _workspaces.removeWhere((w) => w.id == workspace.id);
    await save();

    if (activeWorkspace?.id == workspace.id) {
      activeWorkspace = null;
    }
  }
}



