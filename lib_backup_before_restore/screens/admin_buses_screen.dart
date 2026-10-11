import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// Admin "Buses".
///
/// Every bus is created automatically with its route. Here the admin fills in
/// what only the admin knows:
///   * capacity (seats). A bus without capacity is never offered as a rescue bus.
///   * the real number plate and a name
///   * the GPS device fitted to the bus (register / remove, and whether it is online)
class AdminBusesScreen extends StatefulWidget {
  const AdminBusesScreen({super.key});

  @override
  State<AdminBusesScreen> createState() => _AdminBusesScreenState();
}

class _AdminBusesScreenState extends State<AdminBusesScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  String? _institutionId;
  List<Map<String, dynamic>> _buses = [];
  Map<String, String> _routeOfBus = {};
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_channel != null) _sb.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in.');
      final inst = await _sb
          .from('institutions')
          .select('id')
          .eq('admin_id', uid)
          .maybeSingle();
      if (inst == null) throw Exception('No institution found for this admin.');
      final id = inst['id'].toString();

      final buses = await _sb
          .from('buses')
          .select('id, bus_number, bus_name, capacity, gps_device_id, gps_last_seen')
          .eq('institution_id', id)
          .order('bus_number', ascending: true);

      final routes = await _sb
          .from('routes')
          .select('route_name, bus_id')
          .eq('institution_id', id);

      if (!mounted) return;
      setState(() {
        _institutionId = id;
        _buses = List<Map<String, dynamic>>.from(buses);
        _routeOfBus = {
          for (final r in routes)
            if (r['bus_id'] != null) r['bus_id'].toString(): r['route_name']?.toString() ?? '',
        };
        _loading = false;
      });

      if (_channel == null) {
        _channel = _sb
            .channel('admin_buses_$id')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'buses',
              filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'institution_id',
                  value: id),
              callback: (_) => _load(silent: true),
            )
            .subscribe();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Ym.red : Ym.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _err(Object e) => e is PostgrestException ? e.message : e.toString();

  // ───────────────────────── edit bus ─────────────────────────

  Future<void> _editBus(Map<String, dynamic> b) async {
    final number = TextEditingController(text: b['bus_number']?.toString() ?? '');
    final name = TextEditingController(text: b['bus_name']?.toString() ?? '');
    final cap = TextEditingController(text: b['capacity']?.toString() ?? '');
    String? error;
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          InputDecoration deco(String l, IconData i) => InputDecoration(
                labelText: l,
                prefixIcon: Icon(i, size: 20, color: Ym.grey),
                filled: true,
                fillColor: const Color(0xFFF8F9FB),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              );

          Future<void> save() async {
            final n = number.text.trim();
            final c = int.tryParse(cap.text.trim());
            if (n.isEmpty) {
              setModal(() => error = 'The bus number is required.');
              return;
            }
            if (c == null || c <= 0) {
              setModal(() => error = 'Enter the number of seats (more than 0).');
              return;
            }
            setModal(() {
              saving = true;
              error = null;
            });
            try {
              await _sb.from('buses').update({
                'bus_number': n,
                'bus_name': name.text.trim().isEmpty ? null : name.text.trim(),
                'capacity': c,
              }).eq('id', b['id']);
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('Bus saved.');
              await _load(silent: true);
            } catch (e) {
              setModal(() {
                error = _err(e);
                saving = false;
              });
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Edit bus', style: Ym.h(18)),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: number,
                      decoration: deco('Number plate', Icons.confirmation_number_outlined)),
                  const SizedBox(height: 12),
                  TextField(
                      controller: name,
                      decoration: deco('Name (optional)', Icons.directions_bus_outlined)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cap,
                    keyboardType: TextInputType.number,
                    decoration: deco('Capacity (seats)', Icons.event_seat_outlined),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error!,
                          style: Ym.t(12.5, color: Ym.red, w: FontWeight.w600)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: saving ? null : save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Ym.amber,
                  foregroundColor: Ym.navy,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    number.dispose();
    name.dispose();
    cap.dispose();
  }

  // ───────────────────────── GPS device ─────────────────────────

  Future<void> _registerDevice(Map<String, dynamic> b) async {
    final suggestion =
        '${b['bus_number'] ?? 'BUS'}-GPS'.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '-');
    final c = TextEditingController(text: suggestion);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Register GPS device', style: Ym.h(18)),
        content: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: 'Device ID',
            helperText:
                'The ID that is set in the device. Once registered, only this device can give this bus its location.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Ym.amber,
              foregroundColor: Ym.navy,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Register'),
          ),
        ],
      ),
    );
    final deviceId = c.text.trim();
    c.dispose();
    if (ok != true) return;
    if (deviceId.isEmpty) {
      _snack('Enter a device ID.', error: true);
      return;
    }
    try {
      final secret = await _sb.rpc('register_gps_device',
          params: {'p_bus': b['id'], 'p_device_id': deviceId});
      await _load(silent: true);
      if (!mounted) return;
      await _showSecret(deviceId, secret.toString());
    } catch (e) {
      _snack(_err(e), error: true);
    }
  }

  Future<void> _showSecret(String deviceId, String secret) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Device secret', style: Ym.h(18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device ID', style: Ym.t(11.5, color: Ym.grey)),
            SelectableText(deviceId, style: Ym.h(15)),
            const SizedBox(height: 12),
            Text('Secret', style: Ym.t(11.5, color: Ym.grey)),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(secret,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Ym.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                  'This secret is shown only now. Copy it and put it in the device. If it is lost, register the device again to get a new one.',
                  style: Ym.t(12, color: Ym.red, w: FontWeight.w600)),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: secret));
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Secret copied'),
                  behavior: SnackBarBehavior.floating));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: Ym.amber,
              foregroundColor: Ym.navy,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeDevice(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Remove the GPS device?'),
        content: const Text(
            'The bus goes back to taking its location from the driver\'s phone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Ym.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _sb.rpc('unregister_gps_device', params: {'p_bus': b['id']});
      _snack('Device removed.');
      await _load(silent: true);
    } catch (e) {
      _snack(_err(e), error: true);
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final missing = _buses.where((b) => b['capacity'] == null).length;
    return YmPage(
      title: 'Buses',
      subtitle: 'Capacity and GPS devices',
      child: _loading
          ? const YmSkeletonList(count: 4, height: 150)
          : _error != null
              ? YmEmpty(
                  icon: Icons.error_outline_rounded,
                  color: Ym.red,
                  title: 'Could not load',
                  subtitle: _error,
                  action: YmButton(
                      label: 'Try again',
                      expanded: false,
                      icon: Icons.refresh_rounded,
                      onPressed: _load),
                )
              : RefreshIndicator(
                  color: Ym.amber,
                  onRefresh: () => _load(silent: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                    children: [
                      if (missing > 0)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Ym.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(18),
                            border: const Border(
                                left: BorderSide(color: Ym.red, width: 4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Ym.red, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                    '$missing bus${missing == 1 ? '' : 'es'} ${missing == 1 ? 'has' : 'have'} no capacity set. '
                                    'They cannot be offered as a rescue bus until you set it.',
                                    style: Ym.t(12.5, color: Ym.red, w: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                      if (_buses.isEmpty)
                        const YmEmpty(
                            icon: Icons.directions_bus_outlined,
                            title: 'No buses yet',
                            subtitle: 'Buses are created automatically when you upload routes.')
                      else
                        for (var i = 0; i < _buses.length; i++)
                          YmFadeSlide(index: i, child: _busCard(_buses[i])),
                    ],
                  ),
                ),
    );
  }

  Widget _busCard(Map<String, dynamic> b) {
    final cap = b['capacity'];
    final device = b['gps_device_id']?.toString();
    final seen = parseUtc(b['gps_last_seen']);
    final online = seen != null && DateTime.now().difference(seen).inSeconds < 120;
    final route = _routeOfBus[b['id'].toString()];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: YmCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const YmIconBadge(icon: Icons.directions_bus_rounded, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b['bus_number']?.toString() ?? '', style: Ym.h(16)),
                      Text(route == null ? 'No route' : 'Route: $route',
                          style: Ym.t(12, color: Ym.grey)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_rounded, size: 19, color: Ym.navy),
                  onPressed: () => _editBus(b),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                cap == null
                    ? const YmChip('Capacity not set', color: Ym.red)
                    : YmChip('$cap seats', color: Ym.blue, icon: Icons.event_seat_rounded),
                if (device == null)
                  const YmChip('No GPS device', color: Ym.grey)
                else
                  YmChip(online ? 'Device online' : 'Device offline',
                      color: online ? Ym.green : Ym.amberDark,
                      icon: Icons.satellite_alt_rounded),
              ],
            ),
            if (device != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Device $device'
                  '${seen != null ? '  •  last seen ${fmtClock(seen)}' : '  •  never seen'}',
                  style: Ym.t(11.5, color: Ym.grey),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (cap == null)
                  _btn('Set capacity', Icons.event_seat_outlined, Ym.red, () => _editBus(b)),
                if (device == null)
                  _btn('Register GPS device', Icons.satellite_alt_rounded, Ym.blue,
                      () => _registerDevice(b))
                else ...[
                  _btn('New secret', Icons.key_rounded, Ym.blue, () => _registerDevice(b)),
                  _btn('Remove device', Icons.link_off_rounded, Ym.red, () => _removeDevice(b)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, IconData icon, Color color, VoidCallback onTap) =>
      YmPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(label, style: Ym.t(12, color: color, w: FontWeight.w800)),
            ],
          ),
        ),
      );
}