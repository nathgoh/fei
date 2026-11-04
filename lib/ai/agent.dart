import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/dates.dart';
import 'finance_tools.dart';

const agentInstructions = '''
You are a personal financial analysis assistant. Your job is to help users understand their income, expenses, savings, and spending habits by using the tools provided.

Each question starts with context: today's date, the years that have data, and the valid expense categories. Use it. Never ask for or look up the date.

Rules:
- ALWAYS use the available tools to retrieve data. Never fabricate numbers.
- "This year", "this month", and "last month" are relative to today's date.
- Tool arguments: year is a number like 2024. month is a month name or 1-12, never a date like "2024-10". Leave month out to cover the whole year.
- Format all currency values with a \$ sign and two decimal places (e.g. \$1,234.56).
- "Fixed" expenses are categories like rent that the user excludes from flexible spending.

Workflow hints:
- For income, expenses, savings, or a month's overview, use get_financial_summary.
- For comparisons between months, use compare_months.
- For trend or average monthly spending questions, use get_spending_trend.
- For "top expenses" or "biggest purchases", use get_top_expenses.
- For recurring/subscription questions, use get_recurring_expenses.

Keep your answers concise and actionable. Highlight key insights when relevant. Answer in Markdown.
''';

class ChatMessage {
  ChatMessage(this.role, this.content);
  final String role; // 'user' | 'assistant'
  final String content;
}

class AgentException implements Exception {
  AgentException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Normalises a user-entered endpoint (`http://host:11434`, `…/v1`, `…/v1/`)
/// to the OpenAI-compatible base URL.
Uri openAiBase(String endpoint) {
  var e = endpoint.trim();
  while (e.endsWith('/')) {
    e = e.substring(0, e.length - 1);
  }
  if (!e.startsWith('http://') && !e.startsWith('https://')) e = 'http://$e';
  if (!e.endsWith('/v1')) e = '$e/v1';
  return Uri.parse(e);
}

Uri _join(Uri base, String path) => base.replace(path: '${base.path}/$path');

/// Lists models the server exposes (OpenAI-compatible `/v1/models`).
Future<List<String>> fetchModels(String endpoint, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c.get(_join(openAiBase(endpoint), 'models')).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw AgentException('Server returned ${res.statusCode}');
    final data = (jsonDecode(res.body) as Map)['data'] as List;
    return data.map((m) => (m as Map)['id'].toString()).toList()..sort();
  } finally {
    if (client == null) c.close();
  }
}

/// A small tool-calling loop, equivalent to the web app's smolagents
/// `ToolCallingAgent`, talking to Ollama's OpenAI-compatible API.
class FinanceAgent {
  FinanceAgent({
    required this.endpoint,
    required this.model,
    required this.tools,
    http.Client? client,
    this.maxSteps = 6,
  }) : _client = client ?? http.Client();

  final String endpoint;
  final String model;
  final FinanceTools tools;
  final int maxSteps;
  final http.Client _client;

  Future<String> _context(String question) async {
    final now = DateTime.now();
    final years = (await tools.years()).join(', ');
    final categories = (await tools.expenseCategoryNames()).join(', ');
    return 'Today: ${ymd(now)} (${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][now.weekday - 1]})\n'
        'Years with data: ${years.isEmpty ? 'none' : years}\n'
        'Expense categories: ${categories.isEmpty ? 'none' : categories}\n\n'
        'Question: $question';
  }

  /// Answers [question], given the earlier turns of the conversation.
  /// [onStep] reports progress such as which tool is being called.
  Future<String> ask(List<ChatMessage> history, String question, {void Function(String status)? onStep}) async {
    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': agentInstructions},
      for (final m in history) {'role': m.role, 'content': m.content},
      {'role': 'user', 'content': await _context(question)},
    ];
    final toolSpecs = tools.tools.map((t) => t.toOpenAi()).toList();

    for (var step = 0; step <= maxSteps; step++) {
      final lastStep = step == maxSteps;
      final message = await _complete(messages, lastStep ? null : toolSpecs);
      final calls = (message['tool_calls'] as List?) ?? const [];
      if (calls.isEmpty || lastStep) {
        final content = _stripThinking(message['content']?.toString() ?? '');
        if (content.isEmpty) throw AgentException('The model returned an empty answer.');
        return content;
      }
      messages.add({'role': 'assistant', 'content': message['content'] ?? '', 'tool_calls': calls});
      for (final call in calls.cast<Map>()) {
        final fn = call['function'] as Map;
        final name = fn['name'].toString();
        onStep?.call('Looking up ${name.replaceAll('_', ' ').replaceFirst('get ', '')}…');
        final rawArgs = fn['arguments'];
        Map<String, Object?> args;
        try {
          args = rawArgs is Map
              ? rawArgs.cast<String, Object?>()
              : (jsonDecode(rawArgs?.toString() ?? '{}') as Map).cast<String, Object?>();
        } catch (_) {
          args = {};
        }
        messages.add({
          'role': 'tool',
          'tool_call_id': call['id'] ?? name,
          'name': name,
          'content': await tools.call(name, args),
        });
      }
      onStep?.call('Thinking…');
    }
    throw AgentException('No answer after $maxSteps steps.');
  }

  Future<Map<String, Object?>> _complete(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>>? toolSpecs,
  ) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            _join(openAiBase(endpoint), 'chat/completions'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ollama'},
            body: jsonEncode({'model': model, 'messages': messages, 'temperature': 0.1, 'tools': ?toolSpecs}),
          )
          .timeout(const Duration(minutes: 3));
    } catch (e) {
      throw AgentException('Could not reach $endpoint ($e).');
    }
    if (res.statusCode != 200) {
      throw AgentException('Server returned ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    final choices = body['choices'] as List?;
    if (choices == null || choices.isEmpty) throw AgentException('The model returned no choices.');
    return ((choices.first as Map)['message'] as Map).cast<String, Object?>();
  }
}

String _stripThinking(String s) => s.replaceAll(RegExp(r'<think>[\s\S]*?</think>', multiLine: true), '').trim();
