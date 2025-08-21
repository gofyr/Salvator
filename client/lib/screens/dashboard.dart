import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth.dart';
import '../services/sse.dart';

class DashboardScreen extends StatefulWidget {
  final String host;
  const DashboardScreen({super.key, required this.host});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription? _sub;
  late String _currentHost;
  final List<FlSpot> _cpu = [];
  final List<FlSpot> _mem = [];
  final List<FlSpot> _netIn = [];
  final List<FlSpot> _netOut = [];
  final List<FlSpot> _diskR = [];
  final List<FlSpot> _diskW = [];
  int _t = 0;
  double _intervalSec = 2.0; // server streams every 2s
  num? _lastNetIn;
  num? _lastNetOut;
  num? _lastDiskR;
  num? _lastDiskW;
  List<_LoginEntry> _logins = [];
  List<_ContainerEntry> _containers = [];
  bool _loadingLists = false;
  Timer? _reconnectTimer;
  bool _waitingForMetrics = true;
  Timer? _metricsWaitTimer;

  @override
  void initState() {
    super.initState();
    _currentHost = widget.host;
    _waitingForMetrics = true;
    _metricsWaitTimer?.cancel();
    _metricsWaitTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_waitingForMetrics) {
        setState(() {
          _waitingForMetrics = false;
        });
      }
    });
    _loadInitialMetrics();
    _startSse();
    _loadLists();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      _switchServer(widget.host);
    }
  }

  void _startSse() {
    final auth = context.read<AuthService>();
    final sse = SseClient(
      url: '$_currentHost/api/metrics/stream',
      httpClientFactory: () => auth.newHttpClient(),
      accessToken: auth.accessToken,
      clientKey: auth.clientKey,
    );
    _sub?.cancel();
    _sub = sse.connect().listen(
      (map) {
        _addMetricsPointFromMap(map);
      },
      onError: (e, st) async {
        // Attempt token refresh on auth errors, then schedule reconnect
        try {
          final msg = e.toString();
          if (msg.contains('401')) {
            await auth.refresh();
          }
        } catch (_) {}
        _scheduleReconnect();
      },
      onDone: () {
        _scheduleReconnect();
      },
    );
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _metricsWaitTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salvator'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Servers',
            icon: const Icon(Icons.storage),
            onPressed: () async {
              await Navigator.of(context).pushNamed('/agents');
              _checkActiveHost();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _multiChartCard(
                title: 'CPU & Memory %',
                labels: const ['CPU', 'Memory'],
                series: [_cpu, _mem],
                colors: const [Colors.purpleAccent, Colors.pinkAccent],
                fixedMaxY: 100,
              ),
              const SizedBox(height: 16),
              _multiChartCard(
                title: 'Network (KiB/s)',
                labels: const ['In', 'Out'],
                series: [_netIn, _netOut],
                colors: const [Colors.lightBlueAccent, Colors.tealAccent],
              ),
              const SizedBox(height: 16),
              _multiChartCard(
                title: 'Disk (KiB/s)',
                labels: const ['Read', 'Write'],
                series: [_diskR, _diskW],
                colors: const [Colors.amberAccent, Colors.orangeAccent],
              ),
              const SizedBox(height: 16),
              _containersCard(),
              const SizedBox(height: 16),
              _loginsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _multiChartCard({
    required String title,
    required List<String> labels,
    required List<List<FlSpot>> series,
    required List<Color> colors,
    double? fixedMaxY,
  }) {
    final hasData = series.any((s) => s.isNotEmpty);
    final maxY = fixedMaxY ?? _computeDynamicMaxY(series);
    return Card(
      child: SizedBox(
        height: 200,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: -8,
                children: [
                  for (int i = 0; i < labels.length && i < colors.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colors[i],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(labels[i], style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Stack(
                  children: [
                    if (!hasData)
                      const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            for (
                              int i = 0;
                              i < series.length && i < colors.length;
                              i++
                            )
                              LineChartBarData(
                                spots: series[i],
                                color: colors[i],
                                dotData: const FlDotData(show: false),
                                isCurved: true,
                                barWidth: 2,
                              ),
                          ],
                          minY: 0,
                          maxY: maxY,
                        ),
                      ),
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (title.startsWith('CPU')) {
                              Navigator.of(context).pushNamed('/cpu');
                            } else if (title.startsWith('Network')) {
                              Navigator.of(context).pushNamed('/network');
                            } else if (title.startsWith('Disk')) {
                              Navigator.of(context).pushNamed('/disk');
                            }
                          },
                        ),
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

  double _computeDynamicMaxY(List<List<FlSpot>> series) {
    double m = 1;
    for (final s in series) {
      for (final p in s) {
        if (p.y > m) m = p.y;
      }
    }
    // Add 20% headroom, minimum 1
    final padded = m * 1.2;
    return padded < 1 ? 1 : padded;
  }

  Future<void> _loadLists() async {
    setState(() {
      _loadingLists = true;
    });
    try {
      final auth = context.read<AuthService>();
      final dio = auth.createDio();
      final loginsResp = await dio.get('/api/logins');
      final contResp = await dio.get('/api/containers');
      final logins = <_LoginEntry>[];
      if (loginsResp.statusCode == 200 && loginsResp.data is List) {
        for (final m in (loginsResp.data as List)) {
          if (m is Map<String, dynamic>) {
            logins.add(
              _LoginEntry(
                user: (m['user'] ?? '').toString(),
                tty: (m['tty'] ?? '').toString(),
                host: (m['host'] ?? '').toString(),
                since: (m['since'] ?? '').toString(),
              ),
            );
          }
        }
      }
      final containers = <_ContainerEntry>[];
      if (contResp.statusCode == 200 && contResp.data is List) {
        for (final m in (contResp.data as List)) {
          if (m is Map<String, dynamic>) {
            containers.add(
              _ContainerEntry(
                id: (m['id'] ?? '').toString(),
                image: (m['image'] ?? '').toString(),
                name: (m['name'] ?? '').toString(),
                state: (m['state'] ?? '').toString(),
              ),
            );
          }
        }
      }
      setState(() {
        _logins = logins;
        _containers = containers;
      });
    } catch (_) {
      // ignore errors; UI will show empty lists
    } finally {
      if (mounted)
        setState(() {
          _loadingLists = false;
        });
    }
  }

  Future<void> _refreshAll() async {
    _resetCharts();
    setState(() {
      _waitingForMetrics = true;
    });
    _metricsWaitTimer?.cancel();
    _metricsWaitTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_waitingForMetrics) {
        setState(() {
          _waitingForMetrics = false;
        });
      }
    });
    // Ensure spinner persists until data arrives; wait for initial metrics then SSE will continue
    await _loadInitialMetrics();
    await _loadLists();
  }

  void _resetCharts() {
    setState(() {
      _cpu.clear();
      _mem.clear();
      _netIn.clear();
      _netOut.clear();
      _diskR.clear();
      _diskW.clear();
      _t = 0;
      _lastNetIn = null;
      _lastNetOut = null;
      _lastDiskR = null;
      _lastDiskW = null;
    });
  }

  Future<void> _switchServer(String newHost) async {
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    setState(() {
      _currentHost = newHost;
    });
    _resetCharts();
    setState(() {
      _waitingForMetrics = true;
    });
    _metricsWaitTimer?.cancel();
    _metricsWaitTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_waitingForMetrics) {
        setState(() {
          _waitingForMetrics = false;
        });
      }
    });
    await _loadInitialMetrics();
    _startSse();
    await _loadLists();
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _startSse();
    });
  }

  Future<void> _loadInitialMetrics() async {
    try {
      final auth = context.read<AuthService>();
      final dio = auth.createDio();
      final resp = await dio.get('/api/metrics');
      if (resp.statusCode == 200 && resp.data is Map<String, dynamic>) {
        final map = resp.data as Map<String, dynamic>;
        setState(() {
          final cpu = (map['cpu_percent'] as num?)?.toDouble() ?? 0;
          final memUsed = (map['memory_used'] as num?)?.toDouble() ?? 0;
          final memTotal = (map['memory_total'] as num?)?.toDouble() ?? 1;
          final memPct = (memUsed / memTotal) * 100.0;
          _lastNetIn = (map['net_bytes_in'] as num?) ?? 0;
          _lastNetOut = (map['net_bytes_out'] as num?) ?? 0;
          _lastDiskR = (map['disk_read_bytes'] as num?) ?? 0;
          _lastDiskW = (map['disk_write_bytes'] as num?) ?? 0;
          _cpu.add(FlSpot(_t.toDouble(), cpu));
          _mem.add(FlSpot(_t.toDouble(), memPct));
          _netIn.add(FlSpot(_t.toDouble(), 0));
          _netOut.add(FlSpot(_t.toDouble(), 0));
          _diskR.add(FlSpot(_t.toDouble(), 0));
          _diskW.add(FlSpot(_t.toDouble(), 0));
          _t++;
          _waitingForMetrics = false;
        });
        _metricsWaitTimer?.cancel();
      }
    } catch (_) {
      // ignore; SSE will populate shortly
    }
  }

  void _addMetricsPointFromMap(Map<String, dynamic> map) {
    final cpu = (map['cpu_percent'] as num?)?.toDouble() ?? 0;
    final memUsed = (map['memory_used'] as num?)?.toDouble() ?? 0;
    final memTotal = (map['memory_total'] as num?)?.toDouble() ?? 1;
    final memPct = (memUsed / memTotal) * 100.0;
    final nIn = (map['net_bytes_in'] as num?) ?? 0;
    final nOut = (map['net_bytes_out'] as num?) ?? 0;
    final dR = (map['disk_read_bytes'] as num?) ?? 0;
    final dW = (map['disk_write_bytes'] as num?) ?? 0;
    final netInRate = _lastNetIn == null
        ? 0.0
        : ((nIn - _lastNetIn!) / _intervalSec) / 1024.0;
    final netOutRate = _lastNetOut == null
        ? 0.0
        : ((nOut - _lastNetOut!) / _intervalSec) / 1024.0;
    final diskRRate = _lastDiskR == null
        ? 0.0
        : ((dR - _lastDiskR!) / _intervalSec) / 1024.0;
    final diskWRate = _lastDiskW == null
        ? 0.0
        : ((dW - _lastDiskW!) / _intervalSec) / 1024.0;
    setState(() {
      _cpu.add(FlSpot(_t.toDouble(), cpu));
      _mem.add(FlSpot(_t.toDouble(), memPct));
      _netIn.add(FlSpot(_t.toDouble(), netInRate.toDouble()));
      _netOut.add(FlSpot(_t.toDouble(), netOutRate.toDouble()));
      _diskR.add(FlSpot(_t.toDouble(), diskRRate.toDouble()));
      _diskW.add(FlSpot(_t.toDouble(), diskWRate.toDouble()));
      if (_cpu.length > 60) _cpu.removeAt(0);
      if (_mem.length > 60) _mem.removeAt(0);
      if (_netIn.length > 60) _netIn.removeAt(0);
      if (_netOut.length > 60) _netOut.removeAt(0);
      if (_diskR.length > 60) _diskR.removeAt(0);
      if (_diskW.length > 60) _diskW.removeAt(0);
      _t++;
      _lastNetIn = nIn;
      _lastNetOut = nOut;
      _lastDiskR = dR;
      _lastDiskW = dW;
      _waitingForMetrics = false;
    });
    _metricsWaitTimer?.cancel();
  }

  void _checkActiveHost() {
    final auth = context.read<AuthService>();
    final activeUrl = auth.baseUrl;
    if (activeUrl != null && activeUrl != _currentHost) {
      _switchServer(activeUrl);
    }
  }

  Widget _loginsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent Logins',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: _loadingLists ? null : _loadLists,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_logins.isEmpty)
              const Text('No logins found')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('User')),
                    DataColumn(label: Text('TTY')),
                    DataColumn(label: Text('Host')),
                    DataColumn(label: Text('Since')),
                  ],
                  rows: [
                    for (final l in _logins.take(20))
                      DataRow(
                        cells: [
                          DataCell(Text(l.user)),
                          DataCell(Text(l.tty.isEmpty ? '-' : l.tty)),
                          DataCell(Text(l.host)),
                          DataCell(Text(l.since)),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _containersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Running Containers',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: _loadingLists ? null : _loadLists,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_containers.isEmpty)
              const Text('No containers')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Image')),
                    DataColumn(label: Text('State')),
                    DataColumn(label: Text('ID')),
                  ],
                  rows: [
                    for (final c in _containers.take(20))
                      DataRow(
                        cells: [
                          DataCell(Text(c.name.isEmpty ? c.id : c.name)),
                          DataCell(Text(c.image)),
                          DataCell(Text(c.state)),
                          DataCell(
                            Text(
                              c.id.substring(
                                0,
                                c.id.length > 12 ? 12 : c.id.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoginEntry {
  final String user;
  final String tty;
  final String host;
  final String since;
  _LoginEntry({
    required this.user,
    required this.tty,
    required this.host,
    required this.since,
  });
}

class _ContainerEntry {
  final String id;
  final String image;
  final String name;
  final String state;
  _ContainerEntry({
    required this.id,
    required this.image,
    required this.name,
    required this.state,
  });
}
