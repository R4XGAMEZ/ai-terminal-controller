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
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _isComposing = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
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
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      _showNoApiKeyDialog();
      return;
    }

    _controller.clear();
    setState(() => _isComposing = false);

    // Add user message
    final userMsg = ChatMessage(role: MessageRole.user, content: text);
    ref.read(chatHistoryProvider.notifier).addMessage(userMsg);

    // Add placeholder assistant message
    final assistantMsg =
        ChatMessage(role: MessageRole.assistant, content: '');
    ref.read(chatHistoryProvider.notifier).addMessage(assistantMsg);
    ref.read(isStreamingProvider.notifier).state = true;

    _scrollToBottom();

    try {
      final history = ref.read(chatHistoryProvider)
          .where((m) => m.role != MessageRole.system)
          .toList()
        ..removeLast(); // Remove empty assistant placeholder

      await for (final delta in apiService.sendMessageStream(history)) {
        ref.read(chatHistoryProvider.notifier).appendToLastMessage(delta);
        _scrollToBottom();
      }
    } catch (e) {
      ref.read(chatHistoryProvider.notifier).updateLastAssistantMessage(
            '❌ Error: ${e.toString().replaceAll('APIException: ', '')}',
          );
    } finally {
      ref.read(isStreamingProvider.notifier).state = false;
      _scrollToBottom();
    }
  }

  void _showNoApiKeyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API Key Missing'),
        content: const Text(
            'Please configure your API key in Settings before chatting.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(ctx, '/settings');
            },
            child: const Text('Go to Settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatHistoryProvider);
    final isStreaming = ref.watch(isStreamingProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.terminal,
                  size: 18, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Terminal',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                Consumer(builder: (ctx, ref, _) {
                  final settings = ref.watch(settingsProvider);
                  return Text(
                    settings.selectedModel,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
        actions: [
          if (isStreaming)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear chat',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear Chat'),
                  content: const Text('Delete all messages?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                      onPressed: () {
                        ref.read(chatHistoryProvider.notifier).clear();
                        Navigator.pop(ctx);
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(colorScheme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (ctx, i) => _MessageBubble(
                      message: messages[i],
                      isDark: isDark,
                    ),
                  ),
          ),

          // Input Area
          _buildInputArea(colorScheme, isStreaming),
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
              size: 64, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('AI Terminal Controller',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Ask me to run commands, manage files,\nor automate tasks in Termux.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _SuggestionChip(
                text: '📋 List files',
                onTap: () {
                  _controller.text = 'Show me how to list all files in Termux home directory';
                  setState(() => _isComposing = true);
                },
              ),
              _SuggestionChip(
                text: '🐍 Run Python',
                onTap: () {
                  _controller.text = 'How do I run a Python script in Termux?';
                  setState(() => _isComposing = true);
                },
              ),
              _SuggestionChip(
                text: '📦 Install pkg',
                onTap: () {
                  _controller.text = 'How to install git using Termux package manager?';
                  setState(() => _isComposing = true);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ColorScheme colorScheme, bool isStreaming) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: 5,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: GoogleFonts.jetBrainsMono(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ask about commands, files, scripts...',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onChanged: (v) =>
                    setState(() => _isComposing = v.trim().isNotEmpty),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isStreaming
                  ? IconButton(
                      key: const ValueKey('stop'),
                      icon: const Icon(Icons.stop_circle_outlined),
                      onPressed: () => ref
                          .read(isStreamingProvider.notifier)
                          .state = false,
                      tooltip: 'Stop',
                    )
                  : FilledButton(
                      key: const ValueKey('send'),
                      onPressed: _isComposing ? _sendMessage : null,
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(12),
                      ),
                      child: const Icon(Icons.send_rounded, size: 20),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Message Bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends ConsumerWidget {
  final ChatMessage message;
  final bool isDark;

  const _MessageBubble({required this.message, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(Icons.smart_toy_outlined,
                  size: 14, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: isUser
                  ? Text(
                      message.content,
                      style: TextStyle(
                        color: colorScheme.onPrimary,
                        fontFamily: 'JetBrainsMono',
                        fontSize: 14,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MarkdownWithCode(
                          content: message.content,
                          isDark: isDark,
                          codeBlocks: message.codeBlocks,
                        ),
                      ],
                    ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.secondaryContainer,
              child: Icon(Icons.person_outline,
                  size: 14, color: colorScheme.onSecondaryContainer),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Markdown with Code Highlighting ──────────────────────────────────────────

class _MarkdownWithCode extends ConsumerWidget {
  final String content;
  final bool isDark;
  final List<CodeBlock> codeBlocks;

  const _MarkdownWithCode({
    required this.content,
    required this.isDark,
    required this.codeBlocks,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return MarkdownBody(
      data: content,
      selectable: true,
      builders: {
        'code': _CodeBlockBuilder(isDark: isDark, ref: ref),
      },
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 14,
          height: 1.5,
        ),
        code: GoogleFonts.jetBrainsMono(
          backgroundColor: colorScheme.surfaceContainerHighest,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final WidgetRef ref;

  _CodeBlockBuilder({required this.isDark, required this.ref});

  @override
  Widget? visitElementAfter(element, preferredStyle) {
    final code = element.textContent;
    final lang = element.attributes['class']
            ?.replaceFirst('language-', '') ??
        'text';
    final isBash = lang == 'bash' || lang == 'sh';

    return _CodeCard(code: code, language: lang, isDark: isDark, isBash: isBash);
  }
}

class _CodeCard extends ConsumerWidget {
  final String code;
  final String language;
  final bool isDark;
  final bool isBash;

  const _CodeCard({
    required this.code,
    required this.language,
    required this.isDark,
    required this.isBash,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Code header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E1E1E)
                  : colorScheme.surfaceContainerHighest,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(Icons.code, size: 14, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  language.isEmpty ? 'code' : language,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                // Copy button
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.copy, size: 14,
                        color: colorScheme.onSurfaceVariant),
                  ),
                ),
                // Run in Termux button
                if (isBash) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _runInTermux(context, ref),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow,
                              size: 12, color: Colors.green),
                          const SizedBox(width: 3),
                          Text('Termux',
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10, color: Colors.green)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Code content
          HighlightView(
            code,
            language: language.isEmpty ? 'plaintext' : language,
            theme: isDark ? atomOneDarkTheme : githubTheme,
            padding: const EdgeInsets.all(12),
            textStyle: GoogleFonts.jetBrainsMono(fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Future<void> _runInTermux(BuildContext context, WidgetRef ref) async {
    final fileManager = ref.read(fileManagerProvider);
    final workspace = ref.read(workspacePathProvider);

    try {
      await fileManager.runInTermux(code, workingDir: workspace);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Termux error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ─── Suggestion Chip ──────────────────────────────────────────────────────────

class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _SuggestionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 13)),
      onPressed: onTap,
    );
  }
}
