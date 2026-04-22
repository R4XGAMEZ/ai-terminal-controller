import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

// ─── Workspace Model ──────────────────────────────────────────────────────────

class WorkspaceInfo {
  final String path;
  final String name;
  final DateTime lastOpened;
  final int fileCount;

  const WorkspaceInfo({
    required this.path,
    required this.name,
    required this.lastOpened,
    required this.fileCount,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'lastOpened': lastOpened.toIso8601String(),
        'fileCount': fileCount,
      };

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) => WorkspaceInfo(
        path: json['path'],
        name: json['name'],
        lastOpened: DateTime.parse(json['lastOpened']),
        fileCount: json['fileCount'] ?? 0,
      );
}

// ─── File Tree Node ───────────────────────────────────────────────────────────

class FileNode {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  List<FileNode> children;
  bool isExpanded;

  FileNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    required this.modified,
    this.children = const [],
    this.isExpanded = false,
  });

  String get extension => p.extension(name).toLowerCase();

  bool get isCode => [
        '.dart', '.py', '.js', '.ts', '.java', '.kt', '.cpp',
        '.c', '.h', '.go', '.rs', '.sh', '.bash', '.yml', '.yaml',
        '.json', '.xml', '.html', '.css', '.md', '.txt',
      ].contains(extension);

  String get icon {
    if (isDirectory) return isExpanded ? '📂' : '📁';
    switch (extension) {
      case '.dart': return '🎯';
      case '.py': return '🐍';
      case '.js':
      case '.ts': return '⚡';
      case '.java':
      case '.kt': return '☕';
      case '.sh':
      case '.bash': return '🔧';
      case '.json': return '📋';
      case '.yaml':
      case '.yml': return '⚙️';
      case '.md': return '📝';
      default: return '📄';
    }
  }
}

// ─── File Manager Service ─────────────────────────────────────────────────────

class FileManagerService {
  static const _workspacePrefKey = 'last_workspace';
  static const _recentWorkspacesPrefKey = 'recent_workspaces';

  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    final result = await [
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();
    return result[Permission.storage]?.isGranted == true ||
        result[Permission.manageExternalStorage]?.isGranted == true;
  }

  Future<WorkspaceInfo?> pickWorkspace() async {
    final granted = await requestStoragePermission();
    if (!granted) throw Exception('Storage permission denied');
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Project Workspace',
    );
    if (result == null) return null;
    final dir = Directory(result);
    final fileCount = await _countFiles(dir);
    final workspace = WorkspaceInfo(
      path: result,
      name: p.basename(result),
      lastOpened: DateTime.now(),
      fileCount: fileCount,
    );
    await _saveWorkspace(workspace);
    return workspace;
  }

  Future<int> _countFiles(Directory dir) async {
    try {
      int count = 0;
      await for (final _ in dir.list(recursive: false)) {
        count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _saveWorkspace(WorkspaceInfo workspace) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_workspacePrefKey, workspace.path);
    final recentJson = prefs.getStringList(_recentWorkspacesPrefKey) ?? [];
    final recent = recentJson
        .map((e) {
          try {
            return WorkspaceInfo.fromJson(jsonDecode(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<WorkspaceInfo>()
        .where((w) => w.path != workspace.path)
        .take(4)
        .toList();
    recent.insert(0, workspace);
    await prefs.setStringList(
      _recentWorkspacesPrefKey,
      recent.map((w) => jsonEncode(w.toJson())).toList(),
    );
  }

  Future<String?> getLastWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_workspacePrefKey);
  }

  Future<List<FileNode>> buildFileTree(String dirPath, {int depth = 0}) async {
    if (depth > 3) return [];
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    final List<FileNode> nodes = [];
    try {
      final entities = await dir
          .list(followLinks: false)
          .where((e) => !p.basename(e.path).startsWith('.'))
          .toList();
      entities.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return p.basename(a.path).compareTo(p.basename(b.path));
      });
      for (final entity in entities) {
        final stat = await entity.stat();
        final isDir = entity is Directory;
        nodes.add(FileNode(
          name: p.basename(entity.path),
          path: entity.path,
          isDirectory: isDir,
          size: isDir ? 0 : stat.size,
          modified: stat.modified,
        ));
      }
    } catch (e) {
      debugPrint('Error listing directory: $e');
    }
    return nodes;
  }

  Future<List<FileNode>> expandNode(FileNode node) async {
    if (!node.isDirectory) return [];
    return buildFileTree(node.path, depth: 1);
  }

  Future<String> readFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (e) {
      throw Exception('Cannot read file: $e');
    }
  }

  Future<void> writeFile(String path, String content) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    } catch (e) {
      throw Exception('Cannot write file: $e');
    }
  }

  Future<void> createFile(String dirPath, String fileName) async {
    final path = p.join(dirPath, fileName);
    await File(path).create(recursive: true);
  }

  Future<void> deleteFile(String path) async {
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  Future<void> renameFile(String oldPath, String newName) async {
    final newPath = p.join(p.dirname(oldPath), newName);
    if (await FileSystemEntity.isDirectory(oldPath)) {
      await Directory(oldPath).rename(newPath);
    } else {
      await File(oldPath).rename(newPath);
    }
  }

  Future<void> runInTermux(String command, {String? workingDir}) async {
    if (!Platform.isAndroid) throw Exception('Termux only works on Android');
    try {
      final fullCommand = workingDir != null
          ? 'cd "$workingDir" && $command'
          : command;
      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        package: 'com.termux',
        componentName: 'com.termux.app.TermuxActivity',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        arguments: {
          'com.termux.RUN_COMMAND_PATH': '/data/data/com.termux/files/usr/bin/bash',
          'com.termux.RUN_COMMAND_ARGUMENTS': ['-c', fullCommand],
          'com.termux.RUN_COMMAND_WORKDIR': workingDir ?? '/data/data/com.termux/files/home',
          'com.termux.RUN_COMMAND_BACKGROUND': false,
        },
      );
      await intent.launch();
    } catch (e) {
      await _openTermux();
      rethrow;
    }
  }

  Future<void> _openTermux() async {
    final intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      package: 'com.termux',
      flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    await intent.launch();
  }

  Future<bool> isTermuxInstalled() async {
    if (!Platform.isAndroid) return false;
    return true;
  }

  Future<List<PlatformFile>?> pickFiles({
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: allowedExtensions != null ? FileType.custom : FileType.any,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
      withData: false,
      withReadStream: false,
    );
    return result?.files;
  }

  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String getTermuxHomePath() => '/data/data/com.termux/files/home';
  String getTermuxBinPath() => '/data/data/com.termux/files/usr/bin';
}

// ─── Providers ────────────────────────────────────────────────────────────────

final fileManagerProvider = Provider<FileManagerService>((ref) {
  return FileManagerService();
});

final fileTreeProvider =
    FutureProvider.family<List<FileNode>, String>((ref, path) async {
  final manager = ref.read(fileManagerProvider);
  return manager.buildFileTree(path);
});
