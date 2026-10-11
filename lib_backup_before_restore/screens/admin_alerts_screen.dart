import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';
import 'admin_buses_screen.dart';

/// Admin "Alerts".
///
///  * Breakdown rescues: who was asked, who accepted, and controls to find
///    another bus or cancel.
///  * Everything the system sent to the admin (SOS alerts, driver issues, rescue
///    updates), newest first. Updates live.
///  * The rescue radius: how far a rescue bus may be (set by the admin).
class AdminAlertsScreen extends StatefulWidget {
  const AdminAlertsScreen({super.key});

  @override
  State<AdminAlertsScreen> createState() => _AdminAlertsScreenState();
}

class _AdminAlertsScreenState extends State<AdminAlertsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  String? _institutionId;
  num _radius = 5;
  List<Map<String, dynamic>> _sos = []; // SOS alerts from students and drivers
  num _stopRadius = 100; // metres: how close the bus must be to mark a stop reached
  int _noCapacity = 0; // buses the admin has not set a capacity for
  List<Map<String, dynamic>> _rescues = [];
  Map<String, String> _busNumbers = {};
  Map<String, String> _driverNames = {};
  Map<String, Map<String, dynamic>> _issues = {};
  List<Map<String, dynamic>> _notifications = [];
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
          .select('id, rescue_radius_km, stop_reach_radius_m')
          .eq('admin_id', uid)
          .maybeSingle();
      if (inst == null) throw Exception('No institution found for this admin.');
      final id = inst['id'].toString();

      final rescues = await _sb
          .from('rescue_assignments')
          .select()
          .eq('institution_id', id)
          .order('created_at', ascending: false)
          .limit(20);
      final list = List<Map<String, dynamic>>.from(rescues);

      final busIds = <String>{};
      final driverIds = <String>{};
      final issueIds = <String>{};
      for (final r in list) {
        for (final k in ['broken_bus_id', 'rescue_bus_id']) {
          if (r[k] != null) busIds.add(r[k].toString());
        }
        if (r['rescue_driver_id'] != null) driverIds.add(r['rescue_driver_id'].toString());
        if (r['issue_id'] != null) issueIds.add(r['issue_id'].toString());
      }

      var buses = <String, String>{};
      if (busIds.isNotEmpty) {
        final b = await _sb
            .from('buses')
            .select('id, bus_number')
            .inFilter('id', busIds.toList());
        buses = {for (final x in b) x['id'].toString(): x['bus_number']?.toString() ?? ''};
      }

      var issues = <String, Map<String, dynamic>>{};
      if (issueIds.isNotEmpty) {
        final i = await _sb
            .from('driver_issues')
            .select('id, description, driver_id')
            .inFilter('id', issueIds.toList());
        issues = {for (final x in i) x['id'].toString(): Map<String, dynamic>.from(x)};
        for (final x in i) {
          if (x['driver_id'] != null) driverIds.add(x['driver_id'].toString());
        }
      }

      var drivers = <String, String>{};
      if (driverIds.isNotEmpty) {
        final d = await _sb
            .from('drivers')
            .select('id, driver_name')
            .inFilter('id', driverIds.toList());
        drivers = {for (final x in d) x['id'].toString(): x['driver_name']?.toString() ?? ''};
      }

      final caps = await _sb
          .from('buses')
          .select('id, capacity')
          .eq('institution_id', id);
      final noCap = caps.where((b) => b['capacity'] == null).length;

      var sosRows = <dynamic>[];
      try {
        sosRows = await _sb.rpc('inbox_emergencies') as List;
      } catch (_) {
        // step 14 not run yet: the SOS list stays empty
      }

      final notes = await _sb
          .from('notifications')
          .select('id, title, message, type, is_read, created_at')
          .eq('recipient_id', uid)
          .order('created_at', ascending: false)
          .limit(40);

      if (!mounted) return;
      setState(() {
        _institutionId = id;
        _radius = num.tryParse('${inst['rescue_radius_km']}') ?? 5;
        _stopRadius = num.tryParse('${inst['stop_reach_radius_m']}') ?? 100;
        _noCapacity = noCap;
        _rescues = list;
        _busNumbers = buses;
        _driverNames = drivers;
        _issues = issues;
        _notifications = List<Map<String, dynamic>>.from(notes);
        _sos = List<Map<String, dynamic>>.from(sosRows);
        _loading = false;
      });

      _listen(id, uid);
      _sb
          .from('notifications')
          .update({'is_read': true})
          .eq('recipient_id', uid)
          .eq('is_read', false)
          .then((_) {})
          .catchError((_) {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _listen(String inst, String uid) {
    if (_channel != null) return;
    _channel = _sb
        .channel('admin_alerts_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rescue_assignments',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'institution_id',
              value: inst),
          callback: (_) => _load(silent: true),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'recipient_id',
              value: uid),
          callback: (_) => _load(silent: true),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'emergencies',
          callback: (_) => _load(silent: true),
        )
        .subscribe();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Ym.red : Ym.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _rpc(String fn, String id, String done) async {
    try {
      await _sb.rpc(fn, params: {'p_id': id});
      _snack(done);
      await _load(silent: true);
    } on PostgrestException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('$e', error: true);
    }
  }

  /// The admin picks which running bus gets the pickup.
  Future<void> _assignBus(Map<String, dynamic> r) async {
    var cands = <Map<String, dynamic>>[];
    String? err;
    try {
      final rows =
          await _sb.rpc('rescue_candidates', params: {'p_issue': r['issue_id']});
      cands = List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      err = e is PostgrestException ? e.message : e.toString();
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(
                    color: Ym.line, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Assign a bus', style: Ym.h(20)),
            const SizedBox(height: 4),
            Text('Buses with a trip running now, nearest first.',
                style: Ym.t(12.5, color: Ym.grey)),
            const SizedBox(height: 14),
            if (err != null)
              Text(err, style: Ym.t(13, color: Ym.red))
            else if (cands.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('No other bus has a trip running right now.',
                    style: Ym.t(13.5, color: Ym.grey)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cands.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final c = cands[i];
                    final seats = c['seats_left'];
                    final dist = c['distance_km'];
                    final noCap = c['capacity'] == null;
                    final full = seats != null && seats <= 0;
                    final warn = noCap || full;
                    return YmPressable(
                      onTap: () {
                        Navigator.pop(ctx);
                        _assign(r, c);
                      },
                      scale: 0.98,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Ym.creamTop,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const YmIconBadge(
                                icon: Icons.directions_bus_rounded, size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c['bus_number']?.toString() ?? '',
                                      style: Ym.h(15)),
                                  Text('Driver ${c['driver_name'] ?? '-'}',
                                      style: Ym.t(12, color: Ym.grey)),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      dist == null ? 'location unknown' : '$dist km away',
                                      noCap
                                          ? 'capacity not set'
                                          : (full ? 'bus is full' : '$seats seats free'),
                                    ].join('  •  '),
                                    style: Ym.t(12,
                                        color: warn ? Ym.red : Ym.green,
                                        w: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Ym.grey),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _assign(Map<String, dynamic> r, Map<String, dynamic> c) async {
    try {
      await _sb.rpc('admin_assign_rescue', params: {
        'p_issue': r['issue_id'],
        'p_bus': c['bus_id'],
      });
      _snack('Request sent to ${c['driver_name'] ?? 'the driver'}.');
      await _load(silent: true);
    } on PostgrestException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('$e', error: true);
    }
  }

  Future<void> _editRadius() async {
    final c = TextEditingController(text: _radius.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Rescue radius', style: Ym.h(18)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Kilometres',
            helperText:
                'After a breakdown, only buses within this distance are asked to help.',
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final v = num.tryParse(c.text.trim());
    c.dispose();
    if (ok != true) return;
    if (v == null || v <= 0) {
      _snack('Enter a distance greater than 0.', error: true);
      return;
    }
    try {
      await _sb
          .from('institutions')
          .update({'rescue_radius_km': v}).eq('id', _institutionId!);
      _snack('Rescue radius saved.');
      await _load(silent: true);
    } catch (e) {
      _snack('Could not save: $e', error: true);
    }
  }

  Future<void> _respondSos(Map<String, dynamic> e, String status) async {
    try {
      await _sb.rpc('respond_emergency',
          params: {'p_id': e['id'], 'p_status': status});
      _snack(status == 'resolved' ? 'Marked as resolved.' : 'Acknowledged.');
      await _load(silent: true);
    } on PostgrestException catch (err) {
      _snack(err.message, error: true);
    } catch (err) {
      _snack('$err', error: true);
    }
  }

  Future<void> _openMapAt(dynamic lat, dynamic lng) async {
    final la = double.tryParse('$lat');
    final lo = double.tryParse('$lng');
    if (la == null || lo == null) {
      _snack('No location was shared with this alert.', error: true);
      return;
    }
    await launchUrl(
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$la,$lo'),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _callPhone(dynamic phone) async {
    final p = (phone ?? '').toString();
    if (p.isEmpty) {
      _snack('No phone number available.', error: true);
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: p));
  }

  Widget _sosCard(Map<String, dynamic> e) {
    final status = e['status']?.toString() ?? 'open';
    final resolved = status == 'resolved';
    final acked = status == 'acknowledged';
    final color = resolved ? Ym.green : (acked ? Ym.amberDark : Ym.red);
    final at = parseUtc(e['created_at']);
    final role = e['who_role']?.toString() ?? 'unknown';
    final type = (e['type'] ?? 'other').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: Ym.shadow(color, 0.12),
          border: Border(left: BorderSide(color: color, width: 5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                YmGradientTile(
                    icon: resolved ? Icons.check_rounded : Icons.warning_rounded,
                    color: color,
                    size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e['who']?.toString() ?? 'Unknown', style: Ym.h(15)),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          YmChip(role == 'driver' ? 'Driver' : (role == 'student' ? 'Student' : 'User'),
                              color: Ym.blue),
                          YmChip(type[0].toUpperCase() + type.substring(1), color: color),
                          if (e['bus_number'] != null)
                            YmChip('Bus ${e['bus_number']}',
                                color: Ym.navy, icon: Icons.directions_bus_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
                YmChip(resolved ? 'Resolved' : (acked ? 'Acknowledged' : 'NEW'),
                    color: color, solid: !resolved && !acked),
              ],
            ),
            if ((e['description'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(e['description'].toString(), style: Ym.t(13, color: Ym.grey)),
              ),
            if (at != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${fmtDate(at)}  •  ${fmtClock(at)}',
                    style: Ym.t(11, color: Ym.grey)),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if ((e['phone'] ?? '').toString().isNotEmpty)
                  _action('Call', Icons.call_rounded, Ym.green, () => _callPhone(e['phone'])),
                if (e['lat'] != null && e['lng'] != null)
                  _action('Location', Icons.location_on_rounded, Ym.blue,
                      () => _openMapAt(e['lat'], e['lng'])),
                if (status == 'open')
                  _action('Acknowledge', Icons.visibility_rounded, Ym.amberDark,
                      () => _respondSos(e, 'acknowledged')),
                if (!resolved)
                  _action('Resolve', Icons.check_circle_rounded, Ym.green,
                      () => _respondSos(e, 'resolved')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editStopRadius() async {
    final c = TextEditingController(text: _stopRadius.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Stop arrival distance', style: Ym.h(18)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Metres',
            helperText:
                'A stop is marked reached automatically when the bus gets this close to it.',
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final v = num.tryParse(c.text.trim());
    c.dispose();
    if (ok != true) return;
    if (v == null || v <= 0) {
      _snack('Enter a distance greater than 0.', error: true);
      return;
    }
    try {
      await _sb
          .from('institutions')
          .update({'stop_reach_radius_m': v}).eq('id', _institutionId!);
      _snack('Stop arrival distance saved.');
      await _load(silent: true);
    } catch (e) {
      _snack('Could not save: $e', error: true);
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Alerts',
      subtitle: 'Breakdowns, SOS and driver issues',
      child: _loading
          ? const YmSkeletonList(count: 4, height: 110)
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
                  child: _body(),
                ),
    );
  }

  Widget _body() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
      children: [
        YmFadeSlide(
          index: 0,
          child: YmCard(
            onTap: _editRadius,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const YmIconBadge(icon: Icons.radar_rounded, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rescue radius', style: Ym.h(15)),
                      Text('Nearest running bus within this distance is asked to help',
                          style: Ym.t(11.5, color: Ym.grey)),
                    ],
                  ),
                ),
                Text('$_radius km', style: Ym.h(16, color: Ym.amberDark)),
                const SizedBox(width: 6),
                const Icon(Icons.edit_rounded, size: 17, color: Ym.grey),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        YmFadeSlide(
          index: 1,
          child: YmCard(
            onTap: _editStopRadius,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const YmIconBadge(icon: Icons.pin_drop_outlined, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stop arrival distance', style: Ym.h(15)),
                      Text('A stop is marked reached when the bus is this close',
                          style: Ym.t(11.5, color: Ym.grey)),
                    ],
                  ),
                ),
                Text('$_stopRadius m', style: Ym.h(16, color: Ym.amberDark)),
                const SizedBox(width: 6),
                const Icon(Icons.edit_rounded, size: 17, color: Ym.grey),
              ],
            ),
          ),
        ),
        if (_noCapacity > 0) ...[
          const SizedBox(height: 14),
          YmFadeSlide(
            index: 1,
            child: YmCard(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdminBusesScreen())),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const YmIconBadge(
                      icon: Icons.warning_amber_rounded, color: Ym.red, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        '$_noCapacity bus${_noCapacity == 1 ? '' : 'es'} without capacity. They cannot be a rescue bus. Tap to set it.',
                        style: Ym.t(12.5, color: Ym.red, w: FontWeight.w700)),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Ym.grey),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        YmSectionTitle('SOS alerts',
            trailing: _sos.where((e) => e['status'] != 'resolved').isEmpty
                ? null
                : YmChip(
                    '${_sos.where((e) => e['status'] != 'resolved').length} active',
                    color: Ym.red,
                    solid: true)),
        if (_sos.isEmpty)
          YmCard(
              child: Text('No SOS alerts. Alerts from students and drivers appear here.',
                  style: Ym.t(13.5, color: Ym.grey)))
        else
          for (var i = 0; i < _sos.length; i++)
            YmFadeSlide(index: i, child: _sosCard(_sos[i])),
        const SizedBox(height: 24),
        YmSectionTitle('Breakdown rescues',
            trailing: _rescues.isEmpty
                ? null
                : YmChip('${_rescues.length}', color: Ym.red)),
        if (_rescues.isEmpty)
          YmCard(
              child: Text('No breakdowns reported.',
                  style: Ym.t(13.5, color: Ym.grey)))
        else
          for (var i = 0; i < _rescues.length; i++)
            YmFadeSlide(index: i + 1, child: _rescueCard(_rescues[i])),
        const SizedBox(height: 24),
        const YmSectionTitle('Notifications'),
        if (_notifications.isEmpty)
          YmCard(
              child: Text('Nothing yet. SOS alerts and driver issues appear here.',
                  style: Ym.t(13.5, color: Ym.grey)))
        else
          for (final n in _notifications) _notificationTile(n),
      ],
    );
  }

  Widget _rescueCard(Map<String, dynamic> r) {
    final status = r['status']?.toString() ?? '';
    final broken = _busNumbers[r['broken_bus_id']?.toString()] ?? 'a bus';
    final rescue = _busNumbers[r['rescue_bus_id']?.toString()];
    final driver = _driverNames[r['rescue_driver_id']?.toString()];
    final issue = _issues[r['issue_id']?.toString()];
    final brokenDriver = _driverNames[issue?['driver_id']?.toString()];
    final at = parseUtc(r['created_at']);

    final (label, color) = switch (status) {
      'accepted' => ('Accepted', Ym.green),
      'declined' => ('Declined', Ym.amberDark),
      'completed' => ('Completed', Ym.green),
      'cancelled' => ('Cancelled', Ym.grey),
      'no_bus' => ('No bus nearby', Ym.red),
      _ => ('Waiting for answer', Ym.amberDark),
    };
    final open = ['offered', 'accepted', 'declined', 'no_bus'].contains(status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: YmCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                YmIconBadge(icon: Icons.build_circle_outlined, color: color, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bus $broken broke down', style: Ym.h(15)),
                      if (brokenDriver != null)
                        Text('Driver $brokenDriver', style: Ym.t(12, color: Ym.grey)),
                    ],
                  ),
                ),
                YmChip(label, color: color),
              ],
            ),
            if ((issue?['description'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(issue!['description'].toString(),
                    style: Ym.t(12.5, color: Ym.grey)),
              ),
            if (rescue != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Rescue bus: $rescue'
                  '${driver != null ? '  •  Driver $driver' : ''}'
                  '${r['distance_km'] != null ? '  •  ${r['distance_km']} km away' : ''}',
                  style: Ym.t(12.5, w: FontWeight.w700),
                ),
              ),
            if (status == 'no_bus')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                    'No other running bus within $_radius km has free seats. Arrange a replacement, or try again once a bus is closer.',
                    style: Ym.t(12.5, color: Ym.red, w: FontWeight.w600)),
              ),
            if (at != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${fmtDate(at)}  •  ${fmtClock(at)}',
                    style: Ym.t(11, color: Ym.grey)),
              ),
            if (open) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _action('Assign a bus', Icons.touch_app_rounded, Ym.green,
                      () => _assignBus(r)),
                  _action('Find another bus', Icons.autorenew_rounded, Ym.blue,
                      () => _rpc('admin_reassign_rescue', r['id'].toString(),
                          'Looking for another bus…')),
                  if (status != 'declined')
                    _action('Cancel', Icons.close_rounded, Ym.red,
                        () => _rpc('admin_cancel_rescue', r['id'].toString(),
                            'Rescue cancelled.')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _action(String label, IconData icon, Color color, VoidCallback onTap) =>
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

  Widget _notificationTile(Map<String, dynamic> n) {
    final sos = n['type'] == 'emergency';
    final c = sos ? Ym.red : Ym.blue;
    final at = parseUtc(n['created_at']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: c, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n['title']?.toString() ?? '', style: Ym.h(14)),
          const SizedBox(height: 3),
          Text(n['message']?.toString() ?? '', style: Ym.t(12.5, color: Ym.grey)),
          if (at != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${fmtDate(at)}  •  ${fmtClock(at)}',
                  style: Ym.t(11, color: Ym.grey)),
            ),
        ],
      ),
    );
  }
}