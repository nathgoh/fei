import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: context.text.labelMedium?.copyWith(color: context.colors.primary, letterSpacing: 1),
      ),
    );
    Widget tile(IconData icon, String title, String subtitle, String route) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            children: [
              header('Personalize'),
              tile(Icons.palette_outlined, 'Appearance', 'Accent colour and background', '/settings/appearance'),
              header('Organize'),
              tile(
                Icons.category_outlined,
                'Categories',
                'Groups, emoji, colours and fixed costs',
                '/settings/categories',
              ),
              tile(
                Icons.credit_card,
                'Accounts',
                'Optional "paid with" labels for cards and cash',
                '/settings/accounts',
              ),
              header('Assistant'),
              tile(Icons.auto_awesome_outlined, 'AI assistant', 'Ollama server and models', '/settings/assistant'),
              header('Data'),
              tile(
                Icons.import_export,
                'Import & export',
                'Web app JSON, CSV import/export, erase data',
                '/settings/data',
              ),
              const ListTile(
                enabled: false,
                leading: Icon(Icons.cloud_sync_outlined),
                title: Text('Sync with home server'),
                subtitle: Text('Coming soon. Data is stored on this device for now.'),
              ),
              header('About'),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Fei'),
                subtitle: Text('Personal finance tracker · v0.1.0'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
