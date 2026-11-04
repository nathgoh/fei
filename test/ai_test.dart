import 'dart:convert';

import 'package:fei/ai/agent.dart';
import 'package:fei/ai/finance_tools.dart';
import 'package:fei/data/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late FinanceTools tools;
  setUp(() async {
    db = memoryDb();
    tools = FinanceTools(db);
    await addTxn(db, category: 'Paycheck', cents: 400000, date: '2026-09-15', kind: TxKind.income);
    await addTxn(db, category: 'Paycheck', cents: 400000, date: '2026-10-15', kind: TxKind.income);
    await addTxn(db, category: 'Rent', cents: 180000, date: '2026-09-01');
    await addTxn(db, category: 'Rent', cents: 180000, date: '2026-10-01');
    await addTxn(db, category: 'Grocery', cents: 25000, date: '2026-09-04', merchant: 'Costco');
    await addTxn(db, category: 'Grocery', cents: 40000, date: '2026-10-08', merchant: 'Safeway');
  });
  tearDown(() => db.close());

  Future<Map<String, dynamic>> call(String name, Map<String, Object?> args) async =>
      jsonDecode(await tools.call(name, args)) as Map<String, dynamic>;

  test('resolveMonth accepts names, numbers and dates', () {
    expect(FinanceTools.resolveMonth('oct'), 10);
    expect(FinanceTools.resolveMonth('3'), 3);
    expect(FinanceTools.resolveMonth('2024-10'), 10);
    expect(() => FinanceTools.resolveMonth('13'), throwsA(isA<ToolError>()));
  });

  test('get_financial_summary', () async {
    final r = await call('get_financial_summary', {'year': 2026, 'month': 'October'});
    expect(r['period'], 'October 2026');
    expect(r['total_income'], 4000.0);
    expect(r['total_expenses'], 2200.0);
    expect(r['fixed_expenses'], 1800.0);
    expect(r['savings_rate'], 45.0);
    expect((r['expense_breakdown'] as Map).keys, ['Rent', 'Grocery']);
  });

  test('compare_months, spending trend, top expenses, category (fuzzy)', () async {
    final cmp = await call('compare_months', {'year': '2026', 'month_1': 'sep', 'month_2': '10'});
    expect(cmp['expenses'], {'September': 2050.0, 'October': 2200.0, 'delta': 150.0});

    final trend = await call('get_spending_trend', {'year': 2026, 'category': 'groceries'});
    expect(trend['category'], 'Grocery');
    expect((trend['months'] as List).last['mom_change_percent'], 60.0);

    final top = await call('get_top_expenses', {'year': 2026, 'limit': 1});
    expect((top['expenses'] as List).single['amount'], 1800.0);

    final unknown = await call('get_category_expenses', {'category': 'yachts'});
    expect(unknown['error'], contains('Unknown category'));
  });

  test('openAiBase normalises endpoints', () {
    expect(openAiBase('192.168.1.5:11434').toString(), 'http://192.168.1.5:11434/v1');
    expect(openAiBase('http://host:11434/').toString(), 'http://host:11434/v1');
    expect(openAiBase('http://host:11434/v1').toString(), 'http://host:11434/v1');
  });

  test('agent runs the tool loop and returns the final answer', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      requests.add(body);
      final message = requests.length == 1
          ? {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {'name': 'get_financial_summary', 'arguments': '{"year": 2026, "month": "10"}'},
                },
              ],
            }
          : {'role': 'assistant', 'content': '<think>hmm</think>You spent **\$2,200.00** in October.'};
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': message},
          ],
        }),
        200,
      );
    });
    final agent = FinanceAgent(endpoint: 'http://ollama:11434', model: 'test', tools: tools, client: client);
    final steps = <String>[];
    final answer = await agent.ask([], 'How much did I spend in October?', onStep: steps.add);

    expect(answer, 'You spent **\$2,200.00** in October.');
    expect(requests, hasLength(2));
    expect(requests.first['model'], 'test');
    expect((requests.first['tools'] as List), hasLength(tools.tools.length));
    final toolMessage = (requests[1]['messages'] as List).last as Map;
    expect(toolMessage['role'], 'tool');
    expect(jsonDecode(toolMessage['content'] as String)['total_expenses'], 2200.0);
    expect(steps.first, contains('financial summary'));
  });
}
