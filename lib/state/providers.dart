import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/agent.dart';
import '../ai/finance_tools.dart';
import '../core/dates.dart';
import '../data/database.dart';
import '../domain/analytics.dart';

/// Overridden in `main()` once the database is open.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());

/// Overridden in `main()` with the loaded preferences.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final groupsProvider = StreamProvider<List<CategoryGroup>>((ref) => ref.watch(databaseProvider).watchGroups());

final categoriesProvider = StreamProvider<List<Category>>((ref) => ref.watch(databaseProvider).watchCategories());

final categoryMapProvider = Provider<Map<String, Category>>((ref) {
  final list = ref.watch(categoriesProvider).value ?? const [];
  return {for (final c in list) c.id: c};
});

final accountsProvider = StreamProvider<List<Account>>((ref) => ref.watch(databaseProvider).watchAccounts());

final accountMapProvider = Provider<Map<String, Account>>((ref) {
  final list = ref.watch(accountsProvider).value ?? const [];
  return {for (final a in list) a.id: a};
});

final recurringProvider = StreamProvider<List<RecurringSeries>>((ref) => ref.watch(databaseProvider).watchRecurring());

/// Years that have transactions, newest first, always including this year.
final yearsProvider = StreamProvider<List<int>>((ref) {
  final current = DateTime.now().year;
  return ref.watch(databaseProvider).watchYears().map((years) => ({current, ...years}.toList()..sort((a, b) => b - a)));
});

/// Transactions in an inclusive `YYYY-MM-DD` range; null bounds are open.
final transactionsProvider = StreamProvider.family<List<Txn>, ({String? from, String? to})>(
  (ref, range) => ref.watch(databaseProvider).watchTransactions(from: range.from, to: range.to),
);

({String from, String to}) yearRange(int year) => (from: '$year-01-01', to: '$year-12-31');

({String from, String to}) monthRange(int year, int month) =>
    (from: '${monthKey(year, month)}-01', to: '${monthKey(year, month)}-${daysInMonth(year, month)}');

final yearSummaryProvider = Provider.family<AsyncValue<PeriodSummary>, int>((ref, year) {
  final categories = ref.watch(categoryMapProvider);
  return ref.watch(transactionsProvider(yearRange(year))).whenData((t) => summarize(t, categories));
});

// -----------------------------------------------------------------------------
// Assistant settings (device-local, not synced)
// -----------------------------------------------------------------------------

/// Defaults from the web app's `LLM_MODELS`.
const defaultModels = ['openbmb/minicpm5:latest', 'LiquidAI/lfm2.5-2.6b:latest', 'bonsai-2:2b', 'lfm3:latest'];

class AssistantSettings {
  const AssistantSettings({required this.endpoint, required this.models, required this.model});
  final String endpoint;
  final List<String> models;
  final String model;
  bool get isConfigured => endpoint.trim().isNotEmpty && model.isNotEmpty;
}

class AssistantSettingsNotifier extends Notifier<AssistantSettings> {
  static const _endpointKey = 'assistant.endpoint';
  static const _modelsKey = 'assistant.models';
  static const _modelKey = 'assistant.model';

  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  AssistantSettings build() {
    final prefs = ref.watch(prefsProvider);
    final models = prefs.getStringList(_modelsKey) ?? defaultModels;
    final model = prefs.getString(_modelKey);
    return AssistantSettings(
      endpoint: prefs.getString(_endpointKey) ?? '',
      models: models,
      model: model != null && models.contains(model) ? model : (models.isEmpty ? '' : models.first),
    );
  }

  Future<void> setEndpoint(String endpoint) async {
    await _prefs.setString(_endpointKey, endpoint.trim());
    state = AssistantSettings(endpoint: endpoint.trim(), models: state.models, model: state.model);
  }

  Future<void> setModels(List<String> models) async {
    await _prefs.setStringList(_modelsKey, models);
    final model = models.contains(state.model) ? state.model : (models.isEmpty ? '' : models.first);
    await _prefs.setString(_modelKey, model);
    state = AssistantSettings(endpoint: state.endpoint, models: models, model: model);
  }

  Future<void> setModel(String model) async {
    await _prefs.setString(_modelKey, model);
    state = AssistantSettings(endpoint: state.endpoint, models: state.models, model: model);
  }
}

final assistantSettingsProvider = NotifierProvider<AssistantSettingsNotifier, AssistantSettings>(
  AssistantSettingsNotifier.new,
);

// -----------------------------------------------------------------------------
// Assistant conversation (kept while the app runs, like the web app's session)
// -----------------------------------------------------------------------------

class ChatState {
  const ChatState({this.messages = const [], this.pendingStatus, this.error});
  final List<ChatMessage> messages;

  /// Non-null while the agent is working.
  final String? pendingStatus;
  final String? error;
  bool get isRunning => pendingStatus != null;
}

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() {
    // A new model means a new conversation, as in the web app.
    ref.watch(assistantSettingsProvider.select((s) => s.model));
    return const ChatState();
  }

  void reset() => state = const ChatState();

  Future<void> send(String question) async {
    final settings = ref.read(assistantSettingsProvider);
    if (state.isRunning || question.trim().isEmpty) return;
    final history = state.messages;
    state = ChatState(messages: [...history, ChatMessage('user', question.trim())], pendingStatus: 'Thinking…');
    final agent = FinanceAgent(
      endpoint: settings.endpoint,
      model: settings.model,
      tools: FinanceTools(ref.read(databaseProvider)),
    );
    try {
      final answer = await agent.ask(
        history,
        question.trim(),
        onStep: (s) {
          if (state.isRunning) state = ChatState(messages: state.messages, pendingStatus: s);
        },
      );
      state = ChatState(messages: [...state.messages, ChatMessage('assistant', answer)]);
    } catch (e) {
      state = ChatState(messages: state.messages, error: e.toString());
    }
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
