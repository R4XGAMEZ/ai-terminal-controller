import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../providers/app_providers.dart';

enum AIProvider { openai, anthropic, gemini, groq, ollama }

extension AIProviderExt on AIProvider {
  String get label {
    switch (this) {
      case AIProvider.openai: return 'OpenAI';
      case AIProvider.anthropic: return 'Anthropic';
      case AIProvider.gemini: return 'Gemini';
      case AIProvider.groq: return 'Groq';
      case AIProvider.ollama: return 'Ollama';
    }
  }

  String get baseUrl {
    switch (this) {
      case AIProvider.openai: return 'https://api.openai.com/v1';
      case AIProvider.anthropic: return 'https://api.anthropic.com/v1';
      case AIProvider.gemini: return 'https://generativelanguage.googleapis.com/v1beta';
      case AIProvider.groq: return 'https://api.groq.com/openai/v1';
      case AIProvider.ollama: return 'http://localhost:11434/api';
    }
  }
}

class ApiService {
  final Dio _dio;
  final AppSettings _settings;

  ApiService(this._settings)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
          headers: {'Content-Type': 'application/json'},
        ));

  AIProvider get _provider {
    switch (_settings.selectedProvider) {
      case 'openai': return AIProvider.openai;
      case 'anthropic': return AIProvider.anthropic;
      case 'gemini': return AIProvider.gemini;
      case 'groq': return AIProvider.groq;
      case 'ollama': return AIProvider.ollama;
      default: return AIProvider.anthropic;
    }
  }

  Stream<String> sendMessageStream(List<ChatMessage> messages) {
    switch (_provider) {
      case AIProvider.openai:
      case AIProvider.groq:
        return _streamOpenAI(messages);
      case AIProvider.anthropic:
        return _streamAnthropic(messages);
      case AIProvider.gemini:
        return _streamGemini(messages);
      case AIProvider.ollama:
        return _streamOllama(messages);
    }
  }

  Stream<String> _streamOpenAI(List<ChatMessage> messages) async* {
    try {
      final response = await _dio.post(
        '${_provider.baseUrl}/chat/completions',
        options: Options(
          headers: {'Authorization': 'Bearer ${_settings.apiKey}'},
          responseType: ResponseType.stream,
        ),
        data: {
          'model': _settings.selectedModel,
          'messages': messages.map((m) => m.toApiMap()).toList(),
          'stream': true,
          'max_tokens': 4096,
        },
      );
      final stream = response.data.stream as Stream<List<int>>;
      await for (final line in stream
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data);
            final content = json['choices']?[0]?['delta']?['content'] as String?;
            if (content != null) yield content;
          } catch (_) {}
        }
      }
    } catch (e) {
      throw Exception('OpenAI/Groq API error: $e');
    }
  }

  Stream<String> _streamAnthropic(List<ChatMessage> messages) async* {
    try {
      final response = await _dio.post(
        '${AIProvider.anthropic.baseUrl}/messages',
        options: Options(
          headers: {
            'x-api-key': _settings.apiKey,
            'anthropic-version': '2023-06-01',
          },
          responseType: ResponseType.stream,
        ),
        data: {
          'model': _settings.selectedModel,
          'max_tokens': 4096,
          'stream': true,
          'messages': messages.map((m) => m.toApiMap()).toList(),
        },
      );
      final stream = response.data.stream as Stream<List<int>>;
      await for (final line in stream
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          try {
            final json = jsonDecode(data);
            if (json['type'] == 'content_block_delta') {
              final text = json['delta']?['text'] as String?;
              if (text != null) yield text;
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      throw Exception('Anthropic API error: $e');
    }
  }

  Stream<String> _streamGemini(List<ChatMessage> messages) async* {
    try {
      final prompt = messages.map((m) {
        final role = m.role == MessageRole.user ? 'user' : 'model';
        return {
          'role': role,
          'parts': [{'text': m.content}]
        };
      }).toList();

      final response = await _dio.post(
        '${AIProvider.gemini.baseUrl}/models/${_settings.selectedModel}:streamGenerateContent?key=${_settings.apiKey}',
        options: Options(responseType: ResponseType.stream),
        data: {'contents': prompt},
      );

      final stream = response.data.stream as Stream<List<int>>;
      final buffer = StringBuffer();
      await for (final chunk in stream.transform(const Utf8Decoder())) {
        buffer.write(chunk);
        try {
          final json = jsonDecode(buffer.toString());
          final text = json['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
          if (text != null) {
            yield text;
            buffer.clear();
          }
        } catch (_) {}
      }
    } catch (e) {
      throw Exception('Gemini API error: $e');
    }
  }

  Stream<String> _streamOllama(List<ChatMessage> messages) async* {
    try {
      final response = await _dio.post(
        '${_settings.ollamaHost}/api/chat',
        options: Options(responseType: ResponseType.stream),
        data: {
          'model': _settings.selectedModel,
          'messages': messages.map((m) => m.toApiMap()).toList(),
          'stream': true,
        },
      );
      final stream = response.data.stream as Stream<List<int>>;
      await for (final line in stream
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line);
          final text = json['message']?['content'] as String?;
          if (text != null) yield text;
          if (json['done'] == true) break;
        } catch (_) {}
      }
    } catch (e) {
      throw Exception('Ollama API error: $e');
    }
  }
}

final apiServiceProvider = Provider<ApiService>((ref) {
  final settings = ref.watch(settingsProvider);
  return ApiService(settings);
});
