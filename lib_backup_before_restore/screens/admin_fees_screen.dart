import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/money.dart';
import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// Admin: "Fees & Years".
///
///  * Academic years  - the admin enters them (label + start + end date).
///  * Route fees      - the fee for each route.
///  * Overview        - how many students are Paid / Partial / Unpaid right now.
///
/// Nothing is hardcoded. The incharge records payments (helpdesk); the pass of
/// every student is valid till the end of the academic year only while the full
/// fee for that year is paid, and resets by itself when the next year starts.
class AdminFeesScreen extends StatefulWidget {
  const AdminFeesScreen({super.key});

  @override
  State<AdminFeesScreen> createState() => _AdminFeesScreenState();
}

class _AdminFeesScreenState extends State<AdminFeesScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  String? _institutionId;
  Map<String, dynamic> _payCfg = {}; // the UPI ID, payee name and cash note
  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _routes = [];
  Map<String, int> _counts = {};

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
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in.');
      final inst = await _sb
          .from('institutions')
          .select('id, upi_id, upi_payee_name, cash_note')
          .eq('admin_id', uid)
          .maybeSingle();
      if (inst == null) throw Exception('No institution found for this admin.');
      final id = inst['id'].toString();

      final years = await _sb
          .from('academic_years')
          .select()
          .eq('institution_id', id)
          .order('start_date', ascending: false);

      final routes = await _sb
          .from('routes')
          .select('id, route_name, fee_amount')
          .eq('institution_id', id)
          .order('route_name', ascending: true);

      final status = await _sb
          .from('student_fee_status')
          .select('fee_status')
          .eq('institution_id', id);
      final counts = <String, int>{};
      for (final r in status) {
        final k = r['fee_status']?.toString() ?? 'unpaid';
        counts[k] = (counts[k] ?? 0) + 1;
      }

      if (!mounted) return;
      setState(() {
        _institutionId = id;
        _payCfg = Map<String, dynamic>.from(inst);
        _years = List<Map<String, dynamic>>.from(years);
        _routes = List<Map<String, dynamic>>.from(routes);
        _counts = counts;
        _loading = false;
      });
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

  DateTime? _d(dynamic v) => DateTime.tryParse('$v');

  bool _isCurrent(Map<String, dynamic> y) {
    final s = _d(y['start_date']);
    final e = _d(y['end_date']);
    if (s == null || e == null) return false;
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return !today.isBefore(s) && !today.isAfter(e);
  }

  // ───────────────────────── academic years ─────────────────────────

  Future<void> _addYear() async {
    final label = TextEditingController();
    DateTime? start;
    DateTime? end;
    String? error;
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModal) {
          Future<void> pick(bool isStart) async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: dialogContext,
              initialDate: (isStart ? start : end) ?? now,
              firstDate: DateTime(now.year - 3),
              lastDate: DateTime(now.year + 6),
            );
            if (d != null) setModal(() => isStart ? start = d : end = d);
          }

          Widget dateTile(String title, DateTime? v, bool isStart) =>
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => pick(isStart),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFFF8F9FB),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 18, color: Ym.grey),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            v == null ? title : '$title: ${fmtDate(v)}',
                            style: Ym.t(13.5,
                                color: v == null ? Ym.grey : Ym.navy,
                                w: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              );

          Future<void> save() async {
            final l = label.text.trim();
            if (l.isEmpty || start == null || end == null) {
              setModal(() => error = 'Enter a name and pick both dates.');
              return;
            }
            if (!end!.isAfter(start!)) {
              setModal(() => error = 'The end date must be after the start date.');
              return;
            }
            setModal(() {
              saving = true;
              error = null;
            });
            try {
              await _sb.from('academic_years').insert({
                'institution_id': _institutionId,
                'label': l,
                'start_date': dateKey(start!),
                'end_date': dateKey(end!),
              });
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _snack('Academic year added.');
              await _load();
            } catch (e) {
              var msg = e.toString();
              if (e is PostgrestException) msg = e.message;
              if (msg.contains('duplicate key')) {
                msg = 'An academic year with this name already exists.';
              }
              setModal(() {
                error = msg;
                saving = false;
              });
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Add academic year', style: Ym.h(18)),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: label,
                    decoration: InputDecoration(
                      labelText: 'Name (for example 2026–27)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  dateTile('Start date', start, true),
                  const SizedBox(height: 10),
                  dateTile('End date', end, false),
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
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: saving ? null : save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Ym.amber,
                  foregroundColor: Ym.navy,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Add year'),
              ),
            ],
          );
        },
      ),
    );
    label.dispose();
  }

  Future<void> _deleteYear(Map<String, dynamic> y) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete academic year?'),
        content: Text('${y['label']} will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Ym.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _sb.from('academic_years').delete().eq('id', y['id']);
      _snack('Academic year deleted.');
      await _load();
    } on PostgrestException catch (e) {
      _snack(
          e.code == '23503'
              ? 'This year has payments recorded, so it cannot be deleted.'
              : e.message,
          error: true);
    } catch (e) {
      _snack('Could not delete: $e', error: true);
    }
  }

  // ───────────────────────── route fees ─────────────────────────

  Future<void> _editFee(Map<String, dynamic> r) async {
    final c = TextEditingController(
        text: r['fee_amount'] == null
            ? ''
            : (num.tryParse('${r['fee_amount']}')?.round().toString() ?? ''));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Fee for ${r['route_name']}', style: Ym.h(17)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          // digits, commas, a dot and spaces: so 15000 and 15,000 both work
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\s]'))],
          decoration: InputDecoration(
            labelText: 'Fee per academic year (₹)',
            helperText: 'Type 15000 or 15,000. Leave empty to mark the fee as not set',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final text = c.text.trim();
    c.dispose();
    if (saved != true) return;
    final value = text.isEmpty ? null : parseMoney(text);
    if (text.isNotEmpty && value == null) {
      _snack('Enter a valid amount, for example 15000 or 15,000.', error: true);
      return;
    }
    try {
      await _sb.from('routes').update({'fee_amount': value}).eq('id', r['id']);
      _snack('Fee saved.');
      await _load();
    } catch (e) {
      _snack('Could not save: $e', error: true);
    }
  }

  String _money(num? v) {
    if (v == null) return 'Not set';
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '₹$b';
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Fees & Years',
      subtitle: 'Academic years and route fees',
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
                  color: Ym.amber, onRefresh: _load, child: _body()),
    );
  }

  Widget _paymentCard() {
    final upi = (_payCfg['upi_id'] ?? '').toString().trim();
    final payee = (_payCfg['upi_payee_name'] ?? '').toString().trim();
    final cash = (_payCfg['cash_note'] ?? '').toString().trim();
    final set = upi.isNotEmpty;

    return YmCard(
      padding: const EdgeInsets.all(16),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              YmIconBadge(
                  icon: Icons.qr_code_2_rounded, color: set ? Ym.green : Ym.amberDark, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(set ? upi : 'UPI ID not set', style: Ym.h(15)),
                    Text(
                        set
                            ? (payee.isEmpty ? 'Shown to payers under the school name' : 'Shown to payers as $payee')
                            : 'Parents see a DEMO QR until you add the school\'s UPI ID',
                        style: Ym.t(11.5, color: set ? Ym.grey : Ym.amberDark)),
                  ],
                ),
              ),
              YmPressable(
                onTap: _editPaymentSettings,
                child: const YmChip('Edit', color: Ym.amberDark, icon: Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.payments_outlined, size: 17, color: Ym.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cash.isEmpty ? 'Cash counter note: not set' : 'Cash counter: $cash',
                  style: Ym.t(12.5, color: Ym.grey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editPaymentSettings() async {
    final upi = TextEditingController(text: (_payCfg['upi_id'] ?? '').toString());
    final payee = TextEditingController(text: (_payCfg['upi_payee_name'] ?? '').toString());
    final cash = TextEditingController(text: (_payCfg['cash_note'] ?? '').toString());
    String? error;

    InputDecoration deco(String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('How parents pay', style: Ym.h(18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Use the school\'s own UPI ID, ideally a business account. Only you can change it, '
                  'and the help desk is told every time it changes. Money paid by UPI goes to this ID.',
                  style: Ym.t(12.5, color: Ym.grey).copyWith(height: 1.45),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: upi,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  decoration: deco('UPI ID', 'for example school@okaxis'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: payee,
                  maxLength: 60,
                  decoration: deco('Name shown to the payer', 'for example Sai Vidya Institute'),
                ),
                TextField(
                  controller: cash,
                  maxLength: 200,
                  decoration: deco('Cash counter note (optional)', 'for example Fee counter, Admin block, 9 AM to 4 PM'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 6),
                  Text(error!, style: Ym.t(12.5, color: Ym.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final u = upi.text.trim();
                if (u.isNotEmpty &&
                    !RegExp(r'^[A-Za-z0-9._\-]{2,64}@[A-Za-z][A-Za-z0-9]{1,30}$').hasMatch(u)) {
                  setD(() => error =
                      'That does not look like a UPI ID. It looks like name@bank, for example school@okaxis.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text('Save', style: Ym.t(14, color: Ym.amberDark, w: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );

    final u = upi.text.trim();
    final n = payee.text.trim();
    final c = cash.text.trim();
    upi.dispose();
    payee.dispose();
    cash.dispose();
    if (saved != true) return;

    try {
      await _sb.rpc('set_payment_info',
          params: {'p_upi_id': u, 'p_payee': n, 'p_cash_note': c});
      _snack(u.isEmpty ? 'UPI ID cleared. Parents see the demo QR.' : 'Payment details saved.');
      await _load();
    } on PostgrestException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('Could not save: $e', error: true);
    }
  }

  Widget _body() {
    Map<String, dynamic>? current;
    for (final y in _years) {
      if (_isCurrent(y)) {
        current = y;
        break;
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
      children: [
        YmFadeSlide(index: 0, child: _overview(current)),
        const SizedBox(height: 24),
        const YmSectionTitle('How parents pay'),
        _paymentCard(),
        const SizedBox(height: 24),
        YmFadeSlide(
          index: 1,
          child: YmSectionTitle(
            'Academic years',
            trailing: YmPressable(
              onTap: _addYear,
              child: const YmChip('Add year',
                  color: Ym.amberDark, icon: Icons.add_rounded),
            ),
          ),
        ),
        if (_years.isEmpty)
          YmCard(
            child: Text(
                'No academic year yet. Add one so payments and bus passes can work.',
                style: Ym.t(13.5, color: Ym.grey)),
          )
        else
          for (var i = 0; i < _years.length; i++)
            YmFadeSlide(index: i + 2, child: _yearTile(_years[i])),
        const SizedBox(height: 24),
        const YmSectionTitle('Route fees'),
        if (_routes.isEmpty)
          YmCard(
              child: Text('No routes yet. Upload routes first.',
                  style: Ym.t(13.5, color: Ym.grey)))
        else
          for (final r in _routes) _routeTile(r),
      ],
    );
  }

  Widget _overview(Map<String, dynamic>? current) {
    Widget stat(String k, String key, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.75),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text('${_counts[key] ?? 0}', style: Ym.h(22, color: c)),
                const SizedBox(height: 2),
                Text(k, style: Ym.t(11, color: Ym.grey)),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6E3), Color(0xFFFFE3AE)],
        ),
        border: Border.all(color: Ym.amber.withOpacity(0.45)),
        boxShadow: Ym.shadow(Ym.amberDark, 0.22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current academic year',
              style: Ym.t(12, color: Ym.grey, w: FontWeight.w700)),
          const SizedBox(height: 4),
          if (current == null)
            Text('None active today', style: Ym.h(20, color: Ym.red))
          else ...[
            Text(current['label']?.toString() ?? '', style: Ym.h(24)),
            Text(
                '${fmtDate(_d(current['start_date'])!)}  –  ${fmtDate(_d(current['end_date'])!)}',
                style: Ym.t(12.5, color: Ym.grey)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              stat('Paid', 'paid', Ym.green),
              const SizedBox(width: 8),
              stat('Partial', 'partial', Ym.amberDark),
              const SizedBox(width: 8),
              stat('Unpaid', 'unpaid', Ym.red),
              const SizedBox(width: 8),
              stat('No fee set', 'fee_not_set', Ym.grey),
            ],
          ),
          if (current == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  'Until a year is active, nobody can have a valid bus pass.',
                  style: Ym.t(12, color: Ym.red, w: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _yearTile(Map<String, dynamic> y) {
    final current = _isCurrent(y);
    final s = _d(y['start_date']);
    final e = _d(y['end_date']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: [
            YmIconBadge(
                icon: Icons.event_note_rounded,
                color: current ? Ym.green : Ym.grey,
                size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                          child: Text(y['label']?.toString() ?? '',
                              style: Ym.h(15.5))),
                      if (current) ...[
                        const SizedBox(width: 8),
                        const YmChip('Current', color: Ym.green),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                      s == null || e == null
                          ? ''
                          : '${fmtDate(s)}  –  ${fmtDate(e)}',
                      style: Ym.t(12, color: Ym.grey)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Ym.red, size: 21),
              onPressed: () => _deleteYear(y),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeTile(Map<String, dynamic> r) {
    final fee = num.tryParse('${r['fee_amount']}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        onTap: () => _editFee(r),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const YmIconBadge(icon: Icons.alt_route_rounded, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(r['route_name']?.toString() ?? '',
                  style: Ym.h(15)),
            ),
            fee == null
                ? const YmChip('Not set', color: Ym.red)
                : Text(_money(fee), style: Ym.h(16)),
            const SizedBox(width: 8),
            const Icon(Icons.edit_rounded, size: 18, color: Ym.grey),
          ],
        ),
      ),
    );
  }
}