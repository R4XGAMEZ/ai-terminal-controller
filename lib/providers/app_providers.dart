import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

// ─── Shared Preferences ───────────────────────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences not initialized');
});

// ─── Theme ────────────────────────────────────────────────────────────────────

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeModeNotifier(prefs);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SharedPreferences _prefs;
  ThemeModeNotifier(this._prefs)
      : super(_prefs.getBool('dark_mode') == true
            ? ThemeMode.dark
            : ThemeMode.light);

  void toggle() {
    final isDark = state == ThemeMode.dark;
    state = isDark ? ThemeMode.light : ThemeMode.dark;
    _prefs.setBool('dark_mode', !isDark);
  }
}

// ─── Settings ─────────────────────────────────────────────────────────────────

class AppSettings {
  final String apiKey;
  final String selectedProvider;
  final String selectedModel;
  final String ollamaHost;

  const AppSettings({
    this.apiKey = '',
    this.selectedProvider = 'anthropic',
    this.selectedModel = 'claude-sonnet-4-20250514',
    this.ollamaHost = 'http://localhost:11434',
  });

  AppSettings copyWith({
    String? apiKey,
    String? selectedProvider,
    String? selectedModel,
    String? ollamaHost,
  }) {
    return AppSettings(
      apiKey: apiKey ?? this.apiKey,
      selectedProvider: selectedProvider ?? this.selectedProvider,
      selectedModel: selectedModel ?? this.selectedModel,
      ollamaHost: ollamaHost ?? this.ollamaHost,
    );
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsNotifier(prefs);
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SharedPreferences _prefs;

  SettingsNotifier(this._prefs)
      : super(AppSettings(
          apiKey: _prefs.getString('api_key') ?? '',
          selectedProvider: _prefs.getString('provider') ?? 'anthropic',
          selectedModel:
              _prefs.getString('model') ?? 'claude-sonnet-4-20250514',
          ollamaHost:
              _prefs.getString('ollama_host') ?? 'http://localhost:11434',
        ));

  Future<void> updateApiKey(String key) async {
    state = state.copyWith(apiKey: key);
    await _prefs.setString('api_key', key);
  }

  Future<void> updateProvider(String provider) async {
    final defaultModel = _defaultModelForProvider(provider);
    state = state.copyWith(selectedProvider: provider, selectedModel: defaultModel);
    await _prefs.setString('provider', provider);
    await _prefs.setString('model', defaultModel);
  }

  Future<void> updateModel(String model) async {
    state = state.copyWith(selectedModel: model);
    await _prefs.setString('model', model);
  }

  Future<void> updateOllamaHost(String host) async {
    state = state.copyWith(ollamaHost: host);
    await _prefs.setString('ollama_host', host);
  }

  String _defaultModelForProvider(String provider) {
    switch (provider) {
      case 'openai': return 'gpt-4o';
      case 'anthropic': return 'claude-sonnet-4-20250514';
      case 'gemini': return 'gemini-1.5-pro';
      case 'groq': return 'llama-3.3-70b-versatile';
      case 'ollama': return 'llama3';
      default: return 'claude-sonnet-4-20250514';
    }
  }
}

// ─── Provider Models Map ──────────────────────────────────────────────────────

const providerModels = <String, List<String>>{
  'openai': ['gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo', 'gpt-3.5-turbo'],
  'anthropic': [
    'claude-opus-4-20250514',
    'claude-sonnet-4-20250514',
    'claude-haiku-4-20250514',
    'claude-3-5-sonnet-20241022',
    'claude-3-haiku-20240307',
  ],
  'gemini': ['gemini-1.5-pro', 'gemini-1.5-flash', 'gemini-2.0-flash'],
  'groq': [
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'mixtral-8x7b-32768',
    'gemma2-9b-it',
  ],
  'ollama': ['llama3', 'mistral', 'codellama', 'phi3', 'gemma2'],
};

// ─── Chat Messages ────────────────────────────────────────────────────────────

final chatMessagesProvider =
    StateNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>((ref) {
  return ChatMessagesNotifier();
});

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  ChatMessagesNotifier() : super([]);

  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  void updateMessage(String id, ChatMessage updated) {
    state = state.map((m) => m.id == id ? updated : m).toList();
  }

  void appendToMessage(String id, String chunk) {
    state = state.map((m) {
      if (m.id == id) return m.copyWith(content: m.content + chunk);
      return m;
    }).toList();
  }

  void clearMessages() {
    state = [];
  }
}

// ─── Workspace ────────────────────────────────────────────────────────────────

final workspacePathProvider =
    StateNotifierProvider<WorkspacePathNotifier, String?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return WorkspacePathNotifier(prefs);
});

class WorkspacePathNotifier extends StateNotifier<String?> {
  final SharedPreferences _prefs;

  WorkspacePathNotifier(this._prefs)
      : super(_prefs.getString('workspace_path'));

  Future<void> setPath(String path) async {
    state = path;
    await _prefs.setString('workspace_path', path);
  }

  void clearPath() {
    state = null;
    _prefs.remove('workspace_path');
  }
}

// ─── Streaming State ──────────────────────────────────────────────────────────

final isStreamingProvider = StateProvider<bool>((ref) => false);
