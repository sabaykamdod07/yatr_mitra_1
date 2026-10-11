import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fee_receipt.dart';
import '../services/money.dart';
import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// Helpdesk (incharge): record a student's bus-fee payment.
///
/// Shows the live fee status for the current academic year, lets the incharge
/// add a payment against any academic year, and cancel a wrong entry.
/// Nothing is hardcoded: years come from `academic_years`, the fee from the
/// route (or the student's custom fee), and status from `student_fee_status`.
Future<void> showRecordPaymentSheet(
  BuildContext context,
  Map<String, dynamic> student, {
  VoidCallback? onDone,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RecordPaymentSheet(student: student),
  );
  onDone?.call();
}

class _RecordPaymentSheet extends StatefulWidget {
  const _RecordPaymentSheet({required this.student});
  final Map<String, dynamic> student;

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  final _sb = Supabase.instance.client;
  final _amount = TextEditingController();
  final _method = TextEditingController();
  final _reference = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? _fee;
  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _payments = [];
  String? _yearId;

  static const _methodSuggestions = ['Cash', 'UPI', 'Card', 'Bank transfer', 'Cheque'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _method.dispose();
    _reference.dispose();
    super.dispose();
  }

  String get _sid => widget.student['id'].toString();

  Future<void> _load({bool keepForm = false}) async {
    if (!keepForm) setState(() => _loading = true);
    try {
      final fee = await _sb
          .from('student_fee_status')
          .select()
          .eq('student_id', _sid)
          .maybeSingle();

      final inst = widget.student['institution_id'];
      final years = await _sb
          .from('academic_years')
          .select()
          .eq('institution_id', inst)
          .order('start_date', ascending: false);

      final payments = await _sb
          .from('payments')
          .select('*, academic_years(label)')
          .eq('student_id', _sid)
          .order('paid_on', ascending: false)
          .limit(30);

      if (!mounted) return;
      setState(() {
        _fee = fee;
        _years = List<Map<String, dynamic>>.from(years);
        _payments = List<Map<String, dynamic>>.from(payments);
        _yearId ??= fee?['academic_year_id']?.toString() ??
            (_years.isNotEmpty ? _years.first['id'].toString() : null);
        if (!keepForm) {
          final due = num.tryParse('${fee?['fee_due']}');
          final paid = num.tryParse('${fee?['amount_paid']}') ?? 0;
          if (due != null && due - paid > 0) {
            _amount.text = (due - paid).round().toString();
          }
        }
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

  Future<void> _save() async {
    final amount = parseMoney(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount received, for example 15000 or 15,000.');
      return;
    }
    if (_yearId == null) {
      setState(() => _error =
          'No academic year exists yet. Ask the admin to add one under Fees & Years.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _sb.from('payments').insert({
        'institution_id': widget.student['institution_id'],
        'student_id': _sid,
        'academic_year_id': _yearId,
        'amount': amount,
        'status': 'paid',
        'description': 'Bus Fee',
        'method': _method.text.trim().isEmpty ? null : _method.text.trim(),
        'reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        'recorded_by': _sb.auth.currentUser?.id,
      });
      _amount.clear();
      _reference.clear();
      await _load(keepForm: true);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment recorded.'),
          backgroundColor: Ym.green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('PostgrestException', '');
          _saving = false;
        });
      }
    }
  }

  Future<void> _cancel(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel this payment?'),
        content: const Text(
            'It will no longer count towards the fee. Use this only for a wrong entry.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Ym.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel payment',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _sb.from('payments').update({'status': 'failed'}).eq('id', p['id']);
      await _load(keepForm: true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _money(num? v) {
    if (v == null) return '-';
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '₹$b';
  }

  (String, Color) _status(String? s) => switch (s) {
        'paid' => ('Paid', Ym.green),
        'partial' => ('Partial', Ym.amberDark),
        'fee_not_set' => ('Fee not set', Ym.grey),
        'no_year' => ('No active year', Ym.grey),
        _ => ('Unpaid', Ym.red),
      };

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: Ym.grey),
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: _loading
          ? const SizedBox(
              height: 220, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(child: _content()),
    );
  }

  Widget _content() {
    final status = _fee?['fee_status']?.toString();
    final (label, color) = _status(status);
    final due = num.tryParse('${_fee?['fee_due']}');
    final paid = num.tryParse('${_fee?['amount_paid']}') ?? 0;
    final validTill = DateTime.tryParse('${_fee?['valid_till']}');

    return Column(
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
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Record payment', style: Ym.h(19)),
                  Text(widget.student['student_name']?.toString() ?? '',
                      style: Ym.t(13, color: Ym.grey)),
                ],
              ),
            ),
            YmChip(label, color: color, solid: status == 'paid'),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Ym.creamTop,
            borderRadius: BorderRadius.circular(18),
          ),
          child: status == 'no_year'
              ? Text(
                  'No academic year is active today. Ask the admin to add one under Fees & Years.',
                  style: Ym.t(12.5, color: Ym.red, w: FontWeight.w600))
              : Row(
                  children: [
                    Expanded(child: _stat('Year', _fee?['academic_year']?.toString() ?? '-')),
                    Expanded(child: _stat('Fee', _money(due))),
                    Expanded(child: _stat('Paid', _money(paid))),
                    Expanded(
                        child: _stat(
                            'Balance',
                            due == null
                                ? '-'
                                : _money((due - paid).clamp(0, double.infinity)))),
                  ],
                ),
        ),
        if (status == 'paid' && validTill != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Bus pass valid till ${fmtDate(validTill)}',
                style: Ym.t(12.5, color: Ym.green, w: FontWeight.w700)),
          ),
        if (status == 'fee_not_set')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                'The fee for this route is not set. Ask the admin to set it under Fees & Years.',
                style: Ym.t(12.5, color: Ym.red, w: FontWeight.w600)),
          ),
        const SizedBox(height: 18),
        Text('New payment', style: Ym.h(15)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _yearId,
          isExpanded: true,
          decoration: _deco('Pays for academic year', Icons.event_note_rounded),
          items: [
            for (final y in _years)
              DropdownMenuItem(
                value: y['id'].toString(),
                child: Text(y['label']?.toString() ?? ''),
              ),
          ],
          onChanged: (v) => setState(() => _yearId = v),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _deco('Amount received (₹)', Icons.currency_rupee_rounded),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _method,
          decoration: _deco('Payment method (optional)', Icons.payments_outlined),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final m in _methodSuggestions)
              ActionChip(
                label: Text(m, style: Ym.t(11.5)),
                onPressed: () => setState(() => _method.text = m),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _reference,
          decoration: _deco('Receipt / reference no. (optional)', Icons.tag_rounded),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!,
                style: Ym.t(12.5, color: Ym.red, w: FontWeight.w600)),
          ),
        const SizedBox(height: 14),
        YmButton(
          label: 'Record payment',
          icon: Icons.check_rounded,
          loading: _saving,
          onPressed: _save,
        ),
        const SizedBox(height: 20),
        Text('Payments', style: Ym.h(15)),
        const SizedBox(height: 8),
        if (_payments.isEmpty)
          Text('No payments recorded yet.', style: Ym.t(13, color: Ym.grey))
        else
          for (final p in _payments) _paymentRow(p),
      ],
    );
  }

  Widget _stat(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: Ym.t(10.5, color: Ym.grey)),
          const SizedBox(height: 2),
          Text(v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ym.h(13.5)),
        ],
      );

  Widget _paymentRow(Map<String, dynamic> p) {
    final st = p['status']?.toString() ?? 'paid';
    final at = parseUtc(p['paid_on']);
    final year = (p['academic_years'] as Map?)?['label']?.toString();
    final cancelled = st != 'paid';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: cancelled ? Ym.grey.withOpacity(0.08) : Ym.green.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_money(num.tryParse('${p['amount']}')),
                    style: Ym.h(15,
                        color: cancelled ? Ym.grey : Ym.navy)),
                Text(
                  [
                    if (at != null) fmtDate(at),
                    if (year != null) year,
                    if (p['method'] != null) p['method'].toString(),
                    if (cancelled) 'Cancelled',
                  ].join('  •  '),
                  style: Ym.t(11.5, color: Ym.grey),
                ),
              ],
            ),
          ),
          if (!cancelled)
            IconButton(
              tooltip: 'Download receipt',
              icon: const Icon(Icons.receipt_long_rounded, color: Ym.amberDark, size: 20),
              onPressed: () => downloadFeeReceipt(context, p['id'].toString()),
            ),
          if (!cancelled)
            IconButton(
              tooltip: 'Cancel this payment',
              icon: const Icon(Icons.undo_rounded, color: Ym.red, size: 20),
              onPressed: () => _cancel(p),
            ),
        ],
      ),
    );
  }
}