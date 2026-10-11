import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fee_receipt.dart';
import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// For the help desk (and the admin): payments that parents have sent.
///
/// A parent pays by UPI and sends the reference number. The help desk compares it
/// with the school's UPI / bank statement, then:
///   Approve  -> a real payment is recorded. The fee status, the bus pass and the
///               parent's, student's and admin's screens update by themselves.
///   Reject   -> nothing is recorded. The parent is told why.
class PaymentRequestsScreen extends StatefulWidget {
  const PaymentRequestsScreen({super.key});

  @override
  State<PaymentRequestsScreen> createState() => _PaymentRequestsScreenState();
}

class _PaymentRequestsScreenState extends State<PaymentRequestsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  bool _showDone = false;
  RealtimeChannel? _chan;

  @override
  void initState() {
    super.initState();
    _load();
    final uid = _sb.auth.currentUser?.id;
    if (uid != null) {
      // a new request arrives as a notification: refresh the list
      _chan = _sb
          .channel('pay_requests_$uid')
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
      final rows = await _sb.rpc('inbox_payment_requests') as List;
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

  Future<void> _open(Map<String, dynamic> r) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(item: r, money: _money),
    );
    if (result == null) return;
    await _load(silent: true);

    // an approved payment now has a receipt: offer it at once
    if (result['approved'] == true && mounted) {
      final done = _items.firstWhere(
        (x) => x['id'].toString() == result['id'].toString(),
        orElse: () => <String, dynamic>{},
      );
      final paymentId = done['payment_id']?.toString();
      if (paymentId != null && paymentId.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(children: [
              const Icon(Icons.check_circle_rounded, color: Ym.green),
              const SizedBox(width: 10),
              Text('Payment approved', style: Ym.h(18)),
            ]),
            content: Text(
              'The fee was recorded, and the parent has been told. '
              'The fee receipt is ready. You can download or print it now, '
              'and the parent can also download it from the app.',
              style: Ym.t(13.5, color: Ym.grey).copyWith(height: 1.5),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Later')),
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  downloadFeeReceipt(context, paymentId);
                },
                child: Text('Download receipt',
                    style: Ym.t(14, color: Ym.amberDark, w: FontWeight.w800)),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items.where((r) => r['status'] == 'pending').toList();
    final finished = _items.where((r) => r['status'] != 'pending').toList();
    final list = _showDone ? finished : pending;

    return YmPage(
      title: 'Payment requests',
      subtitle: 'Payments sent by parents, to check',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                _tab('To check (${pending.length})', !_showDone,
                    () => setState(() => _showDone = false)),
                const SizedBox(width: 8),
                _tab('Done (${finished.length})', _showDone,
                    () => setState(() => _showDone = true)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: YmSkeletonList(count: 4, height: 100),
                  )
                : _error != null
                    ? YmEmpty(
                        icon: Icons.cloud_off_rounded,
                        color: Ym.red,
                        title: 'Could not load payment requests',
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
                                children: [
                                  const SizedBox(height: 50),
                                  YmEmpty(
                                    icon: _showDone
                                        ? Icons.history_rounded
                                        : Icons.verified_rounded,
                                    color: _showDone ? Ym.grey : Ym.green,
                                    title: _showDone
                                        ? 'Nothing checked yet'
                                        : 'Nothing to check',
                                    subtitle: _showDone
                                        ? 'Payments you approve or reject will be listed here.'
                                        : 'When a parent sends a payment, it appears here.',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                                itemCount: list.length,
                                itemBuilder: (_, i) => YmFadeSlide(
                                  index: i > 6 ? 6 : i,
                                  child: _tile(list[i]),
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _tab(String text, bool on, VoidCallback onTap) => YmPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: on
                ? const LinearGradient(colors: [Ym.amber, Ym.amberDark])
                : null,
            color: on ? null : Colors.white,
            boxShadow: Ym.shadow(Ym.navy, 0.06),
          ),
          child: Text(text,
              style: Ym.t(12.5, color: on ? Ym.navy : Ym.grey, w: FontWeight.w800)),
        ),
      );

  Widget _tile(Map<String, dynamic> r) {
    final st = (r['status'] ?? 'pending').toString();
    final color = st == 'approved'
        ? Ym.green
        : st == 'rejected'
            ? Ym.red
            : Ym.amberDark;
    final at = parseUtc(r['created_at']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: YmCard(
        onTap: () => _open(r),
        padding: const EdgeInsets.all(16),
        radius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                YmIconBadge(icon: Icons.payments_rounded, color: color, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((r['student_name'] ?? 'Student').toString(),
                          style: Ym.h(15)),
                      Text(
                          [
                            if ((r['route_name'] ?? '').toString().isNotEmpty)
                              r['route_name'].toString(),
                            if ((r['parent_name'] ?? '').toString().isNotEmpty)
                              'Parent: ${r['parent_name']}',
                          ].join('  •  '),
                          style: Ym.t(11.5, color: Ym.grey)),
                    ],
                  ),
                ),
                Text(_money(_num(r['amount'])), style: Ym.h(17)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if ((r['method'] ?? '').toString().toLowerCase() == 'cash')
                const YmChip('CASH', color: Ym.amberDark, icon: Icons.payments_outlined)
              else
                YmChip('Ref ${r['reference'] ?? '-'}',
                    color: Ym.navy, icon: Icons.tag_rounded),
              if (at != null)
                YmChip('${fmtDate(at)}  ${fmtClock(at)}',
                    color: Ym.grey, icon: Icons.schedule_rounded),
              if (st != 'pending')
                YmChip(st == 'approved' ? 'Approved' : 'Rejected', color: color),
              if (st == 'approved' && r['payment_id'] != null)
                const YmChip('Receipt ready',
                    color: Ym.amberDark, icon: Icons.receipt_long_rounded),
            ]),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── review sheet ─────────────────────────

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.item, required this.money});

  final Map<String, dynamic> item;
  final String Function(num?) money;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _sb = Supabase.instance.client;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get r => widget.item;
  bool get _pending => r['status'] == 'pending';
  bool get _cash => (r['method'] ?? '').toString().toLowerCase() == 'cash';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  num? _num(dynamic v) => v == null ? null : num.tryParse('$v');

  Future<void> _decide(bool approve) async {
    if (!approve && _note.text.trim().isEmpty) {
      setState(() => _error = 'Please write a short reason, so the parent knows what to do.');
      return;
    }
    if (approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(_cash ? 'Cash received?' : 'Approve this payment?', style: Ym.h(18)),
          content: Text(
            _cash
                ? 'This records ${widget.money(_num(r['amount']))} as PAID, in cash, for ${r['student_name']}. '
                    'Only approve it after you have the cash in your hand.'
                : 'This records ${widget.money(_num(r['amount']))} as PAID for ${r['student_name']}. '
                    'Please make sure the money has reached the school account (reference ${r['reference']}).',
            style: Ym.t(13.5, color: Ym.grey).copyWith(height: 1.5),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text('Yes, approve',
                    style: Ym.t(14, color: Ym.green, w: FontWeight.w800))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _sb.rpc('review_payment_request', params: {
        'p_id': r['id'],
        'p_approve': approve,
        'p_note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      if (mounted) {
        Navigator.of(context)
            .pop(<String, dynamic>{'approved': approve, 'id': r['id'].toString()});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is PostgrestException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final at = parseUtc(r['created_at']);
    final due = _num(r['fee_due']);
    final paid = _num(r['amount_paid']);
    final parentLine = [
      if ((r['parent_name'] ?? '').toString().isNotEmpty) r['parent_name'].toString(),
      if ((r['parent_phone'] ?? '').toString().isNotEmpty) r['parent_phone'].toString(),
    ].join('  •  ');
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(
          22, 14, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
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
              Text(widget.money(_num(r['amount'])), style: Ym.h(32)),
              Text('sent for ${r['student_name'] ?? 'a student'}',
                  style: Ym.t(13, color: Ym.grey)),
              const SizedBox(height: 16),
              if (_cash)
                _row('Pay mode', 'Cash, to be handed over at the help desk', bold: true)
              else
                _row('Reference number', (r['reference'] ?? '-').toString(), bold: true),
              _row('Sent on', at == null ? '-' : '${fmtDate(at)}  ${fmtClock(at)}'),
              _row('Parent', parentLine.isEmpty ? '-' : parentLine),
              _row('Route', (r['route_name'] ?? '-').toString()),
              _row('Fee this year',
                  due == null ? 'Not set' : '${widget.money(due)}  (paid ${widget.money(paid ?? 0)})'),
              if ((r['note'] ?? '').toString().isNotEmpty)
                _row('Parent\'s note', r['note'].toString()),
              if (!_pending) ...[
                _row('Result', r['status'] == 'approved' ? 'Approved' : 'Rejected', bold: true),
                if ((r['review_note'] ?? '').toString().isNotEmpty)
                  _row('Your note', r['review_note'].toString()),
                if (r['status'] == 'approved' && r['payment_id'] != null) ...[
                  const SizedBox(height: 6),
                  YmButton(
                    label: 'Download fee receipt',
                    icon: Icons.receipt_long_rounded,
                    onPressed: () => downloadFeeReceipt(context, r['payment_id'].toString()),
                  ),
                ],
              ],
              if (_pending) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _note,
                  maxLength: 140,
                  style: Ym.t(14),
                  decoration: InputDecoration(
                    hintText: 'Note for the parent (needed if you reject)',
                    hintStyle: Ym.t(13, color: Ym.grey),
                    filled: true,
                    fillColor: Ym.creamTop,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: Ym.t(12.5, color: Ym.red)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: YmButton(
                        label: 'Reject',
                        outline: true,
                        color: Ym.red,
                        onPressed: _busy ? null : () => _decide(false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: YmButton(
                        label: _cash ? 'Cash received' : 'Approve',
                        icon: Icons.check_rounded,
                        loading: _busy,
                        onPressed: () => _decide(true),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              child: Text(k, style: Ym.t(12.5, color: Ym.grey)),
            ),
            Expanded(
              child: Text(v,
                  style: bold ? Ym.h(14) : Ym.t(13, w: FontWeight.w600)),
            ),
          ],
        ),
      );
}