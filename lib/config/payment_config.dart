/// Where parents pay the bus fee.
///
/// These are DEMO values so the screen can be built and tested. When the school
/// has its real UPI ID, change `upiId` and `payeeName` here, and set `isDemo`
/// to false. Nothing else in the app needs to change.
class PaymentConfig {
  PaymentConfig._();

  /// the school's UPI ID (VPA)
  static const String upiId = 'yatramitra@upi';

  /// the name shown in the parent's UPI app
  static const String payeeName = 'Yatra Mitra Demo';

  /// while true, the pay screen tells the parent this is a demo QR
  static const bool isDemo = true;

  /// the text inside the QR: a standard UPI payment link
  static String upiLink({required num amount, required String note}) {
    final a = amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2);
    return 'upi://pay?pa=${Uri.encodeComponent(upiId)}'
        '&pn=${Uri.encodeComponent(payeeName)}'
        '&am=$a&cu=INR&tn=${Uri.encodeComponent(note)}';
  }
}