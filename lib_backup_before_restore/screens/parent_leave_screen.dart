import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';
import '../widgets/parent_child_picker.dart';

/// "My child is not riding the bus." The parent picks the days (today, tomorrow
/// or up to a week). It is saved exactly like a student's Mark Absent
/// (`attendance_notifications`), so the driver is told and the bus does not wait
/// at that stop.
class ParentLeaveScreen extends StatefulWidget {
  const ParentLeaveScreen({
    super.key,
    required this.children,
    required this.selected,
  });

  final List<Map<String, dynamic>> children;
  final int selected;

  @override
  State<ParentLeaveScreen> createState() => _ParentLeaveScreenState();
}

class _ParentLeaveScreenState extends State<ParentLeaveScreen> {
  final _sb = Supabase.instance.client;
  final _reason = TextEditingController();

  late int _sel = widget.selected;
  late DateTime _from = _today();
  late DateTime _to = _today();
  String _quick = 'today'; // today | tomorrow | pick
  bool _saving = false;
  bool _loading = true;
  List<Map<String, dynamic>> _upcoming = [];

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _loadUpcoming();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _childName(dynamic id) {
    for (final c in widget.children) {
      if (c['id'].toString() == id?.toString()) {
        return (c['student_name'] ?? '').toString();
      }
    }
    return '';
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Ym.red : null,
      ));
  }

  Future<void> _loadUpcoming() async {
    setState(() => _loading = true);
    try {
      final ids = [for (final c in widget.children) c['id'].toString()];
      final rows = await _sb
          .from('attendance_notifications')
          .select()
          .inFilter('student_id', ids)
          .gte('absent_date', dateKey(_today()))
          .order('absent_date', ascending: true);
      if (!mounted) return;
      setState(() {
        _upcoming = [
          for (final r in rows)
            if ((r['status'] ?? 'absent').toString() == 'absent')
              Map<String, dynamic>.from(r),
        ];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Could not load upcoming leave: $e', error: true);
    }
  }

  void _setQuick(String q) {
    final t = _today();
    setState(() {
      _quick = q;
      if (q == 'today') {
        _from = t;
        _to = t;
      } else if (q == 'tomorrow') {
        _from = t.add(const Duration(days: 1));
        _to = _from;
      }
    });
  }

  Future<void> _pick() async {
    final t = _today();
    final r = await showDateRangePicker(
      context: context,
      firstDate: t,
      lastDate: t.add(const Duration(days: 60)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'Choose the days (up to 7)',
    );
    if (r == null) return;
    if (r.end.difference(r.start).inDays > 6) {
      _snack('Please choose 7 days or fewer at a time.', error: true);
      return;
    }
    setState(() {
      _quick = 'pick';
      _from = r.start;
      _to = r.end;
    });
  }

  int get _dayCount => _to.difference(_from).inDays + 1;

  Future<void> _save() async {
    final child = widget.children[_sel];
    final routeId = child['route_id']?.toString();
    if (routeId == null || routeId.isEmpty) {
      _snack('${child['student_name']} has no bus route yet, so there is nothing to cancel.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final reason = _reason.text.trim();
      final rows = [
        for (var i = 0; i < _dayCount; i++)
          {
            'student_id': child['id'],
            'route_id': routeId,
            'absent_date': dateKey(_from.add(Duration(days: i))),
            'reason': reason.isEmpty ? null : reason,
            'status': 'absent',
          },
      ];
      await _sb
          .from('attendance_notifications')
          .upsert(rows, onConflict: 'student_id,absent_date');
      _reason.clear();
      _snack('Saved. The driver has been told that '
          '${(child['student_name'] ?? 'your child').toString().split(' ').first} is not riding.');
      await _loadUpcoming();
    } catch (e) {
      _snack('Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    try {
      await _sb
          .from('attendance_notifications')
          .delete()
          .eq('student_id', r['student_id'])
          .eq('absent_date', r['absent_date']);
      _snack('Leave cancelled. The child is back on the bus list.');
      await _loadUpcoming();
    } catch (e) {
      _snack('Could not cancel: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _dayCount == 1
        ? fmtDate(_from)
        : '${fmtDate(_from)}  to  ${fmtDate(_to)}  ($_dayCount days)';

    return YmPage(
      title: 'Leave',
      subtitle: 'Tell the school your child is not riding',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          ParentChildPicker(
            children: widget.children,
            selected: _sel,
            onChanged: (i) => setState(() => _sel = i),
          ),
          YmCard(
            padding: const EdgeInsets.all(18),
            radius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Which days?', style: Ym.h(15)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final q in const [
                      ('today', 'Today'),
                      ('tomorrow', 'Tomorrow'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _pill(q.$2, _quick == q.$1, () => _setQuick(q.$1)),
                      ),
                    _pill('Pick dates', _quick == 'pick', _pick,
                        icon: Icons.date_range_rounded),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Ym.amber.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_busy_rounded,
                          size: 18, color: Ym.amberDark),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(label, style: Ym.t(13, w: FontWeight.w800))),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _reason,
                  maxLength: 120,
                  style: Ym.t(14),
                  decoration: InputDecoration(
                    hintText: 'Reason (optional), for example: fever',
                    hintStyle: Ym.t(13, color: Ym.grey),
                    filled: true,
                    fillColor: Ym.creamTop,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                YmButton(
                  label: 'Tell the driver',
                  icon: Icons.send_rounded,
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const YmSectionTitle('Upcoming leave'),
          if (_loading)
            const YmSkeleton(height: 80)
          else if (_upcoming.isEmpty)
            YmCard(
              child: Text('No leave planned. Your child is expected on the bus.',
                  style: Ym.t(13, color: Ym.grey)),
            )
          else
            for (final r in _upcoming)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: YmCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  radius: 20,
                  child: Row(
                    children: [
                      const YmIconBadge(
                          icon: Icons.event_busy_rounded,
                          color: Ym.amberDark,
                          size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                DateTime.tryParse('${r['absent_date']}') == null
                                    ? '${r['absent_date']}'
                                    : fmtDate(DateTime.parse('${r['absent_date']}')),
                                style: Ym.h(14)),
                            Text(
                              [
                                if (widget.children.length > 1)
                                  _childName(r['student_id']),
                                if ((r['reason'] ?? '').toString().isNotEmpty)
                                  r['reason'].toString(),
                              ].where((e) => e.isNotEmpty).join('  •  '),
                              style: Ym.t(12, color: Ym.grey),
                            ),
                          ],
                        ),
                      ),
                      YmPressable(
                        onTap: () => _cancel(r),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('Cancel',
                              style: Ym.t(12.5, color: Ym.red, w: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _pill(String text, bool on, VoidCallback onTap, {IconData? icon}) =>
      YmPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: on
                ? const LinearGradient(colors: [Ym.amber, Ym.amberDark])
                : null,
            color: on ? null : Ym.creamTop,
            border: Border.all(color: on ? Ym.amberDark : Ym.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: on ? Ym.navy : Ym.grey),
                const SizedBox(width: 5),
              ],
              Text(text,
                  style: Ym.t(12.5,
                      color: on ? Ym.navy : Ym.grey, w: FontWeight.w800)),
            ],
          ),
        ),
      );
}