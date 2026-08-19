import 'workspace_provider.dart';
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

  static List<Workspace> get workspaces => WorkspaceProvider.instance.workspaces;

  static Workspace? get activeWorkspace => WorkspaceProvider.instance.activeWorkspace;
  static set activeWorkspace(Workspace? ws) => WorkspaceProvider.instance.setActiveWorkspace(ws);

  static bool isWorkspaceRunning(String workspaceId) =>
      WorkspaceProvider.instance.isWorkspaceRunning(workspaceId);

  static HomeController getController(Workspace workspace) =>
      WorkspaceProvider.instance.getController(workspace);

  static Future<void> stopWorkspace(String workspaceId) =>
      WorkspaceProvider.instance.stopWorkspace(workspaceId);

  static Future<void> load() => WorkspaceProvider.instance.load();

  static Future<void> save() => WorkspaceProvider.instance.save();

  static Future<Workspace> createWorkspace(String name, String type) =>
      WorkspaceProvider.instance.createWorkspace(name, type);

  static Future<void> deleteWorkspace(
    Workspace workspace, {
    void Function(String message, double progress)? onProgress,
  }) =>
      WorkspaceProvider.instance.deleteWorkspace(workspace, onProgress: onProgress);
}

