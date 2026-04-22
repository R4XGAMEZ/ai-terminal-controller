import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      ref.read(workspacePathProvider.notifier).setPath(lastPath);
      await _loadTree(lastPath);
    }
  }

  Future<void> _loadTree(String path) async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final manager = ref.read(fileManagerProvider);
      final tree = await manager.buildFileTree(path);
      setState(() { _fileTree = tree; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _pickWorkspace() async {
    try {
      final manager = ref.read(fileManagerProvider);
      final workspace = await manager.pickWorkspace();
      if (workspace != null && mounted) {
        ref.read(workspacePathProvider.notifier).setPath(workspace.path);
        await _loadTree(workspace.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _toggleNode(FileNode node) async {
    if (!node.isDirectory) return;
    if (node.isExpanded) {
      setState(() {
        node.isExpanded = false;
        node.children = [];
      });
    } else {
      final manager = ref.read(fileManagerProvider);
      final children = await manager.expandNode(node);
      setState(() {
        node.isExpanded = true;
        node.children = children;
      });
    }
  }

  Future<void> _runInTermux(String path) async {
    final manager = ref.read(fileManagerProvider);
    final workspacePath = ref.read(workspacePathProvider);
    try {
      await manager.runInTermux('cat "$path"', workingDir: workspacePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Termux error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspacePath = ref.watch(workspacePathProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Workspace', style: GoogleFonts.jetBrainsMono()),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickWorkspace,
            tooltip: 'Open Workspace',
          ),
          if (workspacePath != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _loadTree(workspacePath),
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: workspacePath == null
          ? _buildEmptyState(colorScheme)
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildErrorState(_error!)
                  : _buildFileTree(),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_outlined,
              size: 80, color: colorScheme.onSurface.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('No Workspace Selected',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Tap the folder icon to open a workspace',
              style: GoogleFonts.jetBrainsMono(
                  color: colorScheme.onSurface.withOpacity(0.5))),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _pickWorkspace,
            icon: const Icon(Icons.folder_open),
            label: Text('Open Workspace', style: GoogleFonts.jetBrainsMono()),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error loading workspace',
              style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(error,
              style: GoogleFonts.jetBrainsMono(fontSize: 12),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildFileTree() {
    final workspacePath = ref.read(workspacePathProvider)!;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.folder, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  workspacePath,
                  style: GoogleFonts.jetBrainsMono(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _fileTree.isEmpty
              ? Center(
                  child: Text('Empty folder',
                      style: GoogleFonts.jetBrainsMono()),
                )
              : ListView.builder(
                  itemCount: _fileTree.length,
                  itemBuilder: (context, index) =>
                      _buildNode(_fileTree[index], 0),
                ),
        ),
      ],
    );
  }

  Widget _buildNode(FileNode node, int depth) {
    return Column(
      children: [
        InkWell(
          onTap: () => _toggleNode(node),
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _showFileOptions(node);
          },
          child: Padding(
            padding: EdgeInsets.only(
                left: 16.0 + depth * 16, right: 8, top: 4, bottom: 4),
            child: Row(
              children: [
                Text(node.icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: GoogleFonts.jetBrainsMono(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (node.isDirectory)
                  Icon(
                    node.isExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 16,
                  ),
              ],
            ),
          ),
        ),
        if (node.isExpanded)
          ...node.children.map((child) => _buildNode(child, depth + 1)),
        const Divider(height: 1, thickness: 0.3),
      ],
    );
  }

  void _showFileOptions(FileNode node) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text('Copy Path', style: GoogleFonts.jetBrainsMono()),
            onTap: () {
              Clipboard.setData(ClipboardData(text: node.path));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Path copied!')),
              );
            },
          ),
          if (!node.isDirectory)
            ListTile(
              leading: const Icon(Icons.terminal),
              title: Text('Open in Termux', style: GoogleFonts.jetBrainsMono()),
              onTap: () {
                Navigator.pop(ctx);
                _runInTermux(node.path);
              },
            ),
        ],
      ),
    );
  }
}
