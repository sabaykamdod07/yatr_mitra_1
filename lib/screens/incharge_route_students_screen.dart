import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// For the IN-CHARGE: the students of their route, read only. Name, stop, phone
/// numbers and whether the bus pass is valid. (To check one pass in person, use
/// Scan Pass.)
class InchargeRouteStudentsScreen extends StatefulWidget {
  const InchargeRouteStudentsScreen({super.key});

  @override
  State<InchargeRouteStudentsScreen> createState() => _InchargeRouteStudentsScreenState();
}

class _InchargeRouteStudentsScreenState extends State<InchargeRouteStudentsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _sb.rpc('incharge_route_students') as List;
      if (!mounted) return;
      setState(() {
        _items = [for (final r in rows) Map<String, dynamic>.from(r as Map)];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is PostgrestException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _call(String? phone) async {
    final p = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: p));
  }

  bool _valid(Map<String, dynamic> s) {
    if (s['fee_status'] != 'paid') return false;
    final d = DateTime.tryParse('${s['valid_till']}');
    if (d == null) return false;
    final n = DateTime.now();
    return !DateTime(d.year, d.month, d.day).isBefore(DateTime(n.year, n.month, n.day));
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? _items
        : _items.where((s) {
            return [s['student_name'], s['enrollment_no'], s['stop_name']]
                .any((v) => (v ?? '').toString().toLowerCase().contains(q));
          }).toList();
    final valid = _items.where(_valid).length;

    return YmPage(
      title: 'Route Students',
      subtitle: _loading ? null : '${_items.length} students, $valid with a valid pass',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              style: Ym.t(14),
              decoration: InputDecoration(
                hintText: 'Search by name, ID or stop',
                hintStyle: Ym.t(13, color: Ym.grey),
                prefixIcon: const Icon(Icons.search_rounded, color: Ym.grey),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: YmSkeletonList(count: 5, height: 84),
                  )
                : _error != null
                    ? YmEmpty(
                        icon: Icons.cloud_off_rounded,
                        color: Ym.red,
                        title: 'Could not load the students',
                        subtitle: _error,
                        action: YmButton(
                            label: 'Try again',
                            icon: Icons.refresh_rounded,
                            expanded: false,
                            onPressed: _load),
                      )
                    : RefreshIndicator(
                        color: Ym.amber,
                        onRefresh: _load,
                        child: list.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 50),
                                  YmEmpty(
                                    icon: Icons.groups_rounded,
                                    color: Ym.amberDark,
                                    title: 'No students found',
                                    subtitle: 'Students of your route appear here.',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                                itemCount: list.length,
                                itemBuilder: (_, i) => YmFadeSlide(
                                    index: i > 8 ? 8 : i, child: _tile(list[i])),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  /// today's attendance chips: boarded and got off, absent, on leave, or not boarded yet
  List<Widget> _attendChips(Map<String, dynamic> s, DateTime? boardedAt, DateTime? alightedAt) {
    if (boardedAt != null) {
      return [
        YmChip('Boarded ${fmtClock(boardedAt)}', color: Ym.navy, icon: Icons.login_rounded),
        if (alightedAt != null)
          YmChip('Got off ${fmtClock(alightedAt)}', color: Ym.blue, icon: Icons.logout_rounded),
      ];
    }
    if (s['absent_today'] == true) {
      return [
        s['absent_reason'] == 'on_leave'
            ? const YmChip('On leave today', color: Ym.amberDark, icon: Icons.event_busy_rounded)
            : const YmChip('Absent today', color: Ym.red, icon: Icons.event_busy_rounded),
      ];
    }
    if (s['trip_today'] == true) {
      return const [
        YmChip('Not boarded yet', color: Ym.grey, icon: Icons.person_off_outlined),
      ];
    }
    return const [];
  }

  Widget _tile(Map<String, dynamic> s) {
    final ok = _valid(s);
    final till = DateTime.tryParse('${s['valid_till']}');
    final boardedAt = parseUtc(s['boarded_at']);
    final alightedAt = parseUtc(s['alighted_at']);
    final name = (s['student_name'] ?? 'Student').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Ym.amber, Ym.amberDark]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(name[0].toUpperCase(), style: Ym.h(18, color: Ym.navy)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Ym.h(14.5)),
                  Text(
                    [
                      if ((s['enrollment_no'] ?? '').toString().isNotEmpty)
                        s['enrollment_no'].toString(),
                      if ((s['stop_name'] ?? '').toString().isNotEmpty)
                        s['stop_name'].toString(),
                    ].join('  •  '),
                    style: Ym.t(11.5, color: Ym.grey),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    YmChip(
                      ok
                          ? (till == null ? 'Pass valid' : 'Valid till ${fmtDate(till)}')
                          : 'No valid pass',
                      color: ok ? Ym.green : Ym.red,
                      icon: ok ? Icons.verified_rounded : Icons.block_rounded,
                    ),
                    // today's attendance, from the QR scans (only when a trip ran today)
                    ..._attendChips(s, boardedAt, alightedAt),
                  ]),
                ],
              ),
            ),
            if ((s['student_phone'] ?? '').toString().isNotEmpty)
              YmPressable(
                onTap: () => _call(s['student_phone']?.toString()),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: Ym.green.withOpacity(0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.call_rounded, color: Ym.green, size: 19),
                ),
              ),
          ],
        ),
      ),
    );
  }
}