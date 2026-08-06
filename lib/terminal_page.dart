import 'package:code_lfa/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:xterm/xterm.dart';
import 'terminal_controller.dart';
import 'terminal_theme.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  HomeController controller = Get.put(HomeController());
  ManjaroTerminalTheme terminalTheme = ManjaroTerminalTheme();
  bool visible = false || kDebugMode;

  @override
  void initState() {
    super.initState();
    if (controller.isShellOnly) {
      visible = true;
    }
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
    return Scaffold(
      backgroundColor: visible ? terminalTheme.background : Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: PopScope(
          onPopInvokedWithResult: (didPop, result) {
            controller.pseudoTerminal?.writeString('\x03');
            Get.back();
          },
          canPop: true,
          child: Column(
            children: [
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
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Visibility(
                          visible: visible,
                          child: AbsorbPointer(
                            absorbing: false,
                            child: TerminalView(
                              controller.terminal,
                              readOnly: false,
                              backgroundOpacity: 1,
                              theme: ManjaroTerminalTheme(),
                            ),
                          ),
                        ),
                      ),
                      GetBuilder<HomeController>(
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
                builder: (controller) {
                  if (controller.isShellOnly && !controller.vsCodeStaring) {
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
