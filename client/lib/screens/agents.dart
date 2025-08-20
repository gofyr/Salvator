import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth.dart';

class AgentsScreen extends StatelessWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final profiles = auth.profiles;
    final active = auth.active;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add server',
            onPressed: () => _showAddOrEdit(context),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: profiles.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final p = profiles[i];
          final isActive = active?.id == p.id;
          return ListTile(
            leading: Icon(
              isActive
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(p.name.isEmpty ? p.baseUrl : p.name),
            subtitle: Text(p.baseUrl),
            onTap: () async {
              await auth.setActive(i);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showAddOrEdit(context, index: i),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await _confirmDelete(context, i);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, int index) async {
    final auth = context.read<AuthService>();
    final p = auth.profiles[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove server'),
        content: Text('Remove ${p.name.isEmpty ? p.baseUrl : p.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await auth.deleteProfile(index);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _showAddOrEdit(BuildContext context, {int? index}) async {
    final auth = context.read<AuthService>();
    final editing = index != null ? auth.profiles[index] : null;
    final name = TextEditingController(text: editing?.name ?? '');
    final url = TextEditingController(text: editing?.baseUrl ?? 'https://');
    final uname = TextEditingController(text: editing?.username ?? '');
    final key = TextEditingController(text: editing?.clientKey ?? '');
    final pass = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editing == null ? 'Add server' : 'Edit server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: url,
              decoration: const InputDecoration(labelText: 'Base URL'),
            ),
            TextField(
              controller: uname,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            if (editing == null)
              TextField(
                controller: pass,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
            TextField(
              controller: key,
              decoration: const InputDecoration(labelText: 'Client Key'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (editing == null) {
                // Create profile
                await auth.saveBase(
                  url.text.trim(),
                  clientKey: key.text.trim(),
                );
                // Update name and username
                final i = auth.profiles.indexWhere(
                  (p) => p.baseUrl == url.text.trim(),
                );
                if (i >= 0) {
                  final p = auth.profiles[i];
                  p.name = name.text.trim().isEmpty
                      ? p.baseUrl
                      : name.text.trim();
                  p.username = uname.text.trim();
                  await auth.setActive(i);
                  // Attempt initial login if username/password provided
                  final u = uname.text.trim();
                  final pw = pass.text;
                  if (u.isNotEmpty && pw.isNotEmpty) {
                    await auth.login(username: u, password: pw);
                  }
                }
              } else {
                editing.name = name.text.trim();
                editing.baseUrl = url.text.trim();
                editing.username = uname.text.trim();
                editing.clientKey = key.text.trim();
                await auth.setActive(index!);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
