import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

class _C {
  static const navy = Color(0xFF0F1B4D);
  static const orange = Color(0xFFFF9800);
  static const grey = Color(0xFF8E94A9);
  static const red = Color(0xFFE53935);
}

/// "Mark Absent": tells the driver the student will not use the bus on a day.
/// Saved in `attendance_notifications`; a database trigger notifies the driver.
Future<void> showMarkAbsentSheet(BuildContext context) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _MarkAbsentSheet(),
  );
  if (done == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Marked absent. Your driver has been notified.'),
      backgroundColor: _C.navy,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

class _MarkAbsentSheet extends StatefulWidget {
  const _MarkAbsentSheet();

  @override
  State<_MarkAbsentSheet> createState() => _MarkAbsentSheetState();
}

class _MarkAbsentSheetState extends State<_MarkAbsentSheet> {
  final _sb = Supabase.instance.client;
  final _reason = TextEditingController();

  late DateTime _date = _today();
  bool _saving = false;
  String? _error;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _isToday => _date == _today();
  bool get _isTomorrow =>
      _date == _today().add(const Duration(days: 1));

  Future<void> _pick() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _today(),
      lastDate: _today().add(const Duration(days: 60)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ctx = await StudentContext.load();
      await _sb.from('attendance_notifications').upsert({
        'student_id': ctx.student['id'],
        'route_id': ctx.routeId,
        'absent_date': dateKey(_date),
        'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        'status': 'absent',
      }, onConflict: 'student_id,absent_date');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not save: $e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          22, 16, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
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
            const SizedBox(height: 16),
            Row(
              children: [
                const YmIconBadge(
                    icon: Icons.event_busy_rounded, color: Ym.purple, size: 50),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mark Absent', style: Ym.h(20)),
                      const SizedBox(height: 3),
                      Text('Your driver will know you will not board that day.',
                          style: Ym.t(12.5, color: Ym.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Which day?', style: Ym.t(12, color: Ym.grey, w: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _dayPill('Today', Icons.today_rounded, _isToday,
                    () => setState(() => _date = _today())),
                _dayPill(
                    'Tomorrow',
                    Icons.event_rounded,
                    _isTomorrow,
                    () => setState(
                        () => _date = _today().add(const Duration(days: 1)))),
                _dayPill(
                    _isToday || _isTomorrow ? 'Pick a date' : fmtDate(_date),
                    Icons.calendar_month_rounded,
                    !(_isToday || _isTomorrow),
                    _pick),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _reason,
              maxLines: 2,
              style: Ym.t(14),
              decoration: InputDecoration(
                hintText: 'Reason (optional)',
                hintStyle: Ym.t(14, color: Ym.grey),
                filled: true,
                fillColor: const Color(0xFFF8F9FB),
                contentPadding: const EdgeInsets.all(16),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Ym.amber, width: 1.6)),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: Ym.t(12.5, color: Ym.red)),
              ),
            const SizedBox(height: 18),
            YmButton(
              label: 'Mark absent on ${fmtDate(_date)}',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayPill(String label, IconData icon, bool selected, VoidCallback onTap) =>
      YmPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Ym.amber : Ym.creamTop,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? Ym.amberDark : Ym.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Ym.navy),
              const SizedBox(width: 7),
              Text(label,
                  style: Ym.t(13,
                      w: selected ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
        ),
      );
}