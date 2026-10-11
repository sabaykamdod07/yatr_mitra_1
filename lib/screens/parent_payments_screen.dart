import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fee_receipt.dart';
import '../services/money.dart';
import '../services/payment_info.dart';
import '../services/student_context.dart';
import '../theme/ym_ui.dart';
import '../widgets/pay_panel.dart';
import '../widgets/parent_child_picker.dart';

/// The parent's bus fee screen.
///
///  * the fee for this academic year: what is due, what is paid, what is left
///  * every payment recorded so far, and every payment sent for checking
///  * Pay / Renew: the parent pays through UPI (QR), then sends the reference
///    number here. The HELP DESK checks it and approves it. Only then is a payment
///    recorded, and the fee, the bus pass and the student's and admin's screens
///    update. The parent can never mark a fee as paid.
class ParentPaymentsScreen extends StatefulWidget {
  const ParentPaymentsScreen({
    super.key,
    required this.children,
    required this.selected,
  });

  final List<Map<String, dynamic>> children;
  final int selected;

  @override
  State<ParentPaymentsScreen> createState() => _ParentPaymentsScreenState();
}

class _ParentPaymentsScreenState extends State<ParentPaymentsScreen> {
  final _sb = Supabase.instance.client;

  late int _sel = widget.selected;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _requests = [];
  bool _hasPending = false;
  RealtimeChannel? _chan;

  Map<String, dynamic> get _child => widget.children[_sel];
  String get _childId => _child['id'].toString();
  String get _childName => (_child['student_name'] ?? 'Your child').toString();

  @override
  void initState() {
    super.initState();
    _load();
    // when the help desk confirms, the parent gets a notification: refresh then
    final uid = _sb.auth.currentUser?.id;
    if (uid != null) {
      _chan = _sb
          .channel('parent_pay_$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'recipient_id',
                value: uid),
            callback: (_) {
              if (mounted) _load(silent: true);
            },
          )
          .subscribe();
    }
  }

  @override
  void dispose() {
    _chan?.unsubscribe();
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
      final res = await _sb
          .rpc('parent_fee_overview', params: {'p_student': _childId});
      final m = Map<String, dynamic>.from(res as Map);
      if (!mounted) return;
      setState(() {
        _status = m['status'] == null
            ? null
            : Map<String, dynamic>.from(m['status'] as Map);
        _payments = [
          for (final x in (m['payments'] as List? ?? []))
            Map<String, dynamic>.from(x as Map),
        ];
        _requests = [
          for (final x in (m['requests'] as List? ?? []))
            Map<String, dynamic>.from(x as Map),
        ];
        _hasPending = m['has_pending'] == true;
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

  // ───────────────────────── helpers ─────────────────────────

  num? _num(dynamic v) => v == null ? null : num.tryParse('$v');

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

  String _day(dynamic v) {
    final d = DateTime.tryParse('$v');
    return d == null ? '-' : fmtDate(d.toLocal());
  }

  num get _due => _num(_status?['fee_due']) ?? 0;
  num get _paid => _num(_status?['amount_paid']) ?? 0;
  num get _balance => (_due - _paid) < 0 ? 0 : (_due - _paid);
  String get _fs => (_status?['fee_status'] ?? 'unknown').toString();

  bool get _canPay => (_fs == 'unpaid' || _fs == 'partial') && !_hasPending;

  // ───────────────────────── pay ─────────────────────────

  Future<void> _pay() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaySheet(
        studentId: _childId,
        studentName: _childName,
        balance: _balance,
        money: _money,
        institutionId: _child['institution_id']?.toString(),
      ),
    );
    if (ok == true && mounted) {
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sent. The help desk will confirm it here and tell you.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Payments',
      subtitle: 'Bus fee for $_childName',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: YmSkeletonList(count: 3, height: 120),
            )
          : _error != null
              ? YmEmpty(
                  icon: Icons.cloud_off_rounded,
                  color: Ym.red,
                  title: 'Could not load the fee',
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
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                    children: [
                      ParentChildPicker(
                        children: widget.children,
                        selected: _sel,
                        onChanged: (i) {
                          setState(() => _sel = i);
                          _load();
                        },
                      ),
                      _summary(),
                      const SizedBox(height: 14),
                      _action(),
                      if (_requests.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const YmSectionTitle('Sent for checking'),
                        for (final r in _requests) _requestTile(r),
                      ],
                      const SizedBox(height: 24),
                      const YmSectionTitle('Payment history'),
                      if (_payments.isEmpty)
                        YmCard(
                          child: Text('No payments have been recorded yet.',
                              style: Ym.t(13, color: Ym.grey)),
                        )
                      else
                        for (final p in _payments) _paymentTile(p),
                    ],
                  ),
                ),
    );
  }

  Widget _summary() {
    final paid = _fs == 'paid';
    final partial = _fs == 'partial';
    final color = paid ? Ym.green : (partial ? Ym.amberDark : Ym.red);
    final label = switch (_fs) {
      'paid' => 'Paid',
      'partial' => 'Partly paid',
      'unpaid' => 'Fee due',
      'fee_not_set' => 'Fee not set yet',
      'no_year' => 'No academic year yet',
      _ => 'Unknown',
    };
    final frac = _due <= 0 ? 0.0 : (_paid / _due).clamp(0.0, 1.0).toDouble();
    final till = DateTime.tryParse('${_status?['valid_till']}');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6E3), Color(0xFFFFE3AE)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Ym.amber.withOpacity(0.45)),
        boxShadow: Ym.shadow(Ym.amberDark, 0.22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    (_status?['academic_year'] ?? 'This year').toString(),
                    style: Ym.t(12.5, color: Ym.amberDark, w: FontWeight.w800)),
              ),
              YmChip(label, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(_status?['fee_due'] == null ? 'Fee not set' : _money(_due),
              style: Ym.h(32)),
          Text('bus fee for the year', style: Ym.t(12, color: Ym.grey)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Container(height: 10, color: Colors.white.withOpacity(0.7)),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [color.withOpacity(0.7), color]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _kv('Paid', _money(_paid))),
              Expanded(child: _kv('Balance', _money(_balance))),
              Expanded(
                  child: _kv('Pass valid till',
                      till == null ? 'Not active' : fmtDate(till))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: Ym.t(11, color: Ym.grey)),
          const SizedBox(height: 2),
          Text(v, style: Ym.h(14)),
        ],
      );

  Widget _action() {
    if (_hasPending) {
      final p = _requests.firstWhere(
          (r) => (r['status'] ?? '') == 'pending',
          orElse: () => <String, dynamic>{});
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Ym.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.hourglass_top_rounded, color: Ym.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                (p['method'] ?? '').toString().toLowerCase() == 'cash'
                    ? 'You said you will pay ${_money(_num(p['amount']))} in cash. Please go to the help desk '
                        'with the cash. You will get an alert, and your receipt, once they receive it.'
                    : 'Your payment of ${_money(_num(p['amount']))} is waiting for the help desk to check it. '
                        'You will get an alert as soon as it is confirmed.',
                style: Ym.t(12.5).copyWith(height: 1.45),
              ),
            ),
          ],
        ),
      );
    }
    if (_fs == 'paid') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Ym.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, color: Ym.green),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'The fee for this year is fully paid. You can pay again when the next academic year begins.',
                style: Ym.t(12.5).copyWith(height: 1.45),
              ),
            ),
          ],
        ),
      );
    }
    if (_fs == 'fee_not_set' || _fs == 'no_year') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Ym.amber.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Ym.amberDark),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _fs == 'fee_not_set'
                    ? 'The school has not set the fee for this route yet. Please contact the help desk.'
                    : 'The school has not set up this academic year yet. Please contact the help desk.',
                style: Ym.t(12.5).copyWith(height: 1.45),
              ),
            ),
          ],
        ),
      );
    }
    return YmButton(
      label: _fs == 'partial' ? 'Pay the balance' : 'Pay / Renew',
      icon: Icons.qr_code_2_rounded,
      onPressed: _canPay ? _pay : null,
    );
  }

  Widget _requestTile(Map<String, dynamic> r) {
    final st = (r['status'] ?? 'pending').toString();
    final color = st == 'approved'
        ? Ym.green
        : st == 'rejected'
            ? Ym.red
            : Ym.blue;
    final isCash = (r['method'] ?? '').toString().toLowerCase() == 'cash';
    final label = st == 'approved'
        ? (isCash ? 'Cash received' : 'Confirmed')
        : st == 'rejected'
            ? (isCash ? 'Cancelled' : 'Not verified')
            : (isCash ? 'Waiting for cash' : 'Being checked');
    final note = (r['review_note'] ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                YmIconBadge(
                    icon: st == 'approved'
                        ? Icons.check_circle_rounded
                        : st == 'rejected'
                            ? Icons.cancel_rounded
                            : Icons.hourglass_top_rounded,
                    color: color,
                    size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_money(_num(r['amount'])), style: Ym.h(15)),
                      Text(
                          (r['method'] ?? '').toString().toLowerCase() == 'cash'
                              ? 'Cash  •  ${_day(r['created_at'])}'
                              : 'Ref ${r['reference'] ?? '-'}  •  ${_day(r['created_at'])}',
                          style: Ym.t(11.5, color: Ym.grey)),
                    ],
                  ),
                ),
                YmChip(label, color: color),
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(note, style: Ym.t(12.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paymentTile(Map<String, dynamic> p) {
    final st = (p['status'] ?? 'paid').toString();
    final ok = st == 'paid';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        child: Row(
          children: [
            YmIconBadge(
                icon: ok ? Icons.receipt_long_rounded : Icons.error_outline_rounded,
                color: ok ? Ym.green : Ym.red,
                size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_money(_num(p['amount'])), style: Ym.h(15)),
                  Text(
                    [
                      _day(p['paid_on']),
                      if ((p['method'] ?? '').toString().isNotEmpty)
                        p['method'].toString(),
                      if ((p['academic_year'] ?? '').toString().isNotEmpty)
                        p['academic_year'].toString(),
                    ].join('  •  '),
                    style: Ym.t(11.5, color: Ym.grey),
                  ),
                  if ((p['reference'] ?? '').toString().isNotEmpty)
                    Text('Ref ${p['reference']}',
                        style: Ym.t(11.5, color: Ym.grey)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                YmChip(ok ? 'Paid' : 'Failed', color: ok ? Ym.green : Ym.red),
                if (ok) ...[
                  const SizedBox(height: 6),
                  YmPressable(
                    onTap: () => downloadFeeReceipt(context, p['id'].toString()),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.download_rounded, size: 15, color: Ym.amberDark),
                        const SizedBox(width: 4),
                        Text('Receipt',
                            style: Ym.t(12, color: Ym.amberDark, w: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── the pay sheet ─────────────────────────

/// Pay the bus fee: by UPI (QR, "Pay now", and the reference to type afterwards) or by CASH
/// at the help desk. Either way it goes to the help desk as a request. Nothing is marked
/// paid until the help desk has checked the UPI payment, or received the cash.
class _PaySheet extends StatefulWidget {
  const _PaySheet({
    required this.studentId,
    required this.studentName,
    required this.balance,
    required this.money,
    this.institutionId,
  });

  final String studentId;
  final String studentName;
  final num balance;
  final String Function(num?) money;
  final String? institutionId;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  final _sb = Supabase.instance.client;
  late final TextEditingController _amount =
      TextEditingController(text: widget.balance.round().toString());
  final _ref = TextEditingController();

  PayMode _mode = PayMode.upi;
  PaymentInfo _info = PaymentInfo.demo;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    PaymentInfo.load(widget.institutionId).then((v) {
      if (mounted) setState(() => _info = v);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  num? get _amt => parseMoney(_amount.text);

  Future<void> _send() async {
    final a = _amt;
    if (a == null || a <= 0) {
      setState(() => _error = 'Please enter the amount, for example 15000 or 15,000.');
      return;
    }
    if (a > widget.balance) {
      setState(() => _error =
          'The amount is more than the balance (${widget.money(widget.balance)}).');
      return;
    }
    final cash = _mode == PayMode.cash;
    final ref = _ref.text.trim();
    if (!cash && ref.length < 4) {
      setState(() => _error =
          'After you pay, please enter the UPI / transaction reference number.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _sb.rpc('submit_payment_request', params: {
        'p_student': widget.studentId,
        'p_amount': a,
        'p_reference': cash ? null : ref,
        'p_note': null,
        'p_method': cash ? 'Cash' : 'UPI',
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is PostgrestException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cash = _mode == PayMode.cash;
    final amt = _amt ?? 0;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.94),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(22, 14, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
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
              Text('Pay the bus fee', style: Ym.h(21)),
              const SizedBox(height: 4),
              Text('For ${widget.studentName}', style: Ym.t(12.5, color: Ym.grey)),
              const SizedBox(height: 16),
              Text('Amount you are paying',
                  style: Ym.t(12, color: Ym.grey, w: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _error = null),
                style: Ym.h(22),
                decoration: InputDecoration(
                  prefixText: '\u20B9 ',
                  prefixStyle: Ym.h(22),
                  helperText: 'Balance due: ${widget.money(widget.balance)}',
                  filled: true,
                  fillColor: Ym.creamTop,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              PayPanel(
                info: _info,
                amount: amt,
                note: 'Bus fee ${widget.studentName}',
                mode: _mode,
                onMode: (m) => setState(() {
                  _mode = m;
                  _error = null;
                }),
                referenceController: _ref,
                onReferenceChanged: (_) => setState(() => _error = null),
                errorText: _mode == PayMode.upi ? _error : null,
              ),
              if (cash && _error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: Ym.t(12.5, color: Ym.red)),
              ],
              const SizedBox(height: 16),
              YmButton(
                label: cash ? 'Tell the help desk I will pay cash' : 'I have paid, send for checking',
                icon: cash ? Icons.payments_outlined : Icons.send_rounded,
                loading: _saving,
                onPressed: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}