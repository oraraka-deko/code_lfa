import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'workspace.dart';
import 'terminal_page.dart';

class WorkspaceListPage extends StatefulWidget {
  const WorkspaceListPage({super.key});

  @override
  State<WorkspaceListPage> createState() => _WorkspaceListPageState();
}

class _WorkspaceListPageState extends State<WorkspaceListPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkspaces();
  }

  Future<void> _loadWorkspaces() async {
    setState(() => _loading = true);
    await WorkspaceManager.load();
    if (mounted) {
      setState(() => _loading = false);
    }
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
        title: const Text(
          'Delete Workspace?',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
        ),
        content: Text(
          'Are you sure you want to delete "${workspace.name}"?\n\n'
          'This will permanently delete its Ubuntu container, installed packages, and all local files in this workspace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Get.back();
              setState(() => _loading = true);
              await WorkspaceManager.deleteWorkspace(workspace);
              _loadWorkspaces();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _launchWorkspace(Workspace workspace) {
    WorkspaceManager.activeWorkspace = workspace;
    Get.to(() => const TerminalPage())?.then((_) {
      // Reload lists or clean up when returning
      _loadWorkspaces();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Code FA Workspaces',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : WorkspaceManager.workspaces.isEmpty
              ? _buildEmptyState()
              : _buildWorkspaceList(colorScheme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewWorkspace,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Workspace'),
      ),
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
              color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
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
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outlineVariant.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _launchWorkspace(workspace),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
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
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              workspace.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
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
                            color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.play_arrow_rounded),
                    color: Colors.green,
                    iconSize: 28,
                    onPressed: () => _launchWorkspace(workspace),
                    tooltip: 'Launch Workspace',
                  ),
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
