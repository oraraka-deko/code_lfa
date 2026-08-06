import 'dart:convert';
import 'dart:io';
import 'package:global_repository/global_repository.dart';

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

  static Future<void> deleteWorkspace(Workspace workspace) async {
    _workspaces.removeWhere((w) => w.id == workspace.id);
    await save();

    if (activeWorkspace?.id == workspace.id) {
      activeWorkspace = null;
    }

    // Clean up files asynchronously
    try {
      // 1. Delete rootfs directory
      final rootfsDir = Directory('${RuntimeEnvir.usrPath}/var/lib/proot-distro/installed-rootfs/${workspace.id}');
      if (rootfsDir.existsSync()) {
        rootfsDir.deleteSync(recursive: true);
      }

      // 2. Delete proot-distro script file
      final scriptFile = File('${RuntimeEnvir.usrPath}/etc/proot-distro/${workspace.id}.sh');
      if (scriptFile.existsSync()) {
        scriptFile.deleteSync();
      }
    } catch (e) {
      Log.e('Error cleaning up workspace files: $e');
    }
  }
}
