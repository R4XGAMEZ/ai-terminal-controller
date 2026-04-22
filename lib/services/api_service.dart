import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../providers/app_providers.dart';

// ─── Supported AI Providers ───────────────────────────────────────────────────

enum AIProvider { openai, anthropic, gemini, groq, ollama }

extension AIProviderExt on AIProvider {
  String get label {
    switch (this) {
      case AIProvider.openai:
        return 'OpenAI';
      case AIProvider.anthropic:
        return 'Anthropic';
      case AIProvider.gemini:
        return 'Google Gemini';
      case AIProvider.groq:
        return 'Groq';
      case AIProvider.ollama:
        return 'Ollama (Local)';
    }
  }

  String get baseUrl {
    switch (this) {
      case AIProvider.openai:
        return 'https://api.openai.com/v1';
      case AIProvider.anthropic:
        return 'https://api.anthropic.com/v1';
      case AIProvider.gemini:
        return 'https://generativelanguage.googleapis.com/v1beta';
      case AIProvider.groq:
        return 'https://api.groq.com/openai/v1';
      case AIProvider.ollama:
        return 'http://localhost:11434/api';
    }
  }

  List<String> get availableModels {
    switch (this) {
      case AIProvider.openai:
        return ['gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo', 'gpt-3.5-turbo'];
      case AIProvider.anthropic:
        return [
          'claude-opus-4-5',
          'claude-sonnet-4-5',
          'claude-haiku-4-5',
          'claude-3-5-sonnet-20241022',
        ];
      case AIProvider.gemini:
        return [
          'gemini-1.5-pro',
          'gemini-1.5-flash',
          'gemini-2.0-flash-exp',
        ];
      case AIProvider.groq:
        return [
          'llama-3.3-70b-versatile',
          'llama-3.1-8b-instant',
          'mixtral-8x7b-32768',
        ];
      case AIProvider.ollama:
        return ['llama3', 'codellama', 'mistral', 'phi3'];
    }
  }
}

// ─── API Service ──────────────────────────────────────────────────────────────

class APIService {
  final Dio _dio;
  final String apiKey;
  final String model;
  final AIProvider provider;

  static const String _systemPrompt = '''
You are an AI Terminal Controller integrated with Termux on Android.
Your job:
- Help users manage files, run shell commands, and automate tasks via Termux.
- Always wrap shell commands inside triple backtick code blocks with "bash" language tag.
- Explain what each command does before suggesting it.
- Be security-conscious: warn about dangerous commands (rm -rf, sudo, etc.).
- Format responses clearly with markdown.
- When suggesting file paths, always use Termux-compatible paths (/data/data/com.termux/files/home/).
''';

  APIService({
    required this.apiKey,
    required this.model,
    required this.provider,
  }) : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 60),
            headers: _buildHeaders(provider, apiKey),
          ),
        );

  static Map<String, String> _buildHeaders(
      AIProvider provider, String apiKey) {
    switch (provider) {
      case AIProvider.anthropic:
        return {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        };
      case AIProvider.openai:
      case AIProvider.groq:
        return {
          'Authorization': 'Bearer $apiKey',
          'content-type': 'application/json',
        };
      case AIProvider.gemini:
        return {'content-type': 'application/json'};
      case AIProvider.ollama:
        return {'content-type': 'application/json'};
    }
  }

  // ── Streaming Chat Completion ────────────────────────────────────────────────

  Stream<String> sendMessageStream(List<ChatMessage> history) async* {
    try {
      switch (provider) {
        case AIProvider.openai:
        case AIProvider.groq:
          yield* _openAIStream(history);
          break;
        case AIProvider.anthropic:
          yield* _anthropicStream(history);
          break;
        case AIProvider.gemini:
          yield* _geminiStream(history);
          break;
        case AIProvider.ollama:
          yield* _ollamaStream(history);
          break;
      }
    } on DioException catch (e) {
      final msg = _parseDioError(e);
      throw APIException(msg);
    }
  }

  // ── OpenAI / Groq ─────────────────────────────────────────────────────────

  Stream<String> _openAIStream(List<ChatMessage> history) async* {
    final url = '${provider.baseUrl}/chat/completions';
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ...history.map((m) => {'role': m.role.name, 'content': m.content}),
    ];

    final response = await _dio.post<ResponseBody>(
      url,
      data: jsonEncode({
        'model': model,
        'messages': messages,
        'stream': true,
        'temperature': 0.7,
        'max_tokens': 4096,
      }),
      options: Options(responseType: ResponseType.stream),
    );

    final stream = response.data!.stream
        .transform(const Utf8Decoder())
        .transform(const LineSplitter());

    await for (final line in stream) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data);
          final delta = json['choices']?[0]?['delta']?['content'];
          if (delta != null && delta is String) yield delta;
        } catch (_) {}
      }
    }
  }

  // ── Anthropic ─────────────────────────────────────────────────────────────

  Stream<String> _anthropicStream(List<ChatMessage> history) async* {
    const url = 'https://api.anthropic.com/v1/messages';
    final messages =
        history.map((m) => {'role': m.role.name, 'content': m.content}).toList();

    final response = await _dio.post<ResponseBody>(
      url,
      data: jsonEncode({
        'model': model,
        'max_tokens': 4096,
        'system': _systemPrompt,
        'messages': messages,
        'stream': true,
      }),
      options: Options(responseType: ResponseType.stream),
    );

    final stream = response.data!.stream
        .transform(const Utf8Decoder())
        .transform(const LineSplitter());

    await for (final line in stream) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        try {
          final json = jsonDecode(data);
          if (json['type'] == 'content_block_delta') {
            final text = json['delta']?['text'];
            if (text != null && text is String) yield text;
          }
        } catch (_) {}
      }
    }
  }

  // ── Gemini ────────────────────────────────────────────────────────────────

  Stream<String> _geminiStream(List<ChatMessage> history) async* {
    final url =
        '${provider.baseUrl}/models/$model:streamGenerateContent?key=$apiKey';
    final contents = history
        .map((m) => {
              'role': m.role == MessageRole.user ? 'user' : 'model',
              'parts': [
                {'text': m.content}
              ]
            })
        .toList();

    final response = await _dio.post<ResponseBody>(
      url,
      data: jsonEncode({'contents': contents}),
      options: Options(responseType: ResponseType.stream),
    );

    String buffer = '';
    final stream =
        response.data!.stream.transform(const Utf8Decoder());

    await for (final chunk in stream) {
      buffer += chunk;
      try {
        final json = jsonDecode(buffer);
        final text =
            json['candidates']?[0]?['content']?['parts']?[0]?['text'];
        if (text is String) {
          yield text;
          buffer = '';
        }
      } catch (_) {}
    }
  }

  // ── Ollama (local) ────────────────────────────────────────────────────────

  Stream<String> _ollamaStream(List<ChatMessage> history) async* {
    const url = 'http://localhost:11434/api/chat';
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ...history.map((m) => {'role': m.role.name, 'content': m.content}),
    ];

    final response = await _dio.post<ResponseBody>(
      url,
      data: jsonEncode({'model': model, 'messages': messages, 'stream': true}),
      options: Options(responseType: ResponseType.stream),
    );

    final stream = response.data!.stream
        .transform(const Utf8Decoder())
        .transform(const LineSplitter());

    await for (final line in stream) {
      try {
        final json = jsonDecode(line);
        final content = json['message']?['content'];
        if (content is String) yield content;
      } catch (_) {}
    }
  }

  // ── Error Handling ────────────────────────────────────────────────────────

  String _parseDioError(DioException e) {
    if (e.response != null) {
      try {
        final body = e.response!.data;
        if (body is Map) {
          return body['error']?['message'] ??
              body['message'] ??
              'API Error ${e.response!.statusCode}';
        }
      } catch (_) {}
      return 'API Error: ${e.response!.statusCode}';
    }
    if (e.type == DioExceptionType.connectionTimeout) {
      return 'Connection timeout. Check your internet.';
    }
    return e.message ?? 'Unknown network error';
  }
}

class APIException implements Exception {
  final String message;
  const APIException(this.message);

  @override
  String toString() => 'APIException: $message';
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final apiServiceProvider = Provider<APIService?>((ref) {
  final settings = ref.watch(settingsProvider);
  if (settings.apiKey.isEmpty) return null;
  return APIService(
    apiKey: settings.apiKey,
    model: settings.selectedModel,
    provider: settings.provider,
  );
});
