import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/app_providers.dart';
import '../services/api_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _apiKeyController;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _apiKeyController = TextEditingController(text: settings.apiKey);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: GoogleFonts.jetBrainsMono()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── AI Provider Section ──────────────────────────────────────────
          _SectionHeader(title: '🤖 AI Provider'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Provider', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AIProvider>(
                    value: settings.provider,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    items: AIProvider.values
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.label),
                            ))
                        .toList(),
                    onChanged: (p) {
                      if (p != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .updateProvider(p);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Model', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: settings.provider.availableModels
                            .contains(settings.selectedModel)
                        ? settings.selectedModel
                        : settings.provider.availableModels.first,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    items: settings.provider.availableModels
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m,
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (m) {
                      if (m != null) {
                        ref.read(settingsProvider.notifier).updateModel(m);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── API Key Section ──────────────────────────────────────────────
          _SectionHeader(title: '🔑 API Key'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    style: GoogleFonts.jetBrainsMono(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: settings.provider == AIProvider.anthropic
                          ? 'sk-ant-...'
                          : settings.provider == AIProvider.openai
                              ? 'sk-...'
                              : 'Enter API key',
                      hintStyle:
                          GoogleFonts.jetBrainsMono(fontSize: 13),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                    onChanged: (v) {
                      ref
                          .read(settingsProvider.notifier)
                          .updateApiKey(v.trim());
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        settings.apiKey.isNotEmpty
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_outlined,
                        size: 14,
                        color: settings.apiKey.isNotEmpty
                            ? Colors.green
                            : colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        settings.apiKey.isNotEmpty
                            ? 'API key configured'
                            : 'API key required to use chat',
                        style: TextStyle(
                          fontSize: 12,
                          color: settings.apiKey.isNotEmpty
                              ? Colors.green
                              : colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Appearance Section ───────────────────────────────────────────
          _SectionHeader(title: '🎨 Appearance'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('System Default'),
                  subtitle: const Text('Follows device theme'),
                  value: ThemeMode.system,
                  groupValue: themeMode,
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(themeModeProvider.notifier).setMode(v);
                    }
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light Mode'),
                  value: ThemeMode.light,
                  groupValue: themeMode,
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(themeModeProvider.notifier).setMode(v);
                    }
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark Mode'),
                  value: ThemeMode.dark,
                  groupValue: themeMode,
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(themeModeProvider.notifier).setMode(v);
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Danger Zone ──────────────────────────────────────────────────
          _SectionHeader(title: '⚠️ Danger Zone'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Clear All Data',
                  style: TextStyle(color: Colors.red)),
              subtitle: const Text('Remove API keys, settings, and chat history'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear All Data?'),
                    content: const Text(
                        'This will remove all settings including your API key. This cannot be undone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () {
                          ref
                              .read(settingsProvider.notifier)
                              .update(const AppSettings());
                          ref
                              .read(chatHistoryProvider.notifier)
                              .clear();
                          _apiKeyController.clear();
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('All data cleared'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'AI Terminal Controller v1.0.0',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
