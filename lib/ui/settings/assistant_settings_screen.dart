import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/agent.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets.dart';

class AssistantSettingsScreen extends ConsumerStatefulWidget {
  const AssistantSettingsScreen({super.key});

  @override
  ConsumerState<AssistantSettingsScreen> createState() => _AssistantSettingsScreenState();
}

class _AssistantSettingsScreenState extends ConsumerState<AssistantSettingsScreen> {
  late final _endpoint = TextEditingController(text: ref.read(assistantSettingsProvider).endpoint);
  final _newModel = TextEditingController();
  bool _testing = false;

  @override
  void dispose() {
    _endpoint.dispose();
    _newModel.dispose();
    super.dispose();
  }

  Future<void> _saveEndpoint() => ref.read(assistantSettingsProvider.notifier).setEndpoint(_endpoint.text);

  Future<void> _fetchModels() async {
    await _saveEndpoint();
    setState(() => _testing = true);
    try {
      final models = await fetchModels(_endpoint.text);
      if (!mounted) return;
      if (models.isEmpty) {
        showMessage(context, 'Connected, but the server has no models');
        return;
      }
      final replace = await confirm(
        context,
        title: 'Connected — ${models.length} models found',
        message: '${models.join('\n')}\n\nReplace your model list with these?',
        confirmLabel: 'Use these',
        destructive: false,
      );
      if (replace) await ref.read(assistantSettingsProvider.notifier).setModels(models);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not connect: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(assistantSettingsProvider);
    final notifier = ref.read(assistantSettingsProvider.notifier);
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('AI assistant')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: 'Ollama server',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _endpoint,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Endpoint', hintText: 'http://192.168.68.52:11434'),
                      onSubmitted: (_) => _saveEndpoint(),
                      onTapOutside: (_) => _saveEndpoint(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The OpenAI-compatible API is used (/v1 is added automatically). '
                      'Your financial data is sent only to this server.'
                      '${kIsWeb ? '\n\nIn the browser, Ollama must allow this site: start it with OLLAMA_ORIGINS="*" '
                                '(or this page\'s origin).' : ''}',
                      style: muted,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: _testing ? null : _fetchModels,
                        icon: _testing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_tethering),
                        label: const Text('Test & fetch models'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Models',
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    RadioGroup<String>(
                      groupValue: settings.model,
                      onChanged: (m) => m == null ? null : notifier.setModel(m),
                      child: Column(
                        children: [
                          for (final m in settings.models)
                            ListTile(
                              leading: Radio<String>(value: m),
                              title: Text(m),
                              onTap: () => notifier.setModel(m),
                              trailing: IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => notifier.setModels([...settings.models]..remove(m)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newModel,
                              decoration: const InputDecoration(labelText: 'Add model', hintText: 'e.g. qwen3:8b'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Add',
                            icon: const Icon(Icons.add),
                            onPressed: () {
                              final m = _newModel.text.trim();
                              if (m.isEmpty || settings.models.contains(m)) return;
                              notifier.setModels([...settings.models, m]);
                              _newModel.clear();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
