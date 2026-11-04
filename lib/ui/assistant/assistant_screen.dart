import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai/agent.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets.dart';

const _suggestions = [
  'How much did I spend last month?',
  'Compare this month with last month',
  'What were my biggest purchases this year?',
  'What subscriptions and recurring expenses do I have?',
  'How is my grocery spending trending this year?',
];

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final question = text ?? _input.text;
    if (question.trim().isEmpty) return;
    _input.clear();
    ref.read(chatProvider.notifier).send(question);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(assistantSettingsProvider);
    final chat = ref.watch(chatProvider);
    ref.listen(chatProvider, (_, _) => _scrollToEnd());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant'),
        actions: [
          if (settings.models.isNotEmpty)
            MenuAnchor(
              menuChildren: [
                for (final m in settings.models)
                  MenuItemButton(
                    leadingIcon: Icon(m == settings.model ? Icons.check : null),
                    onPressed: chat.isRunning ? null : () => ref.read(assistantSettingsProvider.notifier).setModel(m),
                    child: Text(m),
                  ),
              ],
              builder: (context, controller, _) => TextButton.icon(
                onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.smart_toy_outlined, size: 18),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(settings.model, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          IconButton(
            tooltip: 'New conversation',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: chat.isRunning || chat.messages.isEmpty ? null : () => ref.read(chatProvider.notifier).reset(),
          ),
          const SettingsButton(),
        ],
      ),
      body: !settings.isConfigured
          ? EmptyState(
              icon: Icons.auto_awesome_outlined,
              title: 'Connect your Ollama server',
              message: 'Ask questions about your finances using a model running on your home server.',
              action: FilledButton(onPressed: () => context.push('/settings/assistant'), child: const Text('Set up')),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  children: [
                    Expanded(
                      child: chat.messages.isEmpty && !chat.isRunning
                          ? _Suggestions(onTap: _send)
                          : ListView(
                              controller: _scroll,
                              padding: const EdgeInsets.all(16),
                              children: [
                                for (final m in chat.messages) _Bubble(message: m),
                                if (chat.isRunning) _PendingBubble(status: chat.pendingStatus!),
                                if (chat.error != null)
                                  Card(
                                    color: context.colors.errorContainer,
                                    child: ListTile(
                                      leading: Icon(Icons.error_outline, color: context.colors.onErrorContainer),
                                      title: Text(
                                        'Analysis failed',
                                        style: TextStyle(color: context.colors.onErrorContainer),
                                      ),
                                      subtitle: Text(
                                        chat.error!,
                                        style: TextStyle(color: context.colors.onErrorContainer),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                enabled: !chat.isRunning,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _send(),
                                decoration: const InputDecoration(hintText: 'Ask about your finances…'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              tooltip: 'Send',
                              onPressed: chat.isRunning ? null : _send,
                              icon: const Icon(Icons.arrow_upward),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onTap});
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.auto_awesome, size: 40, color: context.colors.primary),
        const SizedBox(height: 12),
        Text('Ask about your finances', style: context.text.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          'Answers are computed from your local data by tools the model calls.',
          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => onTap(s))],
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? context.colors.primaryContainer : context.colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: isUser
            ? SelectableText(message.content, style: TextStyle(color: context.colors.onPrimaryContainer))
            : MarkdownBody(data: message.content, selectable: true),
      ),
    );
  }
}

class _PendingBubble extends StatelessWidget {
  const _PendingBubble({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: context.colors.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(
              status,
              style: TextStyle(color: context.colors.onSurfaceVariant, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
