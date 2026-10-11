import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/payment_info.dart';
import '../theme/ym_ui.dart';

/// How the person wants to pay.
enum PayMode { upi, cash, later }

/// The payment part shared by the registration form and the parent's Pay screen.
///
///  * UPI   : a QR (made from the school's UPI ID and the amount), a "Pay now" button that
///            opens the person's UPI app with everything filled in, shortcuts for PhonePe,
///            Google Pay and Paytm, and a box for the reference number to type afterwards.
///  * Cash  : what to do, and the help desk's cash note and phone. The cash is counted only
///            when the help desk confirms it.
///  * Later : (the form only) nothing to pay now.
class PayPanel extends StatelessWidget {
  const PayPanel({
    super.key,
    required this.info,
    required this.amount,
    required this.note,
    required this.mode,
    required this.onMode,
    required this.referenceController,
    this.onReferenceChanged,
    this.allowLater = false,
    this.errorText,
  });

  final PaymentInfo info;

  /// the amount that will be paid (the QR and the buttons use it)
  final num amount;

  /// the note shown in the UPI app, for example "Bus fee Saba"
  final String note;

  final PayMode mode;
  final ValueChanged<PayMode> onMode;
  final TextEditingController referenceController;
  final ValueChanged<String>? onReferenceChanged;
  final bool allowLater;
  final String? errorText;

  String _rupees(num v) => '\u20B9${v.round()}';

  void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
      );

  Future<void> _open(BuildContext context, {String? app}) async {
    if (amount <= 0) {
      _snack(context, 'Please enter the amount first.');
      return;
    }
    final ok = await info.openApp(amount, note, app: app);
    if (!context.mounted) return;
    if (!ok) {
      _snack(
          context,
          'Could not open a UPI app here. On a computer, scan the QR with your phone. '
          'You can also copy the UPI ID.');
    } else {
      _snack(context, 'After you pay, come back and type the reference number below.');
    }
  }

  Widget _modeChip(BuildContext c, PayMode m, IconData icon, String label) {
    final on = mode == m;
    return Expanded(
      child: YmPressable(
        onTap: () => onMode(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
          decoration: BoxDecoration(
            color: on ? Ym.navy : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? Ym.navy : Ym.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: on ? Colors.white : Ym.grey),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    style: Ym.t(11.5, color: on ? Colors.white : Ym.navy, w: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appChip(BuildContext c, String label, String app, Color color) => Expanded(
        child: YmPressable(
          onTap: () => _open(c, app: app),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: Ym.t(12, color: color, w: FontWeight.w800)),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _modeChip(context, PayMode.upi, Icons.qr_code_2_rounded, 'UPI, Pay now'),
            const SizedBox(width: 8),
            _modeChip(context, PayMode.cash, Icons.payments_outlined, 'Cash at help desk'),
            if (allowLater) ...[
              const SizedBox(width: 8),
              _modeChip(context, PayMode.later, Icons.schedule_rounded, 'Pay later'),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (mode == PayMode.upi) _upi(context),
        if (mode == PayMode.cash) _cash(context),
        if (mode == PayMode.later)
          Text(
            'No problem. You can pay later at the help desk, or in the parent app after your login is created.',
            style: Ym.t(12.5, color: Ym.grey).copyWith(height: 1.5),
          ),
      ],
    );
  }

  // ── UPI ──

  Widget _upi(BuildContext context) {
    final payee = info.payeeName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        YmButton(
          label: 'Pay now ${amount > 0 ? _rupees(amount) : ''}'.trim(),
          icon: Icons.bolt_rounded,
          onPressed: () => _open(context),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _appChip(context, 'PhonePe', 'phonepe', const Color(0xFF5F259F)),
            const SizedBox(width: 8),
            _appChip(context, 'Google Pay', 'gpay', const Color(0xFF1A73E8)),
            const SizedBox(width: 8),
            _appChip(context, 'Paytm', 'paytm', const Color(0xFF00B9F1)),
          ],
        ),
        const SizedBox(height: 6),
        Text('On a phone, these open your UPI app with the amount filled in.',
            style: Ym.t(11.5, color: Ym.grey)),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Ym.line, width: 1.5),
              boxShadow: Ym.shadow(Ym.navy, 0.08),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(
                  data: info.upiLink(amount > 0 ? amount : 1, note),
                  size: 180,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 6),
                Text('Or scan this with any UPI app', style: Ym.t(11.5, color: Ym.grey)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: YmPressable(
            onTap: () {
              Clipboard.setData(ClipboardData(text: info.upiId));
              _snack(context, 'UPI ID copied');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Ym.creamTop,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text('$payee   \u2022   ${info.upiId}',
                        overflow: TextOverflow.ellipsis,
                        style: Ym.t(12.5, w: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy_rounded, size: 15, color: Ym.grey),
                ],
              ),
            ),
          ),
        ),
        if (info.isDemo) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Ym.amber.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.science_outlined, size: 18, color: Ym.amberDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Demo QR. The school's real UPI ID has not been added yet. Do not send real money.",
                    style: Ym.t(12, w: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('UPI / transaction reference number',
            style: Ym.t(12, color: Ym.grey, w: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: referenceController,
          textCapitalization: TextCapitalization.characters,
          onChanged: onReferenceChanged,
          style: Ym.t(14.5, w: FontWeight.w700),
          decoration: InputDecoration(
            hintText: 'After you pay, type the reference number here',
            hintStyle: Ym.t(13, color: Ym.grey),
            helperText: 'You can find it in your UPI app under the payment details.',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Ym.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Ym.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Ym.amber, width: 1.6),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Text(errorText!, style: Ym.t(12.5, color: Ym.red)),
        ],
        const SizedBox(height: 10),
        Text(
          'The help desk checks the payment before the fee is marked as paid.',
          style: Ym.t(12, color: Ym.grey).copyWith(height: 1.45),
        ),
      ],
    );
  }

  // ── cash ──

  Widget _cash(BuildContext context) {
    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Ym.navy, shape: BoxShape.circle),
                child: Text(n, style: Ym.t(11.5, color: Colors.white, w: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: Ym.t(13).copyWith(height: 1.4))),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ym.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const YmIconBadge(icon: Icons.payments_outlined, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                amount > 0 ? 'Pay ${_rupees(amount)} in cash' : 'Pay in cash',
                style: Ym.h(16),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          step('1', 'Send this request, so the help desk knows you are coming.'),
          step('2', 'Go to the help desk and hand over the cash.'),
          step('3', 'The help desk confirms it, and your fee receipt is made.'),
          if (info.cashNote != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.place_outlined, size: 17, color: Ym.amberDark),
              const SizedBox(width: 8),
              Expanded(child: Text(info.cashNote!, style: Ym.t(12.5, w: FontWeight.w700))),
            ]),
          ],
          if (info.helpPhone != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.call_outlined, size: 17, color: Ym.green),
              const SizedBox(width: 8),
              Text('Help desk: ${info.helpPhone}', style: Ym.t(12.5, w: FontWeight.w700)),
            ]),
          ],
          const SizedBox(height: 10),
          Text('Your fee is marked as paid only after the help desk has received the cash.',
              style: Ym.t(12, color: Ym.grey).copyWith(height: 1.45)),
        ],
      ),
    );
  }
}