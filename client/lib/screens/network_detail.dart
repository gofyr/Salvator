import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth.dart';
import 'dart:async';

class NetworkDetailScreen extends StatefulWidget {
  const NetworkDetailScreen({super.key});
  @override
  State<NetworkDetailScreen> createState() => _NetworkDetailScreenState();
}

class _NetworkDetailScreenState extends State<NetworkDetailScreen> {
  bool _loading = true;
  List<_Listener> _listeners = [];
  List<_Iface> _ifaces = [];
  List<_Conn> _conns = [];
  Map<String, _Iface> _prevIfaces = {};
  DateTime? _lastPoll;
  late final _Poller _poller = _Poller(
    onTick: _pollOnce,
    interval: const Duration(seconds: 2),
  );

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
      final resp = await dio.get('/api/network/detail');
      if (resp.statusCode == 200 && resp.data is Map<String, dynamic>) {
        final m = resp.data as Map<String, dynamic>;
        _listeners =
            (m['listeners'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(
                  (e) => _Listener(
                    proto: (e['protocol'] ?? '').toString(),
                    addr: (e['local_address'] ?? '').toString(),
                    port: (e['local_port'] as num?)?.toInt() ?? 0,
                    pid: (e['pid'] as num?)?.toInt() ?? 0,
                    process: (e['process'] ?? '').toString(),
                  ),
                )
                .toList() ??
            [];
        _listeners.sort((a, b) => a.port.compareTo(b.port));
        _ifaces =
            (m['interfaces'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(
                  (e) => _Iface(
                    name: (e['name'] ?? '').toString(),
                    recv: (e['bytes_recv'] as num?)?.toInt() ?? 0,
                    sent: (e['bytes_sent'] as num?)?.toInt() ?? 0,
                    preq: (e['packets_recv'] as num?)?.toInt() ?? 0,
                    psent: (e['packets_sent'] as num?)?.toInt() ?? 0,
                    errIn: (e['err_in'] as num?)?.toInt() ?? 0,
                    errOut: (e['err_out'] as num?)?.toInt() ?? 0,
                  ),
                )
                .toList() ??
            [];
        _conns =
            (m['connections'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(
                  (e) => _Conn(
                    proto: (e['protocol'] ?? '').toString(),
                    laddr:
                        '${(e['laddr_ip'] ?? '').toString()}:${(e['laddr_port'] as num?)?.toInt() ?? 0}',
                    raddr:
                        '${(e['raddr_ip'] ?? '').toString()}:${(e['raddr_port'] as num?)?.toInt() ?? 0}',
                    pid: (e['pid'] as num?)?.toInt() ?? 0,
                    process: (e['process'] ?? '').toString(),
                    status: (e['status'] ?? '').toString(),
                  ),
                )
                .toList() ??
            [];
        _lastPoll = DateTime.now();
        _prevIfaces = {for (final i in _ifaces) i.name: i};
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  Future<void> _pollOnce() async {
    try {
      final auth = context.read<AuthService>();
      final dio = auth.createDio();
      final resp = await dio.get('/api/network/detail');
      if (resp.statusCode == 200 && resp.data is Map<String, dynamic>) {
        final m = resp.data as Map<String, dynamic>;
        final now = DateTime.now();
        final prevAt = _lastPoll;
        final prev = _prevIfaces;
        final ifaces =
            (m['interfaces'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(
                  (e) => _Iface(
                    name: (e['name'] ?? '').toString(),
                    recv: (e['bytes_recv'] as num?)?.toInt() ?? 0,
                    sent: (e['bytes_sent'] as num?)?.toInt() ?? 0,
                    preq: (e['packets_recv'] as num?)?.toInt() ?? 0,
                    psent: (e['packets_sent'] as num?)?.toInt() ?? 0,
                    errIn: (e['err_in'] as num?)?.toInt() ?? 0,
                    errOut: (e['err_out'] as num?)?.toInt() ?? 0,
                  ),
                )
                .toList() ??
            [];
        final conns =
            (m['connections'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(
                  (e) => _Conn(
                    proto: (e['protocol'] ?? '').toString(),
                    laddr:
                        '${(e['laddr_ip'] ?? '').toString()}:${(e['laddr_port'] as num?)?.toInt() ?? 0}',
                    raddr:
                        '${(e['raddr_ip'] ?? '').toString()}:${(e['raddr_port'] as num?)?.toInt() ?? 0}',
                    pid: (e['pid'] as num?)?.toInt() ?? 0,
                    process: (e['process'] ?? '').toString(),
                    status: (e['status'] ?? '').toString(),
                  ),
                )
                .toList() ??
            [];
        if (!mounted) return;
        setState(() {
          _ifaces = ifaces;
          _conns = conns;
          if (prevAt != null) {
            final dt = now.difference(prevAt).inMilliseconds / 1000.0;
            _ifaceRates = _computeRates(prev, _ifaces, dt);
          }
          _prevIfaces = {for (final i in _ifaces) i.name: i};
          _lastPoll = now;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network')),
      body: RefreshIndicator(
        onRefresh: _fetchAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('Listening ports'),
            const SizedBox(height: 8),
            _buildListenersTable(),
            const SizedBox(height: 16),
            _sectionTitle('Established connections'),
            const SizedBox(height: 8),
            _buildConnectionsTable(),
            const SizedBox(height: 16),
            _sectionTitle('Interfaces'),
            const SizedBox(height: 8),
            _buildIfacesTable(),
            const SizedBox(height: 8),
            _sectionTitle('Interface rates (approx)'),
            const SizedBox(height: 8),
            _buildIfaceRatesTable(),
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

  Widget _buildListenersTable() {
    if (_listeners.isEmpty) return const Text('No listening sockets');
    final rows = _listeners.map(
      (l) => DataRow(
        cells: [
          DataCell(Text(l.proto)),
          DataCell(Text('${l.addr}:${l.port}')),
          DataCell(Text(l.pid.toString())),
          DataCell(Text(l.process)),
        ],
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Proto')),
          DataColumn(label: Text('Local')),
          DataColumn(label: Text('PID')),
          DataColumn(label: Text('Process')),
        ],
        rows: rows.toList(),
      ),
    );
  }

  Widget _buildIfacesTable() {
    if (_ifaces.isEmpty) return const Text('No interface stats');
    final rows = _ifaces.map(
      (i) => DataRow(
        cells: [
          DataCell(Text(i.name)),
          DataCell(Text(_fmtBytes(i.recv))),
          DataCell(Text(_fmtBytes(i.sent))),
          DataCell(Text(i.preq.toString())),
          DataCell(Text(i.psent.toString())),
          DataCell(Text(i.errIn.toString())),
          DataCell(Text(i.errOut.toString())),
        ],
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Interface')),
          DataColumn(label: Text('Bytes In')),
          DataColumn(label: Text('Bytes Out')),
          DataColumn(label: Text('Packets In')),
          DataColumn(label: Text('Packets Out')),
          DataColumn(label: Text('Err In')),
          DataColumn(label: Text('Err Out')),
        ],
        rows: rows.toList(),
      ),
    );
  }

  Widget _buildConnectionsTable() {
    if (_conns.isEmpty) return const Text('No established connections');
    final rows = _conns.map(
      (c) => DataRow(
        cells: [
          DataCell(Text(c.proto)),
          DataCell(Text(c.laddr)),
          DataCell(Text(c.raddr)),
          DataCell(Text(c.pid.toString())),
          DataCell(Text(c.process)),
          DataCell(Text(c.status)),
        ],
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Proto')),
          DataColumn(label: Text('Local')),
          DataColumn(label: Text('Remote')),
          DataColumn(label: Text('PID')),
          DataColumn(label: Text('Process')),
          DataColumn(label: Text('Status')),
        ],
        rows: rows.toList(),
      ),
    );
  }

  Map<String, _IfaceRate> _ifaceRates = {};
  Map<String, _IfaceRate> _computeRates(
    Map<String, _Iface> prev,
    List<_Iface> now,
    double dt,
  ) {
    final rates = <String, _IfaceRate>{};
    for (final i in now) {
      final p = prev[i.name];
      if (p == null || dt <= 0) continue;
      rates[i.name] = _IfaceRate(
        rx: (i.recv - p.recv) / dt,
        tx: (i.sent - p.sent) / dt,
        rxPk: (i.preq - p.preq) / dt,
        txPk: (i.psent - p.psent) / dt,
      );
    }
    return rates;
  }

  Widget _buildIfaceRatesTable() {
    if (_ifaceRates.isEmpty) return const Text('No rate data yet');
    final rows = _ifaceRates.entries.map(
      (e) => DataRow(
        cells: [
          DataCell(Text(e.key)),
          DataCell(Text(_fmtBytes(e.value.rx))),
          DataCell(Text(_fmtBytes(e.value.tx))),
          DataCell(Text('${e.value.rxPk.toStringAsFixed(0)} pkts/s')),
          DataCell(Text('${e.value.txPk.toStringAsFixed(0)} pkts/s')),
        ],
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Interface')),
          DataColumn(label: Text('RX/s')),
          DataColumn(label: Text('TX/s')),
          DataColumn(label: Text('RX pkts/s')),
          DataColumn(label: Text('TX pkts/s')),
        ],
        rows: rows.toList(),
      ),
    );
  }

  String _fmtBytes(num v) {
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    double n = v.toDouble();
    int i = 0;
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    return '${n.toStringAsFixed(1)} ${units[i]}';
  }
}

class _Listener {
  final String proto;
  final String addr;
  final int port;
  final int pid;
  final String process;
  _Listener({
    required this.proto,
    required this.addr,
    required this.port,
    required this.pid,
    required this.process,
  });
}

class _Iface {
  final String name;
  final int recv;
  final int sent;
  final int preq;
  final int psent;
  final int errIn;
  final int errOut;
  _Iface({
    required this.name,
    required this.recv,
    required this.sent,
    required this.preq,
    required this.psent,
    required this.errIn,
    required this.errOut,
  });
}

class _Conn {
  final String proto;
  final String laddr;
  final String raddr;
  final int pid;
  final String process;
  final String status;
  _Conn({
    required this.proto,
    required this.laddr,
    required this.raddr,
    required this.pid,
    required this.process,
    required this.status,
  });
}

class _IfaceRate {
  final double rx;
  final double tx;
  final double rxPk;
  final double txPk;
  _IfaceRate({
    required this.rx,
    required this.tx,
    required this.rxPk,
    required this.txPk,
  });
}

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
