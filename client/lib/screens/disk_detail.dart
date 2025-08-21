import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth.dart';

class DiskDetailScreen extends StatefulWidget {
  const DiskDetailScreen({super.key});
  @override
  State<DiskDetailScreen> createState() => _DiskDetailScreenState();
}

class _DiskDetailScreenState extends State<DiskDetailScreen> {
  bool _loading = true;
  List<_Mount> _mounts = [];
  List<_DiskIO> _ios = [];

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      final dio = auth.createDio();
      final resp = await dio.get('/api/disk/detail');
      if (resp.statusCode == 200 && resp.data is Map<String, dynamic>) {
        final m = resp.data as Map<String, dynamic>;
        _mounts =
            (m['mounts'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(
                  (e) => _Mount(
                    device: (e['device'] ?? '').toString(),
                    mountpoint: (e['mountpoint'] ?? '').toString(),
                    fstype: (e['fstype'] ?? '').toString(),
                    total: (e['total'] as num?)?.toInt() ?? 0,
                    used: (e['used'] as num?)?.toInt() ?? 0,
                    free: (e['free'] as num?)?.toInt() ?? 0,
                    usedPct: (e['used_percent'] as num?)?.toDouble() ?? 0,
                  ),
                )
                .toList() ??
            [];
        _ios =
            (m['io'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(
                  (e) => _DiskIO(
                    name: (e['name'] ?? '').toString(),
                    readBytes: (e['read_bytes'] as num?)?.toInt() ?? 0,
                    writeBytes: (e['write_bytes'] as num?)?.toInt() ?? 0,
                    reads: (e['reads'] as num?)?.toInt() ?? 0,
                    writes: (e['writes'] as num?)?.toInt() ?? 0,
                  ),
                )
                .toList() ??
            [];
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Disk')),
      body: RefreshIndicator(
        onRefresh: _fetchAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('Mounts'),
            const SizedBox(height: 8),
            _buildMountsTable(),
            const SizedBox(height: 16),
            _sectionTitle('Device I/O'),
            const SizedBox(height: 8),
            _buildIOTable(),
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

  Widget _buildMountsTable() {
    if (_mounts.isEmpty) return const Text('No mounts');
    final rows = _mounts.map(
      (m) => DataRow(
        cells: [
          DataCell(Text(m.device)),
          DataCell(Text(m.mountpoint)),
          DataCell(Text(m.fstype)),
          DataCell(Text(_fmtBytes(m.total))),
          DataCell(Text(_fmtBytes(m.used))),
          DataCell(Text(_fmtBytes(m.free))),
          DataCell(Text('${m.usedPct.toStringAsFixed(1)}%')),
        ],
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Device')),
          DataColumn(label: Text('Mountpoint')),
          DataColumn(label: Text('FS')),
          DataColumn(label: Text('Total')),
          DataColumn(label: Text('Used')),
          DataColumn(label: Text('Free')),
          DataColumn(label: Text('Used %')),
        ],
        rows: rows.toList(),
      ),
    );
  }

  Widget _buildIOTable() {
    if (_ios.isEmpty) return const Text('No device I/O');
    final rows = _ios.map(
      (d) => DataRow(
        cells: [
          DataCell(Text(d.name)),
          DataCell(Text(_fmtBytes(d.readBytes))),
          DataCell(Text(_fmtBytes(d.writeBytes))),
          DataCell(Text(d.reads.toString())),
          DataCell(Text(d.writes.toString())),
        ],
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Device')),
          DataColumn(label: Text('Read Bytes')),
          DataColumn(label: Text('Write Bytes')),
          DataColumn(label: Text('Reads')),
          DataColumn(label: Text('Writes')),
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

class _Mount {
  final String device;
  final String mountpoint;
  final String fstype;
  final int total;
  final int used;
  final int free;
  final double usedPct;
  _Mount({
    required this.device,
    required this.mountpoint,
    required this.fstype,
    required this.total,
    required this.used,
    required this.free,
    required this.usedPct,
  });
}

class _DiskIO {
  final String name;
  final int readBytes;
  final int writeBytes;
  final int reads;
  final int writes;
  _DiskIO({
    required this.name,
    required this.readBytes,
    required this.writeBytes,
    required this.reads,
    required this.writes,
  });
}
