import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/chat_message.dart';
import '../providers/app_providers.dart';
import '../services/api_service.dart';
import '../services/file_manager.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isStreaming = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isStreaming) return;

    _inputController.clear();

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
    );

    ref.read(chatMessagesProvider.notifier).addMessage(userMessage);
    _scrollToBottom();

    final assistantId = '${DateTime.now().millisecondsSinceEpoch}_ai';
    final assistantMessage = ChatMessage(
      id: assistantId,
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      status: MessageStatus.streaming,
    );

    ref.read(chatMessagesProvider.notifier).addMessage(assistantMessage);
    setState(() => _isStreaming = true);

    try {
      final apiService = ref.read(apiServiceProvider);
      final messages = ref.read(chatMessagesProvider)
          .where((m) => m.status != MessageStatus.streaming)
          .toList();

      final stream = apiService.sendMessageStream(messages);

      await for (final chunk in stream) {
        ref.read(chatMessagesProvider.notifier).appendToMessage(assistantId, chunk);
        _scrollToBottom();
      }

      final currentMessages = ref.read(chatMessagesProvider);
      final finalMsg = currentMessages.firstWhere((m) => m.id == assistantId);
      ref.read(chatMessagesProvider.notifier).updateMessage(
        assistantId,
        finalMsg.copyWith(status: MessageStatus.sent),
      );
    } catch (e) {
      final currentMessages = ref.read(chatMessagesProvider);
      final errMsg = currentMessages.firstWhere(
        (m) => m.id == assistantId,
        orElse: () => assistantMessage,
      );
      ref.read(chatMessagesProvider.notifier).updateMessage(
        assistantId,
        errMsg.copyWith(
          status: MessageStatus.error,
          errorText: e.toString(),
        ),
      );
    } finally {
      setState(() => _isStreaming = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('AI Terminal', style: GoogleFonts.jetBrainsMono()),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              ref.read(chatMessagesProvider.notifier).clearMessages();
            },
            tooltip: 'Clear Chat',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(colorScheme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(
                          messages[index], isDark, colorScheme);
                    },
                  ),
          ),
          _buildInputBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terminal,
              size: 80, color: colorScheme.primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            'AI Terminal Controller',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask me anything or request code...',
            style: GoogleFonts.jetBrainsMono(
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
      ChatMessage message, bool isDark, ColorScheme colorScheme) {
    final isUser = message.role == MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: message.status == MessageStatus.error
            ? _buildErrorMessage(message, colorScheme)
            : _buildMessageContent(message, isDark, colorScheme),
      ),
    );
  }

  Widget _buildErrorMessage(ChatMessage message, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Text('Error', style: GoogleFonts.jetBrainsMono(color: Colors.red)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message.errorText ?? 'Unknown error',
            style: GoogleFonts.jetBrainsMono(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(
      ChatMessage message, bool isDark, ColorScheme colorScheme) {
    if (message.status == MessageStatus.streaming && message.content.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // Parse content for code blocks
    final parts = _parseContent(message.content);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: parts.map((part) {
          if (part['type'] == 'code') {
            return _buildCodeBlock(
              part['code'] ?? '',
              part['language'] ?? '',
              isDark,
              colorScheme,
            );
          } else {
            return MarkdownBody(
              data: part['text'] ?? '',
              styleSheet: MarkdownStyleSheet(
                p: GoogleFonts.jetBrainsMono(fontSize: 13),
                code: GoogleFonts.jetBrainsMono(fontSize: 12),
              ),
            );
          }
        }).toList(),
      ),
    );
  }

  List<Map<String, String>> _parseContent(String content) {
    final parts = <Map<String, String>>[];
    final codeBlockRegex = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    int lastEnd = 0;

    for (final match in codeBlockRegex.allMatches(content)) {
      if (match.start > lastEnd) {
        parts.add({
          'type': 'text',
          'text': content.substring(lastEnd, match.start),
        });
      }
      parts.add({
        'type': 'code',
        'language': match.group(1) ?? '',
        'code': match.group(2) ?? '',
      });
      lastEnd = match.end;
    }

    if (lastEnd < content.length) {
      parts.add({'type': 'text', 'text': content.substring(lastEnd)});
    }

    if (parts.isEmpty) {
      parts.add({'type': 'text', 'text': content});
    }

    return parts;
  }

  Widget _buildCodeBlock(
      String code, String language, bool isDark, ColorScheme colorScheme) {
    final isBash = language == 'bash' || language == 'sh' || language == 'shell';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE8E8E8),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Text(
                  language.isEmpty ? 'code' : language,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const Spacer(),
                // Copy button
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code copied!'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.copy, size: 14),
                      const SizedBox(width: 4),
                      Text('Copy',
                          style: GoogleFonts.jetBrainsMono(fontSize: 11)),
                    ],
                  ),
                ),
                // Run in Termux button (only for bash)
                if (isBash) ...[
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => _runCodeInTermux(code),
                    child: Row(
                      children: [
                        const Icon(Icons.terminal, size: 14,
                            color: Colors.green),
                        const SizedBox(width: 4),
                        Text('Run in Termux',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 11, color: Colors.green)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Code content
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: language.isNotEmpty
                  ? HighlightView(
                      code,
                      language: language,
                      theme: isDark ? atomOneDarkTheme : githubTheme,
                      textStyle: GoogleFonts.jetBrainsMono(fontSize: 12),
                    )
                  : Text(
                      code,
                      style: GoogleFonts.jetBrainsMono(fontSize: 12),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runCodeInTermux(String code) async {
    final fileManager = ref.read(fileManagerProvider);
    final workspace = ref.read(workspacePathProvider);
    try {
      await fileManager.runInTermux(code, workingDir: workspace);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Termux error: $e')),
        );
      }
    }
  }

  Widget _buildInputBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              style: GoogleFonts.jetBrainsMono(fontSize: 13),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Ask AI anything...',
                hintStyle: GoogleFonts.jetBrainsMono(fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          _isStreaming
              ? const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton(
                  onPressed: _sendMessage,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(12),
                  ),
                  child: const Icon(Icons.send, size: 20),
                ),
        ],
      ),
    );
  }
}
