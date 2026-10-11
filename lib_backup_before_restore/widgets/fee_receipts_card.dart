import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fee_receipt.dart';
import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// "Fee receipts": the receipts of a student's payments, each with a download button.
/// Shown next to the bus pass, for the student and for the parent. It shows nothing
/// until a payment has been confirmed, and nothing if receipts are not set up yet.
class FeeReceiptsCard extends StatefulWidget {
  const FeeReceiptsCard({super.key, required this.studentId});

  final String studentId;

  @override
  State<FeeReceiptsCard> createState() => _FeeReceiptsCardState();
}

class _FeeReceiptsCardState extends State<FeeReceiptsCard> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FeeReceiptsCard old) {
    super.didUpdateWidget(old);
    if (old.studentId != widget.studentId) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .rpc('student_receipts', params: {'p_student': widget.studentId}) as List;
      if (!mounted) return;
      setState(() {
        _items = [for (final r in rows) Map<String, dynamic>.from(r as Map)];
        _loaded = true;
      });
    } catch (_) {
      // receipts not set up (or not allowed): the card simply stays hidden
      if (mounted) setState(() => _loaded = true);
    }
  }

  String _money(dynamic v) {
    final n = num.tryParse('$v') ?? 0;
    final s = n.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '\u20B9$b';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _items.isEmpty) return const SizedBox.shrink();
    final shown = _items.take(5).toList();

    return YmCard(
      padding: const EdgeInsets.all(16),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YmIconBadge(icon: Icons.receipt_long_rounded, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fee receipts', style: Ym.h(15.5)),
                    Text('Download a receipt for any payment',
                        style: Ym.t(11.5, color: Ym.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: YmPressable(
                onTap: () => downloadFeeReceipt(context, p['payment_id'].toString()),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: Ym.creamTop,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Receipt ${p['receipt_no'] ?? ''}   \u2022   ${_money(p['amount'])}',
                              style: Ym.h(13.5),
                            ),
                            Text(
                              [
                                if (parseUtc(p['paid_on']) != null) fmtDate(parseUtc(p['paid_on'])!),
                                if ((p['academic_year'] ?? '').toString().isNotEmpty)
                                  p['academic_year'].toString(),
                              ].join('   \u2022   '),
                              style: Ym.t(11.5, color: Ym.grey),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.download_rounded, color: Ym.amberDark, size: 22),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}