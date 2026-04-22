import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _ollamaHostController;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _ollamaHostController = TextEditingController(text: settings.ollamaHost);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _ollamaHostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final providers = ['openai', 'anthropic', 'gemini', 'groq', 'ollama'];
    final models = providerModels[settings.selectedProvider] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: GoogleFonts.jetBrainsMono()),
        actions: [
          IconButton(
            icon: Icon(themeMode == ThemeMode.dark
                ? Icons.light_mode
                : Icons.dark_mode),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Provider Selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Provider',
                      style: GoogleFonts.jetBrainsMono(
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: settings.selectedProvider,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: providers
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.toUpperCase(),
                                  style: GoogleFonts.jetBrainsMono()),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .updateProvider(value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Model Selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Model',
                      style: GoogleFonts.jetBrainsMono(
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: models.contains(settings.selectedModel)
                        ? settings.selectedModel
                        : models.first,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: models
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m,
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 12)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .updateModel(value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // API Key
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('API Key',
                      style: GoogleFonts.jetBrainsMono(
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _apiKeyController,
                    obscureText: _obscureApiKey,
                    style: GoogleFonts.jetBrainsMono(fontSize: 13),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Enter your API key...',
                      suffixIcon: IconButton(
                        icon: Icon(_obscureApiKey
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureApiKey = !_obscureApiKey),
                      ),
                    ),
                    onChanged: (value) {
                      ref
                          .read(settingsProvider.notifier)
                          .updateApiKey(value);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Ollama Host (show only when ollama selected)
          if (settings.selectedProvider == 'ollama')
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ollama Host',
                        style: GoogleFonts.jetBrainsMono(
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ollamaHostController,
                      style: GoogleFonts.jetBrainsMono(fontSize: 13),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'http://localhost:11434',
                      ),
                      onChanged: (value) {
                        ref
                            .read(settingsProvider.notifier)
                            .updateOllamaHost(value);
                      },
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Clear Chat Button
          OutlinedButton.icon(
            onPressed: () {
              ref.read(chatMessagesProvider.notifier).clearMessages();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Chat cleared!')),
              );
            },
            icon: const Icon(Icons.delete_outline),
            label: Text('Clear Chat History',
                style: GoogleFonts.jetBrainsMono()),
          ),

          const SizedBox(height: 32),

          Center(
            child: Text(
              'AI Terminal Controller v1.0.0',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
