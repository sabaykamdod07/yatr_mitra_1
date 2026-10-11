import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/payment_config.dart';

/// How a person can pay: the school's UPI ID and name (set by the admin), the cash counter
/// note, and the help desk phone. Used by the registration form and the parent app.
///
/// If the admin has not set a UPI ID yet, the demo values from `PaymentConfig` are used, and
/// `isDemo` is true so the screens can warn "Demo QR, do not send real money".
class PaymentInfo {
  const PaymentInfo({
    required this.upiId,
    required this.payeeName,
    required this.isDemo,
    this.cashNote,
    this.helpPhone,
    this.institution,
  });

  final String upiId;
  final String payeeName;
  final bool isDemo;
  final String? cashNote;
  final String? helpPhone;
  final String? institution;

  /// the demo values, until the admin sets the real ones
  static const PaymentInfo demo = PaymentInfo(
    upiId: PaymentConfig.upiId,
    payeeName: PaymentConfig.payeeName,
    isDemo: true,
  );

  static String? _clean(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Reads the settings of an institution. Never throws: on any problem it returns the demo values.
  static Future<PaymentInfo> load(String? institutionId) async {
    if (institutionId == null || institutionId.isEmpty) return demo;
    try {
      final res = await Supabase.instance.client
          .rpc('public_payment_info', params: {'p_institution': institutionId});
      if (res is! Map) return demo;
      final upi = _clean(res['upi_id']);
      return PaymentInfo(
        upiId: upi ?? PaymentConfig.upiId,
        payeeName: _clean(res['payee_name']) ?? _clean(res['institution']) ?? PaymentConfig.payeeName,
        isDemo: upi == null,
        cashNote: _clean(res['cash_note']),
        helpPhone: _clean(res['help_phone']),
        institution: _clean(res['institution']),
      );
    } catch (_) {
      return demo;
    }
  }

  String _query(num amount, String note) {
    final a = amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2);
    return 'pa=${Uri.encodeComponent(upiId)}'
        '&pn=${Uri.encodeComponent(payeeName)}'
        '&am=$a&cu=INR&tn=${Uri.encodeComponent(note)}';
  }

  /// the standard UPI link: it is what the QR holds, and it opens any UPI app
  String upiLink(num amount, String note) => 'upi://pay?${_query(amount, note)}';

  /// a link that opens one particular app
  String appLink(String app, num amount, String note) {
    final q = _query(amount, note);
    switch (app) {
      case 'phonepe':
        return 'phonepe://pay?$q';
      case 'gpay':
        return 'gpay://upi/pay?$q';
      case 'paytm':
        return 'paytmmp://pay?$q';
      default:
        return 'upi://pay?$q';
    }
  }

  /// Opens the person's UPI app with the amount and the payee filled in.
  /// [app] = 'phonepe' | 'gpay' | 'paytm' | null (null shows the phone's own list of UPI apps).
  /// Returns false when nothing could be opened (for example on a computer).
  Future<bool> openApp(num amount, String note, {String? app}) async {
    try {
      final uri = Uri.parse(appLink(app ?? '', amount, note));
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('UPI app could not be opened: $e');
      return false;
    }
  }
}