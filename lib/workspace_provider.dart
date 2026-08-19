import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:global_repository/global_repository.dart';
import 'terminal_controller.dart';
import 'workspace.dart';

class WorkspaceProvider extends ChangeNotifier {
  WorkspaceProvider._();

  static final WorkspaceProvider instance = WorkspaceProvider._();

  List<Workspace> _workspaces = [];
  Workspace? _activeWorkspace;
  bool _loading = false;

  final Map<String, HomeController> _controllers = {};

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  Workspace? get activeWorkspace => _activeWorkspace;
  bool get isLoading => _loading;

  static File get _storageFile => File('${RuntimeEnvir.configPath}/workspaces.json');

  void setActiveWorkspace(Workspace? ws) {
    _activeWorkspace = ws;
   // WorkspaceManager.activeWorkspace = ws;
    notifyListeners();
  }

  bool isWorkspaceRunning(String workspaceId) {
    final c = _controllers[workspaceId];
    return c != null && c.isRunning;
  }

  HomeController getController(Workspace workspace) {
    if (_controllers.containsKey(workspace.id)) {
      return _controllers[workspace.id]!;
    }
    final c = HomeController(workspace: workspace);
    _controllers[workspace.id] = c;
    return c;
  }

  Future<void> stopWorkspace(String workspaceId) async {
    final c = _controllers[workspaceId];
    if (c != null) {
      await c.stop();
      _controllers.remove(workspaceId);
      notifyListeners();
    }
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    try {
      if (!_storageFile.existsSync()) {
        _workspaces = [];
        final legacyRootfs = Directory('${RuntimeEnvir.usrPath}/var/lib/proot-distro/installed-rootfs/ubuntu');
        if (legacyRootfs.existsSync()) {
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
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> save() async {
    try {
      if (!_storageFile.parent.existsSync()) {
        _storageFile.parent.createSync(recursive: true);
      }
      final content = json.encode(_workspaces.map((w) => w.toJson()).toList());
      _storageFile.writeAsStringSync(content);
      notifyListeners();
    } catch (e) {
      Log.e('Failed to save workspaces: $e');
    }
  }

  Future<Workspace> createWorkspace(String name, String type) async {
    final id = 'ws_${DateTime.now().millisecondsSinceEpoch}';

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
    notifyListeners();
    return newWorkspace;
  }

  static Future<void> _runCommand(String command) async {
    try {
      final binPath = RuntimeEnvir.binPath;
      final bashFile = File('$binPath/bash');
      final busyboxFile = File('$binPath/busybox');

      String executable = 'sh';
      List<String> args = ['-c', command];

      if (bashFile.existsSync()) {
        executable = bashFile.path;
      } else if (busyboxFile.existsSync()) {
        executable = busyboxFile.path;
        args = ['sh', '-c', command];
      }

      final Map<String, String> env = Map.from(Platform.environment);
      env['HOME'] = RuntimeEnvir.homePath;
      env['TERMUX_PREFIX'] = RuntimeEnvir.usrPath;
      env['PATH'] = '${RuntimeEnvir.binPath}:${env['PATH'] ?? ''}';
      env['PROOT_LOADER'] = '${RuntimeEnvir.binPath}/loader';
      env['LD_LIBRARY_PATH'] = RuntimeEnvir.binPath;

      await Process.run(
        executable,
        args,
        environment: env,
      );
    } catch (e) {
      Log.e('Command execution failed ($command): $e');
    }
  }

  Future<void> deleteWorkspace(
    Workspace workspace, {
    void Function(String message, double progress)? onProgress,
  }) async {
    Log.i('Starting complete removal of workspace: ${workspace.name} (${workspace.id})');

    try {
      onProgress?.call('Stopping workspace processes...', 0.15);
      await stopWorkspace(workspace.id);
      await _runCommand('pkill -9 -f "${workspace.id}" 2>/dev/null || true');
      await _runCommand('fuser -k ${workspace.port}/tcp 2>/dev/null || true');
      await Future.delayed(const Duration(milliseconds: 300));

      final rootfsPath = '${RuntimeEnvir.usrPath}/var/lib/proot-distro/installed-rootfs/${workspace.id}';
      final rootfsDir = Directory(rootfsPath);

      if (rootfsDir.existsSync()) {
        onProgress?.call('Unlocking container filesystem permissions...', 0.35);
        await _runCommand('chmod -R 777 "$rootfsPath" 2>/dev/null || true');
        await Future.delayed(const Duration(milliseconds: 200));

        onProgress?.call('Purging container rootfs from internal storage...', 0.65);
        await _runCommand('rm -rf "$rootfsPath" 2>/dev/null || true');

        if (rootfsDir.existsSync()) {
          try {
            await rootfsDir.delete(recursive: true);
          } catch (e) {
            Log.w('Dart deleteSync fallback warning: $e');
            try {
              final entities = rootfsDir.listSync(recursive: true, followLinks: false);
              for (final entity in entities.reversed) {
                try {
                  entity.deleteSync();
                } catch (_) {}
              }
              if (rootfsDir.existsSync()) {
                rootfsDir.deleteSync();
              }
            } catch (_) {}
          }
        }
      }

      onProgress?.call('Cleaning workspace configuration and scripts...', 0.85);
      final scriptFile = File('${RuntimeEnvir.usrPath}/etc/proot-distro/${workspace.id}.sh');
      if (scriptFile.existsSync()) {
        try {
          scriptFile.deleteSync();
        } catch (e) {
          Log.e('Failed to delete script file: $e');
        }
      }

      try {
        final tmpDir = Directory(RuntimeEnvir.tmpPath);
        if (tmpDir.existsSync()) {
          final files = tmpDir.listSync();
          for (final f in files) {
            if (f.path.contains(workspace.id)) {
              try {
                f.deleteSync(recursive: true);
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      onProgress?.call('Updating workspace list...', 0.95);
      _workspaces.removeWhere((w) => w.id == workspace.id);
      await save();

      if (_activeWorkspace?.id == workspace.id) {
        _activeWorkspace = null;
        WorkspaceManager.activeWorkspace = null;
      }

      onProgress?.call('Container removed from internal storage successfully!', 1.0);
      await Future.delayed(const Duration(milliseconds: 500));
      notifyListeners();
    } catch (e) {
      Log.e('Error during workspace deletion: $e');
      rethrow;
    }
  }
}
