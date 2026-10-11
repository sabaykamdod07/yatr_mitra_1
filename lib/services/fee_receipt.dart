import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The fee receipt: a downloadable PDF in the layout of a school fee receipt
/// (header, FEE RECEIPT band, receipt details, the fee table, pay mode information,
/// the total in words, "computer generated" note). There is no QR code on it.
///
/// The numbers come from the database function `payment_receipt`, which only gives the
/// receipt to the help desk / admin, the student's parent, and the student.

/// Asks the database for everything printed on the receipt of one payment.
Future<Map<String, dynamic>> fetchFeeReceipt(String paymentId) async {
  final res = await Supabase.instance.client
      .rpc('payment_receipt', params: {'p_payment': paymentId});
  return Map<String, dynamic>.from(res as Map);
}

/// Builds the PDF and opens the share / download sheet.
Future<void> downloadFeeReceipt(BuildContext context, String paymentId) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(
    content: Text('Preparing the receipt...'),
    duration: Duration(seconds: 2),
    behavior: SnackBarBehavior.floating,
  ));
  try {
    final data = await fetchFeeReceipt(paymentId);
    final bytes = await buildFeeReceiptPdf(data);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'fee-receipt-${data['receipt_no'] ?? 'x'}.pdf',
    );
  } catch (e) {
    final msg = e is PostgrestException ? e.message : e.toString();
    messenger.showSnackBar(SnackBar(
      content: Text('Could not make the receipt: $msg'),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

// ───────────────────────── number helpers ─────────────────────────

const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
  'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen',
  'Eighteen', 'Nineteen',
];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _below100(int n) {
  if (n < 20) return _ones[n];
  final t = _tens[n ~/ 10];
  final o = n % 10;
  return o == 0 ? t : '$t-${_ones[o].toLowerCase()}';
}

String _below1000(int n) {
  final h = n ~/ 100;
  final r = n % 100;
  final parts = <String>[];
  if (h > 0) parts.add('${_ones[h]} Hundred');
  if (r > 0) parts.add(_below100(r));
  return parts.join(' ');
}

/// "177820" -> "One Lakh Seventy-seven Thousand Eight Hundred Twenty Only"
/// (Indian grouping: thousand, lakh, crore).
String amountInWords(num amount) {
  final rupees = amount.floor();
  final paise = ((amount - rupees) * 100).round();
  if (rupees == 0 && paise == 0) return 'Zero Only';

  final crore = rupees ~/ 10000000;
  final lakh = (rupees % 10000000) ~/ 100000;
  final thousand = (rupees % 100000) ~/ 1000;
  final rest = rupees % 1000;

  final parts = <String>[];
  if (crore > 0) parts.add('${_below1000(crore)} Crore');
  if (lakh > 0) parts.add('${_below100(lakh)} Lakh');
  if (thousand > 0) parts.add('${_below100(thousand)} Thousand');
  if (rest > 0) parts.add(_below1000(rest));

  var words = parts.join(' ');
  if (paise > 0) {
    words = '${words.isEmpty ? '' : '$words and '}${_below100(paise)} Paise';
  }
  return '$words Only';
}

String _amt(dynamic v) {
  final n = num.tryParse('$v') ?? 0;
  return n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2);
}

String _date(dynamic v) {
  final d = DateTime.tryParse('$v');
  if (d == null) return '-';
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

String _initials(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (w.isEmpty) return 'YM';
  if (w.length == 1) return w.first.substring(0, w.first.length >= 2 ? 2 : 1).toUpperCase();
  return (w[0][0] + w[1][0]).toUpperCase();
}

// ───────────────────────── the PDF ─────────────────────────

Future<Uint8List> buildFeeReceiptPdf(Map<String, dynamic> r) async {
  const green = PdfColor.fromInt(0xFF1E7B4F);
  const band = PdfColor.fromInt(0xFFD9D9D9);
  const line = PdfColor.fromInt(0xFFB0B0B0);
  const grey = PdfColor.fromInt(0xFF7A7A7A);

  final institution = (r['institution'] ?? 'Institution').toString();
  final city = (r['city'] ?? '').toString();
  final amount = num.tryParse('${r['amount']}') ?? 0;
  final routeFee = num.tryParse('${r['route_fee']}') ?? 0;
  final concession = num.tryParse('${r['concession']}') ?? 0;
  final feeTotal = num.tryParse('${r['fee_total']}') ?? 0;
  final paidTill = num.tryParse('${r['paid_till_date']}') ?? 0;
  final balance = num.tryParse('${r['balance']}') ?? 0;
  final instNo = r['installment_no'];
  final instCount = r['installment_count'];

  final method = ((r['method'] ?? '').toString().trim().isEmpty
          ? ((r['reference'] ?? '').toString().trim().isEmpty ? 'Cash' : 'UPI')
          : r['method'].toString())
      .trim();
  var reference = (r['reference'] ?? '').toString().trim();
  if (reference.toUpperCase().startsWith('CASH-')) reference = ''; // an internal code, not for the receipt
  final description = (r['description'] ?? 'Bus Fee').toString();
  final route = (r['route_name'] ?? '').toString();

  pw.Widget bandRow(String text) => pw.Container(
        width: double.infinity,
        color: band,
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Center(
          child: pw.Text(text, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ),
      );

  pw.Widget info(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 7),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 78,
              child: pw.Text(k, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text(':  ', style: const pw.TextStyle(fontSize: 10.5)),
            pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: 10.5))),
          ],
        ),
      );

  pw.Widget cell(String t, {bool right = false, bool bold = false, double size = 10}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: pw.Align(
          alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
          child: pw.Text(t,
              style: pw.TextStyle(
                  fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ),
      );

  final doc = pw.Document(title: 'Fee receipt ${r['receipt_no'] ?? ''}');
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: 0.8)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // header: emblem, institution, address
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: 58,
                        height: 58,
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          border: pw.Border.all(color: green, width: 2.4),
                        ),
                        child: pw.Center(
                          child: pw.Text(_initials(institution),
                              style: pw.TextStyle(
                                  fontSize: 17, fontWeight: pw.FontWeight.bold, color: green)),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          children: [
                            pw.Text(institution,
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold)),
                            if (city.isNotEmpty) ...[
                              pw.SizedBox(height: 4),
                              pw.Text(city,
                                  textAlign: pw.TextAlign.center,
                                  style: const pw.TextStyle(fontSize: 11)),
                            ],
                            pw.SizedBox(height: 2),
                            pw.Text('Transport (Bus) Fee',
                                textAlign: pw.TextAlign.center,
                                style: const pw.TextStyle(fontSize: 9.5, color: grey)),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 58),
                    ],
                  ),
                ),
                bandRow('FEE RECEIPT'),

                // receipt details, two columns
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 11,
                        child: pw.Column(
                          children: [
                            info('Receipt No', '${r['receipt_no'] ?? '-'}'),
                            info('Adm No', (r['enrollment_no'] ?? '-').toString()),
                            info('Name', (r['student_name'] ?? '-').toString().toUpperCase()),
                            info('Installment',
                                instNo == null ? '-' : (instCount != null ? '$instNo of $instCount' : '$instNo')),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 14),
                      pw.Expanded(
                        flex: 9,
                        child: pw.Column(
                          children: [
                            info('Date', _date(r['paid_on'])),
                            info('Session', (r['session'] ?? '-').toString()),
                            info('Class', (r['class_name'] ?? '-').toString()),
                            info('Counter No', (r['counter'] ?? 'HELP DESK').toString()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // the fee table
                pw.Table(
                  columnWidths: const {
                    0: pw.FixedColumnWidth(44),
                    1: pw.FlexColumnWidth(),
                    2: pw.FixedColumnWidth(70),
                    3: pw.FixedColumnWidth(50),
                    4: pw.FixedColumnWidth(74),
                  },
                  border: const pw.TableBorder(
                    top: pw.BorderSide(color: line, width: 0.8),
                    bottom: pw.BorderSide(color: line, width: 0.8),
                    horizontalInside: pw.BorderSide(color: line, width: 0.5),
                  ),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFEFEF)),
                      children: [
                        cell('Sl.No', bold: true, size: 9.5),
                        cell('Description', bold: true, size: 9.5),
                        cell('Due', right: true, bold: true, size: 9.5),
                        cell('Con', right: true, bold: true, size: 9.5),
                        cell('Paid', right: true, bold: true, size: 9.5),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        cell('1'),
                        cell(route.isEmpty ? description : '$description ($route)'),
                        cell(_amt(routeFee), right: true),
                        cell(_amt(concession), right: true),
                        cell(_amt(amount), right: true),
                      ],
                    ),
                  ],
                ),

                // where the year's fee stands after this payment
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Fee for the year: ${_amt(feeTotal)}     Paid till date: ${_amt(paidTill)}     Balance: ${_amt(balance)}',
                        style: const pw.TextStyle(fontSize: 9.5, color: grey),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 64),

                // pay mode information
                bandRow('PAY MODE INFORMATION'),
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 8),
                  child: pw.Column(
                    children: [
                      pw.Row(children: [
                        pw.SizedBox(width: 70, child: pw.Text('Pay Mode', style: const pw.TextStyle(fontSize: 10))),
                        pw.Expanded(child: pw.Text(method, style: const pw.TextStyle(fontSize: 10))),
                        pw.SizedBox(width: 60, child: pw.Text('Date', style: const pw.TextStyle(fontSize: 10))),
                        pw.SizedBox(
                          width: 90,
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(_date(r['paid_on']), style: const pw.TextStyle(fontSize: 10)),
                          ),
                        ),
                      ]),
                      if (reference.isNotEmpty) ...[
                        pw.SizedBox(height: 8),
                        pw.Row(children: [
                          pw.SizedBox(width: 70, child: pw.Text('Reference', style: const pw.TextStyle(fontSize: 10))),
                          pw.Expanded(child: pw.Text(reference, style: const pw.TextStyle(fontSize: 10))),
                        ]),
                      ],
                    ],
                  ),
                ),
                pw.Container(
                  color: band,
                  margin: const pw.EdgeInsets.symmetric(horizontal: 10),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text(_amt(amount), style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: line, width: 0.8),
                      bottom: pw.BorderSide(color: line, width: 0.8),
                    ),
                  ),
                  padding: const pw.EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total :', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text(_amt(amount), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: pw.Text('Total in Words: ${amountInWords(amount)}',
                      style: const pw.TextStyle(fontSize: 12)),
                ),
                pw.SizedBox(height: 26),
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: pw.Text(
                    'This is a computer generated receipt. It does not require a signature.',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text('PARENT COPY',
                style: const pw.TextStyle(fontSize: 10, color: grey, letterSpacing: 1)),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}