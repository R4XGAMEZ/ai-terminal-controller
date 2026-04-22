import 'package:uuid/uuid.dart';

enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isError;
  final List<CodeBlock> codeBlocks;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isError = false,
    List<CodeBlock>? codeBlocks,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now(),
        codeBlocks = codeBlocks ?? _extractCodeBlocks(content);

  ChatMessage copyWith({
    String? content,
    bool? isError,
    List<CodeBlock>? codeBlocks,
  }) =>
      ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        timestamp: timestamp,
        isError: isError ?? this.isError,
        codeBlocks: codeBlocks ?? _extractCodeBlocks(content ?? this.content),
      );

  static List<CodeBlock> _extractCodeBlocks(String content) {
    final regex = RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true);
    return regex.allMatches(content).map((m) {
      return CodeBlock(
        language: m.group(1) ?? '',
        code: m.group(2)?.trim() ?? '',
        isBash: (m.group(1) ?? '').toLowerCase() == 'bash' ||
            (m.group(1) ?? '').toLowerCase() == 'sh',
      );
    }).toList();
  }

  bool get hasCode => codeBlocks.isNotEmpty;
  bool get hasBashCommands => codeBlocks.any((b) => b.isBash);

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'isError': isError,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        role: MessageRole.values.firstWhere((r) => r.name == json['role']),
        content: json['content'],
        timestamp: DateTime.parse(json['timestamp']),
        isError: json['isError'] ?? false,
      );
}

class CodeBlock {
  final String language;
  final String code;
  final bool isBash;

  const CodeBlock({
    required this.language,
    required this.code,
    required this.isBash,
  });
}
