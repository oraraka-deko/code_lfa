import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'workspace.dart';
import 'workspace_provider.dart';
import 'terminal_page.dart';

class WorkspaceListPage extends StatefulWidget {
  const WorkspaceListPage({super.key});

  @override
  State<WorkspaceListPage> createState() => _WorkspaceListPageState();
}

class _WorkspaceListPageState extends State<WorkspaceListPage> {
  final WorkspaceProvider _provider = WorkspaceProvider.instance;

  @override
  void initState() {
    super.initState();
    _provider.load();
  }

  Future<void> _loadWorkspaces() async {
    await _provider.load();
  }

  void _createNewWorkspace() {
    final textController = TextEditingController();
    String selectedType = 'vscode';
    Get.dialog(
      AlertDialog(
        title: const Text(
          'New Workspace',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: textController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Workspace Name',
                    hintText: 'e.g., Python Dev, Web Workspace',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Workspace Type:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('VS Code'),
                      selected: selectedType == 'vscode',
                      onSelected: (selected) {
                        if (selected) {
                          setDialogState(() => selectedType = 'vscode');
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Shell Only'),
                      selected: selectedType == 'shell',
                      onSelected: (selected) {
                        if (selected) {
                          setDialogState(() => selectedType = 'shell');
                        }
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                Get.back();
                await WorkspaceManager.createWorkspace(name, selectedType);
                _loadWorkspaces();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteWorkspace(Workspace workspace) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            const Text(
              'Delete Workspace?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${workspace.name}"?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'This will programmatically purge and free all container files, Ubuntu rootfs, and installed packages from internal storage.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Container ID: ${workspace.id} • Port: ${workspace.port}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Delete Container'),
            onPressed: () async {
              Get.back();
              final result = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => WorkspaceDeleteProgressDialog(workspace: workspace),
              );
              if (result == true) {
                _loadWorkspaces();
              }
            },
          ),
        ],
      ),
    );
  }

  void _launchWorkspace(Workspace workspace) {
    WorkspaceManager.activeWorkspace = workspace;
    Get.to(() => TerminalPage(workspace: workspace))?.then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _confirmStopWorkspace(Workspace workspace) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.power_settings_new_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text(
              'Stop Workspace?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Do you want to stop "${workspace.name}"?\n\n'
          'All running container processes will be stopped. Your files and installed packages will remain saved on disk and you can start it again at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Get.back();
              await WorkspaceManager.stopWorkspace(workspace.id);
              if (mounted) {
                setState(() {});
              }
            },
            child: const Text('Stop Workspace'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Consumer<WorkspaceProvider>(builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Code LFA Workspaces',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
          ),
          body: _provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _provider.workspaces.isEmpty
                  ? _buildEmptyState()
                  : _buildWorkspaceList(colorScheme),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _createNewWorkspace,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Workspace'),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.developer_board_off_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Workspaces Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first Ubuntu workspace container to run VS Code locally.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _createNewWorkspace,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Workspace'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceList(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: WorkspaceManager.workspaces.length,
      itemBuilder: (context, index) {
        final workspace = WorkspaceManager.workspaces[index];
        final isRunning = WorkspaceManager.isWorkspaceRunning(workspace.id);

        DateTime? createDate;
        try {
          createDate = DateTime.parse(workspace.createTime);
        } catch (_) {}

        final dateStr = createDate != null
            ? DateFormat('yyyy-MM-dd HH:mm').format(createDate)
            : 'Unknown';

        return Card(
          key: ValueKey(workspace.id),
          margin: const EdgeInsets.only(bottom: 12),
          elevation: isRunning ? 2 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isRunning
                  ? Colors.green.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: isRunning ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _launchWorkspace(workspace),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: workspace.type == 'shell'
                            ? colorScheme.secondaryContainer
                            : colorScheme.primaryContainer,
                        child: Icon(
                          workspace.type == 'shell'
                              ? Icons.terminal_rounded
                              : Icons.code_rounded,
                          color: workspace.type == 'shell'
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onPrimaryContainer,
                        ),
                      ),
                      if (isRunning)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.surface,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                workspace.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: workspace.type == 'shell'
                                    ? colorScheme.secondaryContainer
                                    : colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                workspace.type == 'shell' ? 'SHELL' : 'VSCODE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: workspace.type == 'shell'
                                      ? colorScheme.onSecondaryContainer
                                      : colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            if (isRunning) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: const BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'ACTIVE',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Created: $dateStr',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Port: ${workspace.port} • ID: ${workspace.id}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isRunning) ...[
                    IconButton(
                      icon: const Icon(Icons.launch_rounded),
                      color: Colors.green,
                      iconSize: 26,
                      onPressed: () => _launchWorkspace(workspace),
                      tooltip: 'Resume Workspace',
                    ),
                    IconButton(
                      icon: const Icon(Icons.power_settings_new_rounded),
                      color: Colors.orange,
                      iconSize: 22,
                      onPressed: () => _confirmStopWorkspace(workspace),
                      tooltip: 'Stop Workspace',
                    ),
                  ] else ...[
                    IconButton(
                      icon: const Icon(Icons.play_arrow_rounded),
                      color: colorScheme.primary,
                      iconSize: 28,
                      onPressed: () => _launchWorkspace(workspace),
                      tooltip: 'Launch Workspace',
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: colorScheme.error,
                    onPressed: () => _confirmDeleteWorkspace(workspace),
                    tooltip: 'Delete Workspace',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class WorkspaceDeleteProgressDialog extends StatefulWidget {
  final Workspace workspace;

  const WorkspaceDeleteProgressDialog({
    super.key,
    required this.workspace,
  });

  @override
  State<WorkspaceDeleteProgressDialog> createState() => _WorkspaceDeleteProgressDialogState();
}

class _WorkspaceDeleteProgressDialogState extends State<WorkspaceDeleteProgressDialog> {
  double _progress = 0.0;
  String _status = 'Initializing container removal...';
  bool _isError = false;
  String _errorMessage = '';
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _startDeletion();
  }

  Future<void> _startDeletion() async {
    try {
      await WorkspaceManager.deleteWorkspace(
        widget.workspace,
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _status = status;
              _progress = progress;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _isCompleted = true;
          _progress = 1.0;
          _status = 'Container removed from internal storage successfully!';
        });
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: _isError || _isCompleted,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isError
                          ? colorScheme.errorContainer
                          : _isCompleted
                              ? Colors.green.withValues(alpha: 0.15)
                              : colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isError
                          ? Icons.error_outline_rounded
                          : _isCompleted
                              ? Icons.check_circle_rounded
                              : Icons.delete_sweep_rounded,
                      color: _isError
                          ? colorScheme.error
                          : _isCompleted
                              ? Colors.green
                              : colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isError
                              ? 'Removal Failed'
                              : _isCompleted
                                  ? 'Removed Successfully'
                                  : 'Removing Container',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.workspace.name,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (!_isError) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    minHeight: 8,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _isCompleted ? Colors.green : colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _status,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(_progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

