import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../models/chat_message.dart';

// ─── SharedPreferences Provider ───────────────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('Override in main()'),
);

// ─── Theme ────────────────────────────────────────────────────────────────────

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(ref.read(sharedPreferencesProvider)),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SharedPreferences _prefs;
  static const _key = 'theme_mode';

  ThemeModeNotifier(this._prefs)
      : super(_modeFromString(_prefs.getString(_key)));

  static ThemeMode _modeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void setMode(ThemeMode mode) {
    state = mode;
    _prefs.setString(_key, mode.name);
  }

  void toggle() {
    setMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

// ─── Settings ─────────────────────────────────────────────────────────────────

class AppSettings {
  final String apiKey;
  final String selectedModel;
  final AIProvider provider;
  final double temperature;
  final int maxTokens;
  final bool streamResponses;
  final bool autoRunCommands;
  final String? systemPromptOverride;

  const AppSettings({
    this.apiKey = '',
    this.selectedModel = 'claude-sonnet-4-5',
    this.provider = AIProvider.anthropic,
    this.temperature = 0.7,
    this.maxTokens = 4096,
    this.streamResponses = true,
    this.autoRunCommands = false,
    this.systemPromptOverride,
  });

  AppSettings copyWith({
    String? apiKey,
    String? selectedModel,
    AIProvider? provider,
    double? temperature,
    int? maxTokens,
    bool? streamResponses,
    bool? autoRunCommands,
    String? systemPromptOverride,
  }) =>
      AppSettings(
        apiKey: apiKey ?? this.apiKey,
        selectedModel: selectedModel ?? this.selectedModel,
        provider: provider ?? this.provider,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        streamResponses: streamResponses ?? this.streamResponses,
        autoRunCommands: autoRunCommands ?? this.autoRunCommands,
        systemPromptOverride: systemPromptOverride ?? this.systemPromptOverride,
      );

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'selectedModel': selectedModel,
        'provider': provider.index,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'streamResponses': streamResponses,
        'autoRunCommands': autoRunCommands,
        'systemPromptOverride': systemPromptOverride,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        apiKey: json['apiKey'] ?? '',
        selectedModel: json['selectedModel'] ?? 'claude-sonnet-4-5',
        provider: AIProvider.values[json['provider'] ?? 1],
        temperature: (json['temperature'] ?? 0.7).toDouble(),
        maxTokens: json['maxTokens'] ?? 4096,
        streamResponses: json['streamResponses'] ?? true,
        autoRunCommands: json['autoRunCommands'] ?? false,
        systemPromptOverride: json['systemPromptOverride'],
      );
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(ref.read(sharedPreferencesProvider)),
);

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SharedPreferences _prefs;
  static const _key = 'app_settings';

  SettingsNotifier(this._prefs) : super(_load(_prefs));

  static AppSettings _load(SharedPreferences prefs) {
    final json = prefs.getString(_key);
    if (json == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(json));
    } catch (_) {
      return const AppSettings();
    }
  }

  void update(AppSettings settings) {
    state = settings;
    _prefs.setString(_key, jsonEncode(settings.toJson()));
  }

  void updateApiKey(String key) => update(state.copyWith(apiKey: key));
  void updateModel(String model) => update(state.copyWith(selectedModel: model));
  void updateProvider(AIProvider provider) {
    final models = provider.availableModels;
    update(state.copyWith(
      provider: provider,
      selectedModel: models.isNotEmpty ? models.first : '',
    ));
  }
}

// ─── Chat History ─────────────────────────────────────────────────────────────

final chatHistoryProvider =
    StateNotifierProvider<ChatHistoryNotifier, List<ChatMessage>>(
  (ref) => ChatHistoryNotifier(),
);

class ChatHistoryNotifier extends StateNotifier<List<ChatMessage>> {
  ChatHistoryNotifier() : super([]);

  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  void updateLastAssistantMessage(String content) {
    if (state.isEmpty) return;
    final last = state.last;
    if (last.role == MessageRole.assistant) {
      state = [
        ...state.sublist(0, state.length - 1),
        last.copyWith(content: content),
      ];
    }
  }

  void appendToLastMessage(String delta) {
    if (state.isEmpty) return;
    final last = state.last;
    if (last.role == MessageRole.assistant) {
      state = [
        ...state.sublist(0, state.length - 1),
        last.copyWith(content: last.content + delta),
      ];
    }
  }

  void clear() => state = [];

  void removeMessage(String id) {
    state = state.where((m) => m.id != id).toList();
  }
}

// ─── Streaming State ──────────────────────────────────────────────────────────

final isStreamingProvider = StateProvider<bool>((ref) => false);
