import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth.dart';
import 'dart:async';

class SystemDetailScreen extends StatefulWidget {
  const SystemDetailScreen({super.key});
  @override
  State<SystemDetailScreen> createState() => _SystemDetailScreenState();
}

class _SystemDetailScreenState extends State<SystemDetailScreen> {
  bool _loading = true;
  List<double> _perCpu = [];
  double _load1 = 0, _load5 = 0, _load15 = 0;
  Map<String, num> _mem = {};
  List<_Proc> _procs = [];
  // History and polling
  List<List<double>> _perCpuHistory = [];
  final int _historyLen = 30;
  final Duration _pollInterval = const Duration(seconds: 2);
  late final _Poller _poller = _Poller(
    onTick: _pollOnce,
    interval: _pollInterval,
  );
  // Process filtering/sorting
  String _procFilter = '';
  _ProcSort _procSort = _ProcSort.cpuDesc;

  @override
  void initState() {
    super.initState();
    _fetchAll();
    _poller.start();
  }

  Future<void> _fetchAll() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      final dio = auth.createDio();
      final sys = await dio.get('/api/system/detail');
      final procs = await dio.get('/api/processes');
      if (sys.statusCode == 200 && sys.data is Map<String, dynamic>) {
        final m = sys.data as Map<String, dynamic>;
        _perCpu =
            (m['per_cpu'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList()
                .cast<double>() ??
            [];
        _load1 = (m['load1'] as num?)?.toDouble() ?? 0;
        _load5 = (m['load5'] as num?)?.toDouble() ?? 0;
        _load15 = (m['load15'] as num?)?.toDouble() ?? 0;
        final md = (m['memory'] as Map?)?.cast<String, dynamic>() ?? {};
        _mem = md.map((k, v) => MapEntry(k, (v as num)));
        _seedHistoryIfNeeded();
        _appendHistory(_perCpu);
      }
      if (procs.statusCode == 200 && procs.data is List) {
        _procs = (procs.data as List)
            .whereType<Map<String, dynamic>>()
            .map(
              (p) => _Proc(
                pid: (p['pid'] as num?)?.toInt() ?? 0,
                name: (p['name'] ?? '').toString(),
                cpu: (p['cpu'] as num?)?.toDouble() ?? 0,
                mem: (p['memory'] as num?)?.toInt() ?? 0,
                user: (p['username'] ?? '').toString(),
              ),
            )
            .toList();
        _procs.sort((a, b) => b.cpu.compareTo(a.cpu));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pollOnce() async {
    try {
      final auth = context.read<AuthService>();
      final dio = auth.createDio();
      final sys = await dio.get('/api/system/detail');
      if (sys.statusCode == 200 && sys.data is Map<String, dynamic>) {
        final m = sys.data as Map<String, dynamic>;
        final per =
            (m['per_cpu'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList()
                .cast<double>() ??
            [];
        final md = (m['memory'] as Map?)?.cast<String, dynamic>() ?? {};
        if (!mounted) return;
        setState(() {
          _perCpu = per;
          _load1 = (m['load1'] as num?)?.toDouble() ?? _load1;
          _load5 = (m['load5'] as num?)?.toDouble() ?? _load5;
          _load15 = (m['load15'] as num?)?.toDouble() ?? _load15;
          _mem = md.map((k, v) => MapEntry(k, (v as num)));
          _seedHistoryIfNeeded();
          _appendHistory(_perCpu);
        });
      }
    } catch (_) {}
  }

  void _seedHistoryIfNeeded() {
    if (_perCpuHistory.length != _perCpu.length) {
      _perCpuHistory = List.generate(_perCpu.length, (_) => <double>[]);
    }
  }

  void _appendHistory(List<double> per) {
    for (int i = 0; i < per.length && i < _perCpuHistory.length; i++) {
      final h = _perCpuHistory[i];
      h.add(per[i]);
      if (h.length > _historyLen) h.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CPU & Memory')),
      body: RefreshIndicator(
        onRefresh: _fetchAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('Per-core CPU % (history)'),
            const SizedBox(height: 8),
            _buildPerCoreHistory(),
            const SizedBox(height: 16),
            _sectionTitle('Load averages'),
            const SizedBox(height: 8),
            Text(
              '1m: ${_load1.toStringAsFixed(2)}  5m: ${_load5.toStringAsFixed(2)}  15m: ${_load15.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 16),
            _sectionTitle('Memory'),
            const SizedBox(height: 8),
            _buildMemoryIndicator(),
            const SizedBox(height: 16),
            _sectionTitle('Top processes (CPU)'),
            const SizedBox(height: 8),
            _buildProcControls(),
            const SizedBox(height: 8),
            _buildProcTable(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String s) =>
      Text(s, style: const TextStyle(fontWeight: FontWeight.bold));

  Widget _buildProcTable() {
    if (_procs.isEmpty) return const Text('No processes');
    // filter and sort
    final filtered = _procs.where((p) {
      if (_procFilter.isEmpty) return true;
      final q = _procFilter.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.user.toLowerCase().contains(q);
    }).toList();
    filtered.sort((a, b) {
      switch (_procSort) {
        case _ProcSort.cpuDesc:
          return b.cpu.compareTo(a.cpu);
        case _ProcSort.cpuAsc:
          return a.cpu.compareTo(b.cpu);
        case _ProcSort.memDesc:
          return b.mem.compareTo(a.mem);
        case _ProcSort.memAsc:
          return a.mem.compareTo(b.mem);
        case _ProcSort.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _ProcSort.nameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
      }
    });
    final rows = filtered
        .take(50)
        .map(
          (p) => DataRow(
            cells: [
              DataCell(Text(p.pid.toString())),
              DataCell(Text(p.name)),
              DataCell(Text('${p.cpu.toStringAsFixed(1)}%')),
              DataCell(Text(_fmtBytes(p.mem))),
              DataCell(Text(p.user)),
            ],
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('PID')),
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('CPU')),
          DataColumn(label: Text('Memory')),
          DataColumn(label: Text('User')),
        ],
        rows: rows.toList(),
      ),
    );
  }

  Widget _buildPerCoreHistory() {
    if (_perCpu.isEmpty) return const Text('No data');
    final items = <Widget>[];
    for (int i = 0; i < _perCpu.length; i++) {
      final data = _perCpuHistory.length > i ? _perCpuHistory[i] : <double>[];
      final spots = [
        for (int j = 0; j < data.length; j++)
          FlSpot(j.toDouble(), data[j].clamp(0, 100)),
      ];
      items.add(
        SizedBox(
          width: 120,
          height: 80,
          child: Card(
            elevation: 0,
            color: const Color(0xFF121216),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CPU $i',
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                  Expanded(
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            color: Colors.purpleAccent,
                            isCurved: true,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                        minY: 0,
                        maxY: 100,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );
  }

  Widget _buildProcControls() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Filter by name or user',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _procFilter = v.trim()),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 40,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<_ProcSort>(
              value: _procSort,
              onChanged: (v) =>
                  setState(() => _procSort = v ?? _ProcSort.cpuDesc),
              items: const [
                DropdownMenuItem(
                  value: _ProcSort.cpuDesc,
                  child: Text('CPU ▼'),
                ),
                DropdownMenuItem(value: _ProcSort.cpuAsc, child: Text('CPU ▲')),
                DropdownMenuItem(
                  value: _ProcSort.memDesc,
                  child: Text('Mem ▼'),
                ),
                DropdownMenuItem(value: _ProcSort.memAsc, child: Text('Mem ▲')),
                DropdownMenuItem(
                  value: _ProcSort.nameAsc,
                  child: Text('Name ▲'),
                ),
                DropdownMenuItem(
                  value: _ProcSort.nameDesc,
                  child: Text('Name ▼'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // duplicate removed

  Widget _buildMemoryIndicator() {
    final total = (_mem['total'] ?? 0).toDouble();
    final used = (_mem['used'] ?? 0).toDouble();
    final avail = (_mem['available'] ?? 0).toDouble();
    final buffers = (_mem['buffers'] ?? 0).toDouble();
    final cached = (_mem['cached'] ?? 0).toDouble();
    final usedPct = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Used: ${_fmtBytes(used)}'),
            Text('${(usedPct * 100).toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: usedPct,
            minHeight: 10,
            backgroundColor: const Color(0xFF22222A),
            valueColor: const AlwaysStoppedAnimation<Color>(
              Colors.purpleAccent,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: -6,
          children: [
            Text(
              'Total: ${_fmtBytes(total)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Avail: ${_fmtBytes(avail)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Buffers: ${_fmtBytes(buffers)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Cached: ${_fmtBytes(cached)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Swap: ${_fmtBytes(_mem['swap_used'])}/${_fmtBytes(_mem['swap_total'])}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  String _fmtBytes(num? v) {
    if (v == null) return '-';
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    double n = v.toDouble();
    int i = 0;
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    return '${n.toStringAsFixed(1)} ${units[i]}';
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }
}

class _Proc {
  final int pid;
  final String name;
  final double cpu;
  final int mem;
  final String user;
  const _Proc({
    required this.pid,
    required this.name,
    required this.cpu,
    required this.mem,
    required this.user,
  });
}

enum _ProcSort { cpuDesc, cpuAsc, memDesc, memAsc, nameAsc, nameDesc }

class _Poller {
  final Duration interval;
  final Future<void> Function() onTick;
  _Poller({required this.onTick, required this.interval});
  Timer? _timer;
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => onTick());
  }

  void dispose() {
    _timer?.cancel();
  }
}
