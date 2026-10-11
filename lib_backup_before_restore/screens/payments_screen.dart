import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// Bus fee for the CURRENT academic year + payment history.
///
/// Nothing is hardcoded: the academic year, the fee and every payment come from
/// the database (`student_fee_status` view). The incharge records payments; when
/// a new academic year starts the student automatically shows as Unpaid again.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  StudentContext? _ctx;
  Map<String, dynamic>? _fee;
  List<Map<String, dynamic>> _payments = [];

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
      final ctx = await StudentContext.load();
      final sid = ctx.student['id'];

      final fee = await _sb
          .from('student_fee_status')
          .select()
          .eq('student_id', sid)
          .maybeSingle();

      final rows = await _sb
          .from('payments')
          .select('*, academic_years(label)')
          .eq('student_id', sid)
          .order('paid_on', ascending: false)
          .limit(40);

      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _fee = fee;
        _payments = List<Map<String, dynamic>>.from(rows);
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

  num? _n(dynamic v) => v == null ? null : num.tryParse(v.toString());

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

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Payments',
      subtitle: _fee?['academic_year']?.toString(),
      child: _loading
          ? const YmSkeletonList(count: 3, height: 130)
          : _error != null
              ? YmEmpty(
                  icon: Iconsax.warning_2,
                  color: Ym.red,
                  title: 'Could not load payments',
                  subtitle: _error,
                  action: YmButton(
                      label: 'Try again',
                      expanded: false,
                      icon: Icons.refresh_rounded,
                      onPressed: _load),
                )
              : RefreshIndicator(
                  color: Ym.amber,
                  onRefresh: _load,
                  child: _body(),
                ),
    );
  }

  Widget _body() {
    final status = _fee?['fee_status']?.toString();
    final (label, color) = _status(status);
    final due = _n(_fee?['fee_due']);
    final paid = _n(_fee?['amount_paid']) ?? 0;
    final balance = due == null ? null : (due - paid).clamp(0, double.infinity);
    final progress =
        (due == null || due == 0) ? 0.0 : (paid / due).clamp(0, 1).toDouble();
    final validTill = DateTime.tryParse('${_fee?['valid_till']}');
    final routeName = _ctx?.route?['route_name']?.toString() ?? '-';

    String? notice;
    if (status == 'no_year') {
      notice = 'No academic year is active today. Please contact your incharge.';
    } else if (status == 'fee_not_set') {
      notice =
          'The fee for your route has not been set yet. Please contact your incharge.';
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
      children: [
        YmFadeSlide(
          index: 0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF6E3), Color(0xFFFFE3AE)],
              ),
              border: Border.all(color: Ym.amber.withOpacity(0.45)),
              boxShadow: Ym.shadow(Ym.amberDark, 0.25),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const YmIconBadge(icon: Iconsax.bus, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bus Fee', style: Ym.h(17)),
                          Text(routeName, style: Ym.t(12.5, color: Ym.grey)),
                        ],
                      ),
                    ),
                    YmChip(label, color: color, solid: status == 'paid'),
                  ],
                ),
                const SizedBox(height: 18),
                Text(due == null ? '—' : _money(due), style: Ym.h(36)),
                Text(
                    _fee?['academic_year'] == null
                        ? 'Fee for the current year'
                        : 'Fee for ${_fee!['academic_year']}',
                    style: Ym.t(12.5, color: Ym.grey)),
                if (due != null) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: Colors.white.withOpacity(0.7),
                      valueColor: AlwaysStoppedAnimation<Color>(
                          status == 'paid' ? Ym.green : Ym.amberDark),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _miniStat('Paid', _money(paid), Ym.green)),
                      Expanded(
                          child: _miniStat('Balance', _money(balance), Ym.red)),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          status == 'paid'
                              ? Icons.verified_rounded
                              : Icons.lock_outline_rounded,
                          size: 18,
                          color: status == 'paid' ? Ym.green : Ym.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status == 'paid' && validTill != null
                              ? 'Bus pass valid till ${fmtDate(validTill)}'
                              : 'Bus pass not valid until the full fee is paid',
                          style: Ym.t(12.5,
                              color: status == 'paid' ? Ym.green : Ym.red,
                              w: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (notice != null) ...[
          const SizedBox(height: 14),
          YmFadeSlide(
            index: 1,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Ym.grey.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(notice, style: Ym.t(12.5, color: Ym.navy)),
            ),
          ),
        ],
        const SizedBox(height: 26),
        const YmSectionTitle('Recent Transactions'),
        if (_payments.isEmpty)
          YmCard(
            child: Text('No payments recorded yet.',
                style: Ym.t(13.5, color: Ym.grey)),
          )
        else
          for (var i = 0; i < _payments.length; i++)
            YmFadeSlide(index: i + 2, child: _paymentTile(_payments[i])),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Ym.blue.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Ym.blue, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    'Fees are paid at your institution. For any payment related queries, contact your in-charge.',
                    style: Ym.t(12.5)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String k, String v, Color c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: Ym.t(11.5, color: Ym.grey)),
          const SizedBox(height: 2),
          Text(v, style: Ym.h(17, color: c)),
        ],
      );

  Widget _paymentTile(Map<String, dynamic> p) {
    final at = parseUtc(p['paid_on']);
    final st = p['status']?.toString() ?? 'paid';
    final (label, color) = switch (st) {
      'paid' => ('Paid', Ym.green),
      'pending' => ('Pending', Ym.amberDark),
      _ => ('Cancelled', Ym.grey),
    };
    final year = (p['academic_years'] as Map?)?['label']?.toString();
    final method = p['method']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            YmIconBadge(icon: Icons.receipt_long_rounded, color: color, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['description']?.toString() ?? 'Bus Fee',
                      style: Ym.h(14.5)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (at != null) fmtDate(at),
                      if (year != null) year,
                      if (method != null && method.isNotEmpty) method,
                    ].join('  •  '),
                    style: Ym.t(11.5, color: Ym.grey),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_money(_n(p['amount'])),
                    style: Ym.h(15, color: st == 'paid' ? Ym.navy : Ym.grey)),
                const SizedBox(height: 4),
                YmChip(label, color: color),
              ],
            ),
          ],
        ),
      ),
    );
  }
}