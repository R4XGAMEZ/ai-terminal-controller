import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/app_providers.dart';
import '../services/file_manager.dart';

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  List<FileNode> _fileTree = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLastWorkspace();
  }

  Future<void> _loadLastWorkspace() async {
    final manager = ref.read(fileManagerProvider);
    final lastPath = await manager.getLastWorkspace();
    if (lastPath != null && mounted) {
      ref.read(workspacePathProvider.notifier).state = lastPath;
      await _loadTree(lastPath);
    }
  }

  Future<void> _loadTree(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final manager = ref.read(fileManagerProvider);
      final tree = await manager.buildFileTree(path);
      if (mounted) setState(() => _fileTree = tree);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickWorkspace() async {
    final manager = ref.read(fileManagerProvider);
    try {
      final workspace = await manager.pickWorkspace();
      if (workspace != null && mounted) {
        ref.read(workspacePathProvider.notifier).state = workspace.path;
        await _loadTree(workspace.path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Workspace: ${workspace.name}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () => openAppSettings(),
          textColor: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspacePath = ref.watch(workspacePathProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Workspace', style: GoogleFonts.jetBrainsMono()),
        actions: [
          if (workspacePath != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => _loadTree(workspacePath),
            ),
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: 'Pick workspace folder',
            onPressed: _pickWorkspace,
          ),
        ],
      ),
      body: workspacePath == null
          ? _buildNoWorkspace(colorScheme)
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError(_error!)
                  : _buildFileTree(workspacePath, colorScheme),
      floatingActionButton: workspacePath != null
          ? FloatingActionButton.extended(
              onPressed: () => _showTermuxDialog(workspacePath),
              icon: const Icon(Icons.terminal),
              label: const Text('Open Termux'),
            )
          : null,
    );
  }

  Widget _buildNoWorkspace(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_off_outlined,
              size: 72, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('No Workspace Selected',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Pick a project folder to browse and manage files.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _pickWorkspace,
            icon: const Icon(Icons.folder_open),
            label: const Text('Select Workspace'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              ref.read(workspacePathProvider.notifier).state =
                  '/data/data/com.termux/files/home';
              _loadTree('/data/data/com.termux/files/home');
            },
            icon: const Icon(Icons.home_outlined),
            label: const Text('Use Termux Home'),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _pickWorkspace,
            child: const Text('Try Different Folder'),
          ),
        ],
      ),
    );
  }

  Widget _buildFileTree(String workspacePath, ColorScheme colorScheme) {
    return Column(
      children: [
        // Workspace path breadcrumb
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.folder, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  workspacePath,
                  style: GoogleFonts.jetBrainsMono(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),

        // File tree
        Expanded(
          child: _fileTree.isEmpty
              ? Center(
                  child: Text('Empty folder',
                      style: TextStyle(color: colorScheme.onSurfaceVariant)))
              : ListView.builder(
                  itemCount: _fileTree.length,
                  itemBuilder: (ctx, i) => _FileNodeTile(
                    node: _fileTree[i],
                    depth: 0,
                    onTap: (node) => _onNodeTap(node),
                    workspacePath: workspacePath,
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _onNodeTap(FileNode node) async {
    if (!node.isDirectory) {
      // Open file for viewing
      await _showFileContent(node);
      return;
    }

    // Toggle expand/collapse
    setState(() {
      node.isExpanded = !node.isExpanded;
    });

    if (node.isExpanded && node.children.isEmpty) {
      final manager = ref.read(fileManagerProvider);
      final children = await manager.expandNode(node);
      setState(() {
        node.children = children;
      });
    }
  }

  Future<void> _showFileContent(FileNode node) async {
    if (!node.isCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Binary files cannot be previewed'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final manager = ref.read(fileManagerProvider);
    try {
      final content = await manager.readFile(node.path);
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, scrollCtrl) => Column(
            children: [
              ListTile(
                leading: Text(node.icon),
                title: Text(node.name,
                    style: GoogleFonts.jetBrainsMono(fontSize: 14)),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      content,
                      style: GoogleFonts.jetBrainsMono(fontSize: 12,
                          height: 1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showError('Cannot read file: $e');
    }
  }

  void _showTermuxDialog(String workspacePath) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open in Termux'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Run this command in Termux to navigate here:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                'cd "$workspacePath"',
                style: GoogleFonts.jetBrainsMono(
                    color: Colors.greenAccent, fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.terminal, size: 16),
            label: const Text('Open Termux'),
            onPressed: () async {
              Navigator.pop(ctx);
              final manager = ref.read(fileManagerProvider);
              try {
                await manager.runInTermux('echo "Workspace ready"',
                    workingDir: workspacePath);
              } catch (e) {
                if (mounted) _showError(e.toString());
              }
            },
          ),
        ],
      ),
    );
  }
}

// ─── File Node Tile (recursive) ───────────────────────────────────────────────

class _FileNodeTile extends StatelessWidget {
  final FileNode node;
  final int depth;
  final Function(FileNode) onTap;
  final String workspacePath;

  const _FileNodeTile({
    required this.node,
    required this.depth,
    required this.onTap,
    required this.workspacePath,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        InkWell(
          onTap: () => onTap(node),
          child: Padding(
            padding: EdgeInsets.only(
              left: 16.0 + depth * 20,
              right: 16,
              top: 6,
              bottom: 6,
            ),
            child: Row(
              children: [
                if (node.isDirectory)
                  Icon(
                    node.isExpanded
                        ? Icons.expand_more
                        : Icons.chevron_right,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(width: 4),
                Text(node.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: GoogleFonts.jetBrainsMono(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!node.isDirectory)
                  Text(
                    _formatSize(node.size),
                    style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
        // Recursive children
        if (node.isExpanded && node.children.isNotEmpty)
          ...node.children.map((child) => _FileNodeTile(
                node: child,
                depth: depth + 1,
                onTap: onTap,
                workspacePath: workspacePath,
              )),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}K';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
  }
}
