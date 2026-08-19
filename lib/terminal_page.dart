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
  final Workspace workspace;
  const TerminalPage({super.key, required this.workspace});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late final HomeController controller;
  final ManjaroTerminalTheme terminalTheme = ManjaroTerminalTheme();
  late bool visible;

  // Keyboard modifier states
  bool _ctrlActive = false;
  bool _altActive = false;
  bool _shiftActive = false;
  bool _stickyModifiers = false;
  int _keyboardCategory = 0; // 0: Main & Nav, 1: F1-F12, 2: Symbols

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<HomeController>(tag: widget.workspace.id)) {
      controller = Get.find<HomeController>(tag: widget.workspace.id);
    } else {
      controller = Get.put(
        HomeController(workspace: widget.workspace),
        tag: widget.workspace.id,
        permanent: true,
      );
    }
    visible = controller.isShellOnly || kDebugMode;
  }

  void _sendKey(String code, {bool isControlChar = false}) {
    final pty = controller.activePty;
    if (pty == null) return;

    if (isControlChar && _ctrlActive) {
      if (code.length == 1) {
        final upper = code.toUpperCase();
        final asciiVal = upper.codeUnitAt(0);
        if (asciiVal >= 64 && asciiVal <= 95) {
          pty.writeString(String.fromCharCode(asciiVal - 64));
        } else {
          pty.writeString(code);
        }
      } else {
        pty.writeString(code);
      }
    } else {
      pty.writeString(code);
    }

    if (!_stickyModifiers) {
      if (_ctrlActive || _altActive || _shiftActive) {
        setState(() {
          _ctrlActive = false;
          _altActive = false;
          _shiftActive = false;
        });
      }
    }
  }

  void _showRenameTabDialog(int index, String currentName) {
    final textCtrl = TextEditingController(text: currentName);
    Get.dialog(
      AlertDialog(
        title: const Text('Rename Tab'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tab Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = textCtrl.text.trim();
              if (newName.isNotEmpty) {
                controller.renameTab(index, newName);
              }
              Get.back();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmPowerOff() {
    Get.dialog(
      AlertDialog(
        title: const Text('Power Off Workspace?'),
        content: Text('Are you sure you want to power off "${widget.workspace.name}"?\nAll running tasks in this container will be gracefully stopped.'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[800],
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Get.back();
              await WorkspaceManager.powerOff(widget.workspace);
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Power Off'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                tooltip: 'Back to Workspaces',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.workspace.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.workspace.type.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Port: ${widget.workspace.port} • ID: ${widget.workspace.id}',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 22),
                tooltip: 'Power Off Container',
                onPressed: _confirmPowerOff,
              ),
            ],
          ),
          if (controller.isShellOnly) _buildShellTabBar(),
        ],
      ),
    );
  }

  Widget _buildShellTabBar() {
    return GetBuilder<HomeController>(
      tag: widget.workspace.id,
      builder: (ctrl) {
        if (ctrl.shellTabs.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 36,
          margin: const EdgeInsets.only(top: 4, bottom: 2),
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: ctrl.shellTabs.length,
                  itemBuilder: (context, index) {
                    final tab = ctrl.shellTabs[index];
                    final isActive = index == ctrl.activeTabIndex;

                    return GestureDetector(
                      onTap: () => ctrl.selectTab(index),
                      onLongPress: () => _showRenameTabDialog(index, tab.name),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.blueGrey[800] : Colors.grey[850],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.terminal_rounded,
                              size: 14,
                              color: isActive ? Colors.white : Colors.white60,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              tab.name,
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.white70,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                            if (ctrl.shellTabs.length > 1) ...[
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => ctrl.closeTab(index),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                tooltip: 'New Shell Tab',
                onPressed: () => ctrl.addNewTab(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  padding: const EdgeInsets.all(6),
                  minimumSize: const Size(32, 32),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdvancedKeyboard() {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Category selector & Modifiers Row
          Row(
            children: [
              _buildCategoryChip(0, 'Main & Nav'),
              const SizedBox(width: 4),
              _buildCategoryChip(1, 'F1-F12'),
              const SizedBox(width: 4),
              _buildCategoryChip(2, 'Symbols'),
              const Spacer(),
              _buildModifierKey('Ctrl', _ctrlActive, () {
                setState(() => _ctrlActive = !_ctrlActive);
              }),
              const SizedBox(width: 4),
              _buildModifierKey('Alt', _altActive, () {
                setState(() => _altActive = !_altActive);
              }),
              const SizedBox(width: 4),
              _buildModifierKey('Shift', _shiftActive, () {
                setState(() => _shiftActive = !_shiftActive);
              }),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() => _stickyModifiers = !_stickyModifiers),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: _stickyModifiers ? Colors.amber[800] : Colors.grey[800],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    _stickyModifiers ? Icons.lock_rounded : Icons.lock_open_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Scrollable Key row based on category
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _getCategoryKeys(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(int catIndex, String label) {
    final isSelected = _keyboardCategory == catIndex;
    return InkWell(
      onTap: () => setState(() => _keyboardCategory = catIndex),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[800],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildModifierKey(String label, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.deepOrangeAccent : Colors.grey[800],
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? Colors.white : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  List<Widget> _getCategoryKeys() {
    switch (_keyboardCategory) {
      case 1:
        // F1-F12
        return [
          _buildKeyBtn('F1', '\x1bOP'),
          _buildKeyBtn('F2', '\x1bOQ'),
          _buildKeyBtn('F3', '\x1bOR'),
          _buildKeyBtn('F4', '\x1bOS'),
          _buildKeyBtn('F5', '\x1b[15~'),
          _buildKeyBtn('F6', '\x1b[17~'),
          _buildKeyBtn('F7', '\x1b[18~'),
          _buildKeyBtn('F8', '\x1b[19~'),
          _buildKeyBtn('F9', '\x1b[20~'),
          _buildKeyBtn('F10', '\x1b[21~'),
          _buildKeyBtn('F11', '\x1b[23~'),
          _buildKeyBtn('F12', '\x1b[24~'),
        ];
      case 2:
        // Symbols
        return [
          _buildKeyBtn('|', '|'),
          _buildKeyBtn('~', '~'),
          _buildKeyBtn('/', '/'),
          _buildKeyBtn('\\', '\\'),
          _buildKeyBtn('-', '-'),
          _buildKeyBtn('_', '_'),
          _buildKeyBtn('=', '='),
          _buildKeyBtn('+', '+'),
          _buildKeyBtn(':', ':'),
          _buildKeyBtn(';', ';'),
          _buildKeyBtn('"', '"'),
          _buildKeyBtn('\'', '\''),
          _buildKeyBtn('`', '`'),
          _buildKeyBtn('<', '<'),
          _buildKeyBtn('>', '>'),
          _buildKeyBtn('[', '['),
          _buildKeyBtn(']', ']'),
          _buildKeyBtn('{', '{'),
          _buildKeyBtn('}', '}'),
        ];
      case 0:
      default:
        // Main & Nav
        return [
          _buildKeyBtn('ESC', '\x1b'),
          _buildKeyBtn('TAB', '\t'),
          _buildKeyBtn('Ctrl+C', '\x03'),
          _buildKeyBtn('Ctrl+D', '\x04'),
          _buildKeyBtn('Ctrl+Z', '\x1a'),
          _buildKeyBtn('Ctrl+K', '\x0b'),
          _buildKeyBtn('Ctrl+\\', '\x1c'),
          _buildKeyBtn('Home', '\x1b[H'),
          _buildKeyBtn('End', '\x1b[F'),
          _buildKeyBtn('PgUp', '\x1b[5~'),
          _buildKeyBtn('PgDn', '\x1b[6~'),
          _buildKeyBtn('Ins', '\x1b[2~'),
          _buildKeyBtn('Del', '\x1b[3~'),
          _buildKeyBtn('↑', '\x1b[A'),
          _buildKeyBtn('↓', '\x1b[B'),
          _buildKeyBtn('←', '\x1b[D'),
          _buildKeyBtn('→', '\x1b[C'),
        ];
    }
  }

  Widget _buildKeyBtn(String label, String code) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _sendKey(code),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: visible ? terminalTheme.background : Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: PopScope(
          canPop: true,
          child: Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (!controller.isShellOnly) {
                      visible = !visible;
                      setState(() {});
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      GetBuilder<HomeController>(
                        tag: widget.workspace.id,
                        builder: (ctrl) {
                          return Padding(
                            padding: const EdgeInsets.all(6),
                            child: Visibility(
                              visible: visible,
                              child: AbsorbPointer(
                                absorbing: false,
                                child: TerminalView(
                                  ctrl.activeTerminal,
                                  controller: ctrl.activeTerminalController,
                                  readOnly: false,
                                  backgroundOpacity: 1,
                                  theme: ManjaroTerminalTheme(),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      GetBuilder<HomeController>(
                        tag: widget.workspace.id,
                        builder: (controller) {
                          if (!controller.vsCodeStaring) {
                            return const SizedBox.shrink();
                          }
                          return Center(
                            child: Material(
                              borderRadius: BorderRadius.circular(12),
                              color: Theme.of(context).colorScheme.surface,
                              child: SizedBox(
                                width: 300,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Center(
                                        child: RepaintBoundary(
                                          child: LoadingProgress(
                                            minRadius: 6,
                                            strokeWidth: 3,
                                            increaseRadius: 3,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Stack(
                                        children: [
                                          Container(
                                            height: 5,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primary,
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          ),
                                          AnimatedContainer(
                                            duration: 300.milliseconds,
                                            height: 5,
                                            width: 300 * controller.progress,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primary,
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        controller.currentProgress.trim(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onSurface,
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
                tag: widget.workspace.id,
                builder: (controller) {
                  if (controller.isShellOnly && !controller.vsCodeStaring) {
                    return _buildAdvancedKeyboard();
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


