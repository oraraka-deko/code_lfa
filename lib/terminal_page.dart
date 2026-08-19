import 'package:code_lfa/utils.dart';
import 'package:code_lfa/workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:xterm/xterm.dart';
import 'terminal_controller.dart';
import 'terminal_theme.dart';

class TerminalPage extends StatefulWidget {
  final Workspace? workspace;

  const TerminalPage({super.key, this.workspace});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late Workspace currentWorkspace;
  late HomeController controller;
  final ManjaroTerminalTheme terminalTheme = ManjaroTerminalTheme();
  bool visible = false || kDebugMode;

  @override
  void initState() {
    super.initState();
    currentWorkspace = widget.workspace ??
        WorkspaceManager.activeWorkspace ??
        Workspace(
          id: 'ubuntu',
          name: 'Default Workspace',
          port: 20000,
          createTime: '',
          type: 'vscode',
        );

    controller = WorkspaceManager.getController(currentWorkspace);

    if (controller.isShellOnly) {
      visible = true;
    }

    if (!controller.isRunning) {
      controller.loadCodeServer();
    }
  }

  void _confirmStopWorkspace() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.power_settings_new_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Stop Workspace?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to stop "${currentWorkspace.name}"?\n\n'
          'All running processes will be terminated. Your workspace files will remain saved on disk.',
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
              await WorkspaceManager.stopWorkspace(currentWorkspace.id);
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Stop Workspace'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme colorScheme) {
    return Container(
      height: 38,
      color: Colors.grey[900],
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: controller.tabs.length,
              itemBuilder: (context, index) {
                final tab = controller.tabs[index];
                final isSelected = index == controller.activeTabIndex;
                return Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                  child: Material(
                    color: isSelected ? Colors.grey[800] : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => controller.selectTerminalTab(index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.terminal_rounded,
                              size: 15,
                              color: isSelected ? Colors.greenAccent : Colors.grey[400],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              tab.title,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Colors.white : Colors.grey[400],
                              ),
                            ),
                            if (controller.tabs.length > 1) ...[
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => controller.closeTerminalTab(index),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: isSelected ? Colors.white70 : Colors.grey[500],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: IconButton(
              icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              tooltip: 'New Terminal Window',
              onPressed: () => controller.addNewTerminalTab(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalToolbar() {
    final buttons = [
      _ToolbarKey(label: 'ESC', code: '\x1b'),
      _ToolbarKey(label: 'TAB', code: '\t'),
      _ToolbarKey(label: 'Ctrl+C', code: '\x03'),
      _ToolbarKey(label: 'Ctrl+D', code: '\x04'),
      _ToolbarKey(label: 'Ctrl+Z', code: '\x1a'),
      _ToolbarKey(label: '↑', code: '\x1b[A'),
      _ToolbarKey(label: '↓', code: '\x1b[B'),
      _ToolbarKey(label: '←', code: '\x1b[D'),
      _ToolbarKey(label: '→', code: '\x1b[C'),
    ];

    return Container(
      color: Colors.grey[900],
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: buttons.length,
        itemBuilder: (context, index) {
          final btn = buttons[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  controller.pseudoTerminal?.writeString(btn.code);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  child: Text(
                    btn.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Allow normal popping back to workspace list; process continues in background
      },
      child: Scaffold(
        backgroundColor: visible ? terminalTheme.background : colorScheme.surface,
        appBar: AppBar(
          backgroundColor: visible ? Colors.grey[900] : colorScheme.surface,
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back to Workspaces (Keep in background)',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentWorkspace.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: visible ? Colors.white : colorScheme.onSurface,
                ),
              ),
              GetBuilder<HomeController>(
                init: controller,
                builder: (ctrl) {
                  final isRunning = ctrl.isRunning;
                  final isStarting = ctrl.vsCodeStaring;
                  return Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isStarting
                              ? Colors.amber
                              : isRunning
                                  ? Colors.greenAccent
                                  : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isStarting
                            ? 'Starting container...'
                            : isRunning
                                ? (currentWorkspace.type == 'shell'
                                    ? 'Shell Active (${ctrl.tabs.length} window${ctrl.tabs.length > 1 ? 's' : ''})'
                                    : 'VS Code Active • Port ${currentWorkspace.port}')
                                : 'Stopped',
                        style: TextStyle(
                          fontSize: 11,
                          color: visible ? Colors.grey[400] : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          actions: [
            if (!controller.isShellOnly)
              IconButton(
                icon: const Icon(Icons.open_in_browser_rounded),
                tooltip: 'Open VS Code Web View',
                onPressed: () => openWebView(port: currentWorkspace.port),
              ),
            IconButton(
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'New Terminal Window',
              onPressed: () {
                if (!visible) setState(() => visible = true);
                controller.addNewTerminalTab();
              },
            ),
            IconButton(
              icon: Icon(
                visible ? Icons.visibility_off_outlined : Icons.terminal_rounded,
              ),
              tooltip: visible ? 'Hide Terminal' : 'Show Terminal',
              onPressed: () {
                setState(() => visible = !visible);
              },
            ),
            IconButton(
              icon: const Icon(Icons.power_settings_new_rounded),
              color: Colors.redAccent,
              tooltip: 'Stop Workspace',
              onPressed: _confirmStopWorkspace,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              GetBuilder<HomeController>(
                init: controller,
                builder: (ctrl) {
                  if (visible && ctrl.isRunning && ctrl.tabs.isNotEmpty) {
                    return _buildTabBar(colorScheme);
                  }
                  return const SizedBox.shrink();
                },
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (!controller.isShellOnly) {
                      setState(() => visible = !visible);
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Visibility(
                          visible: visible,
                          child: AbsorbPointer(
                            absorbing: false,
                            child: GetBuilder<HomeController>(
                              init: controller,
                              builder: (ctrl) {
                                return TerminalView(
                                  ctrl.terminal,
                                  key: ValueKey(ctrl.currentTab?.id ?? 'default'),
                                  readOnly: false,
                                  backgroundOpacity: 1,
                                  theme: ManjaroTerminalTheme(),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      GetBuilder<HomeController>(
                        init: controller,
                        builder: (ctrl) {
                          if (!ctrl.vsCodeStaring) {
                            return const SizedBox.shrink();
                          }
                          return Center(
                            child: Material(
                              borderRadius: BorderRadius.circular(16),
                              elevation: 6,
                              color: colorScheme.surface,
                              child: SizedBox(
                                width: 300,
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const RepaintBoundary(
                                        child: LoadingProgress(
                                          minRadius: 6,
                                          strokeWidth: 3,
                                          increaseRadius: 3,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: ctrl.progress > 0 ? ctrl.progress : null,
                                          minHeight: 6,
                                          backgroundColor: colorScheme.surfaceContainerHighest,
                                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        ctrl.currentProgress.isNotEmpty
                                            ? ctrl.currentProgress.trim()
                                            : 'Starting Workspace Container...',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              GetBuilder<HomeController>(
                init: controller,
                builder: (ctrl) {
                  if (ctrl.isShellOnly && !ctrl.vsCodeStaring) {
                    return _buildTerminalToolbar();
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarKey {
  final String label;
  final String code;
  _ToolbarKey({required this.label, required this.code});
}

