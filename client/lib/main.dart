import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth.dart';
import 'screens/dashboard.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'screens/agents.dart';

void main() {
  HttpOverrides.global = _AllowSelfSigned();
  runApp(const App());
}

class _AllowSelfSigned extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => true; // dev only
    return client;
  }
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    const accent = Color(0xFFBB86FC);
    final theme = base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: const Color(0xFFFF00FF),
      ),
      scaffoldBackgroundColor: const Color(0xFF0F0F12),
      cardColor: const Color(0xFF16161B),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF16161B)),
    );
    return ChangeNotifierProvider(
      create: (_) => AuthService()..load(),
      child: MaterialApp(
        title: 'Server Monitor',
        debugShowCheckedModeBanner: false,
        theme: theme,
        initialRoute: '/',
        routes: {
          '/': (_) => const _Root(),
          '/agents': (_) => const AgentsScreen(),
        },
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) {
    return const _ServersPage();
  }
}

class _ServersPage extends StatefulWidget {
  const _ServersPage();
  @override
  State<_ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<_ServersPage> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Servers')),
      body: ListView.builder(
        itemCount: auth.profiles.length + 1,
        itemBuilder: (ctx, idx) {
          if (idx == auth.profiles.length) {
            return ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add server'),
              onTap: () async {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const _LoginPage()));
              },
            );
          }
          final p = auth.profiles[idx];
          return ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(p.name.isEmpty ? p.baseUrl : p.name),
            subtitle: Text(p.baseUrl),
            trailing: p.accessToken != null
                ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                : null,
            onTap: () async {
              await auth.setActive(idx);
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DashboardScreen(host: p.baseUrl),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const _LoginPage())),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _LoginPage extends StatefulWidget {
  const _LoginPage({super.key});
  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  final _host = TextEditingController(text: 'https://10.0.2.2:8888');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _clientKey = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _initFilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initFilled) {
      final auth = Provider.of<AuthService>(context);
      if (auth.baseUrl != null && _host.text.isEmpty) {
        _host.text = auth.baseUrl!;
      } else {
        // _prefillGateway();
      }
      if (auth.clientKey != null && _clientKey.text.isEmpty) {
        _clientKey.text = auth.clientKey!;
      }
      _initFilled = true;
    }
  }

  // Future<void> _prefillGateway() async {
  //   try {
  //     final gw = await NetworkInfo().getWifiGatewayIP();
  //     if (gw != null && gw.isNotEmpty && mounted) {
  //       setState(() {
  //         _host.text = 'https://$gw:8443';
  //       });
  //     }
  //   } catch (_) {}
  // }

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    _clientKey.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      await auth.saveBase(_host.text, clientKey: _clientKey.text);
      // store username with profile
      final i = auth.profiles.indexWhere((p) => p.baseUrl == _host.text);
      if (i >= 0) {
        auth.profiles[i].username = _user.text.trim();
      }
      final ok = await auth.login(username: _user.text, password: _pass.text);
      if (ok && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardScreen(host: _host.text)),
        );
      } else {
        _error = 'Login failed';
      }
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'Server URL'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clientKey,
              decoration: const InputDecoration(labelText: 'Client Key'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy ? null : _login,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}

class Dashboard extends StatelessWidget {
  final String host;
  const Dashboard({super.key, required this.host});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Salvator')),
      body: Center(child: Text('Connected to $host')),
    );
  }
}
