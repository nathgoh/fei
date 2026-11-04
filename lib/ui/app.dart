import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'assistant/assistant_screen.dart';
import 'cashflow/cashflow_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'recurring/recurring_screen.dart';
import 'settings/accounts_screen.dart';
import 'settings/assistant_settings_screen.dart';
import 'settings/categories_screen.dart';
import 'settings/data_screen.dart';
import 'settings/settings_screen.dart';
import 'theme.dart';
import 'transactions/transactions_screen.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard),
  _Destination('Transactions', Icons.receipt_long_outlined, Icons.receipt_long),
  _Destination('Cash Flow', Icons.insights_outlined, Icons.insights),
  _Destination('Recurring', Icons.event_repeat_outlined, Icons.event_repeat),
  _Destination('Assistant', Icons.auto_awesome_outlined, Icons.auto_awesome),
];

GoRoute _page(String path, Widget child) => GoRoute(path: path, builder: (_, _) => child);

final router = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _Shell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [_page('/dashboard', const DashboardScreen())]),
        StatefulShellBranch(routes: [_page('/transactions', const TransactionsScreen())]),
        StatefulShellBranch(routes: [_page('/cashflow', const CashFlowScreen())]),
        StatefulShellBranch(routes: [_page('/recurring', const RecurringScreen())]),
        StatefulShellBranch(routes: [_page('/assistant', const AssistantScreen())]),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => const SettingsScreen(),
      routes: [
        _page('categories', const CategoriesScreen()),
        _page('accounts', const AccountsScreen()),
        _page('assistant', const AssistantSettingsScreen()),
        _page('data', const DataScreen()),
      ],
    ),
  ],
);

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    if (context.isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1200,
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: MediaQuery.sizeOf(context).width >= 1200 ? null : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'fei',
                  style: context.text.headlineSmall?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
        ],
      ),
    );
  }
}

class FeiApp extends StatelessWidget {
  const FeiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Fei',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
