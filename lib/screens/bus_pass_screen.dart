import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:iconsax/iconsax.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/ym_ui.dart';
import '../widgets/fee_receipts_card.dart';
import 'student_profile_screen.dart';

/// The student's bus pass.
///
///  * One pass per student, with its own random token. The QR holds only that
///    token ("YM1:<token>"), never the student's details, so it cannot be forged
///    or guessed. A scanner asks the database who it belongs to and whether it is
///    valid right now (`verify_bus_pass`).
///  * The pass exists only while the fee of the current academic year is fully
///    paid. A new year (or an unpaid fee) removes the old pass; paying issues a
///    new one with a new token, so the old QR stops working at once.
///  * Download gives a PDF with the photo, contact number, boarding point and a
///    small QR. One copy is kept in the private `bus-passes` storage bucket and
///    older files are deleted automatically.
class BusPassScreen extends StatefulWidget {
  const BusPassScreen({super.key, this.studentId});

  /// Set by the parent app: show THIS child's pass instead of the logged-in student's.
  final String? studentId;

  @override
  State<BusPassScreen> createState() => _BusPassScreenState();
}

class _BusPassScreenState extends State<BusPassScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  bool _busy = false;
  String? _error;

  Map<String, dynamic>? _student;
  Map<String, dynamic>? _pass; // null while the fee is not fully paid
  Map<String, dynamic>? _fee;
  String? _photoUrl;
  String _institution = '';

  bool get _forParent => widget.studentId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ───────────────────────── DATA ─────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _sb.auth.currentUser;
      if (user?.email == null) throw Exception('Not logged in.');

      final base = _sb
          .from('students')
          .select('*, buses(bus_number), routes(route_name), stops(stop_name,timing)');
      final st = _forParent
          ? await base.eq('id', widget.studentId!).maybeSingle()
          : await base.eq('student_email', user!.email as Object).maybeSingle();
      if (st == null) throw Exception('No student record found.');

      // issues the pass if the year's fee is paid, replaces last year's, or removes it
      final rows = (_forParent
          ? await _sb.rpc('parent_bus_pass', params: {'p_student': widget.studentId})
          : await _sb.rpc('my_bus_pass')) as List;
      final pass = rows.isEmpty ? null : Map<String, dynamic>.from(rows.first as Map);

      // the student's photo (a parent finds it through the student's own login)
      String? photoUserId;
      if (_forParent) {
        if (pass != null) photoUserId = pass['student_user_id']?.toString();
      } else {
        photoUserId = user!.id;
      }
      final prof = photoUserId == null
          ? null
          : await _sb
              .from('profiles')
              .select('photo')
              .eq('user_id', photoUserId)
              .maybeSingle();

      final inst = await _sb
          .from('institutions')
          .select('name')
          .eq('id', st['institution_id'])
          .maybeSingle();

      final fee = await _sb
          .from('student_fee_status')
          .select()
          .eq('student_id', st['id'])
          .maybeSingle();

      if (!_forParent) await _tidyStorage(st['id'].toString(), pass);

      if (!mounted) return;
      setState(() {
        _student = st;
        _photoUrl = prof?['photo'] as String?;
        _institution = (inst?['name'] ?? '').toString();
        _fee = fee;
        _pass = pass;
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

  /// Keeps only this year's pass file in storage. Last year's file, and every
  /// file when there is no valid pass, is deleted.
  Future<void> _tidyStorage(String studentId, Map<String, dynamic>? pass) async {
    try {
      final bucket = _sb.storage.from('bus-passes');
      final files = await bucket.list(path: studentId);
      final keep = pass == null ? null : '${pass['academic_year_id']}.pdf';
      final stale = [
        for (final f in files)
          if (f.name != keep && f.name != '.emptyFolderPlaceholder')
            '$studentId/${f.name}',
      ];
      if (stale.isNotEmpty) await bucket.remove(stale);
    } catch (_) {
      // storage is only a copy; the pass itself never depends on it
    }
  }

  String? get _boarding {
    final fromStop = (_student?['stops'] as Map?)?['stop_name']?.toString();
    if (fromStop != null && fromStop.isNotEmpty) return fromStop;
    return _student?['boarding_point']?.toString();
  }

  String _date(dynamic v) {
    final d = DateTime.tryParse('$v');
    if (d == null) return '-';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  // ───────────────────────── PDF ─────────────────────────

  Future<Uint8List> _buildPdf(Uint8List? photoBytes) async {
    final st = _student!;
    final pass = _pass!;

    const navy = PdfColor.fromInt(0xFF0F1B4D);
    const amber = PdfColor.fromInt(0xFFFFC21E);
    const cream = PdfColor.fromInt(0xFFFFF8EC);
    const grey = PdfColor.fromInt(0xFF6B7390);
    const white = PdfColors.white;

    // the Yatra Mitra logo, shown in the header of the pass
    pw.ImageProvider? logo;
    try {
      final data = await rootBundle.load('assets/images/yatra_logo.png');
      logo = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      logo = null; // the pass still works without it
    }

    pw.ImageProvider? img;
    if (photoBytes != null) {
      try {
        img = pw.MemoryImage(photoBytes);
      } catch (_) {
        img = null; // unsupported picture type: the pass is made without it
      }
    }

    String v(dynamic x) => (x == null || x.toString().trim().isEmpty) ? '-' : x.toString();

    pw.Widget row(String k, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                  width: 70,
                  child: pw.Text(k, style: const pw.TextStyle(fontSize: 8.5, color: grey))),
              pw.Expanded(
                child: pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: navy)),
              ),
            ],
          ),
        );

    final name = v(st['student_name']);
    final qrData = 'YM1:${pass['token']}';
    final passId = pass['token'].toString().substring(0, 8).toUpperCase();

    final doc = pw.Document(title: 'Bus Pass', author: 'Yatra Mitra');
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a6,
        margin: const pw.EdgeInsets.all(14),
        build: (ctx) => pw.Container(
          decoration: pw.BoxDecoration(
            color: cream,
            borderRadius: pw.BorderRadius.circular(14),
            border: pw.Border.all(color: amber, width: 2),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                decoration: const pw.BoxDecoration(
                  color: navy,
                  borderRadius: pw.BorderRadius.only(
                    topLeft: pw.Radius.circular(12),
                    topRight: pw.Radius.circular(12),
                  ),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      width: 34,
                      height: 38,
                      padding: const pw.EdgeInsets.all(3),
                      decoration: pw.BoxDecoration(
                        color: cream,
                        borderRadius: pw.BorderRadius.circular(7),
                      ),
                      child: logo == null ? pw.SizedBox() : pw.Image(logo, fit: pw.BoxFit.contain),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        children: [
                          pw.Text(_institution.toUpperCase(),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                  fontSize: 8.5, color: white, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 3),
                          pw.Text('BUS PASS',
                              style: pw.TextStyle(
                                  fontSize: 16,
                                  color: amber,
                                  fontWeight: pw.FontWeight.bold,
                                  letterSpacing: 2)),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 34), // balances the logo, so the title stays centred
                  ],
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 70,
                      height: 88,
                      decoration: pw.BoxDecoration(
                        color: white,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: amber, width: 1.5),
                      ),
                      child: img != null
                          ? pw.ClipRRect(
                              horizontalRadius: 7,
                              verticalRadius: 7,
                              child: pw.Image(img, fit: pw.BoxFit.cover),
                            )
                          : pw.Center(
                              child: pw.Text('PHOTO',
                                  style: const pw.TextStyle(fontSize: 8, color: grey))),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(name,
                              style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                  color: navy)),
                          pw.SizedBox(height: 4),
                          pw.Text(v(st['enrollment_no']),
                              style: const pw.TextStyle(fontSize: 9, color: grey)),
                          pw.SizedBox(height: 6),
                          pw.Text(
                              [
                                if ((st['department'] ?? '').toString().isNotEmpty)
                                  st['department'].toString(),
                                if ((st['year'] ?? '').toString().isNotEmpty)
                                  st['year'].toString(),
                              ].join('  |  '),
                              style: const pw.TextStyle(fontSize: 8.5, color: grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12),
                child: pw.Column(
                  children: [
                    row('Contact', v(st['student_phone'])),
                    row('Boarding point', v(_boarding)),
                    row('Route', v((st['routes'] as Map?)?['route_name'])),
                    row('Bus number', v((st['buses'] as Map?)?['bus_number'])),
                    row('Academic year', v(pass['academic_year'])),
                    row('Valid till', _date(pass['valid_till'])),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Pass ID  $passId',
                              style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: navy)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                              'Valid only while the fee of the academic year is paid. '
                              'A new pass is issued every year.',
                              style: const pw.TextStyle(fontSize: 7, color: grey)),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(4),
                      decoration: pw.BoxDecoration(
                        color: white,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: qrData,
                        width: 62,
                        height: 62,
                        color: navy,
                        drawText: false,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  Future<void> _download() async {
    final st = _student;
    final pass = _pass;
    if (st == null || pass == null) return;
    setState(() => _busy = true);
    try {
      Uint8List? photo;
      if (_photoUrl != null) {
        try {
          final r = await http.get(Uri.parse(_photoUrl!));
          if (r.statusCode == 200) photo = r.bodyBytes;
        } catch (_) {
          photo = null;
        }
      }
      final bytes = await _buildPdf(photo);

      // one copy in the private storage; older ones are deleted
      // (only the student keeps a stored copy; a parent just receives the file)
      if (!_forParent) {
        try {
          await _sb.storage.from('bus-passes').uploadBinary(
                '${st['id']}/${pass['academic_year_id']}.pdf',
                bytes,
                fileOptions: const FileOptions(upsert: true, contentType: 'application/pdf'),
              );
          await _tidyStorage(st['id'].toString(), pass);
        } catch (_) {}
      }

      await Printing.sharePdf(
        bytes: bytes,
        filename: 'bus-pass-${(st['enrollment_no'] ?? 'student').toString().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf',
      );
    } catch (e) {
      _snack('Could not make the pass: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Ym.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Bus Pass',
      subtitle: 'Your pass for this academic year',
      child: _loading
          ? const YmSkeletonList(count: 2, height: 260)
          : _error != null
              ? YmEmpty(
                  icon: Icons.error_outline_rounded,
                  color: Ym.red,
                  title: 'Could not load your pass',
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
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                    children: [
                      if (_photoUrl == null && !_forParent) _photoBanner(),
                      YmFadeSlide(
                        index: 0,
                        child: _pass == null ? _lockedCard() : _passCard(),
                      ),
                      const SizedBox(height: 18),
                      if (_pass != null) ...[
                        YmFadeSlide(
                          index: 1,
                          child: YmButton(
                            label: 'Download bus pass (PDF)',
                            icon: Icons.download_rounded,
                            loading: _busy,
                            onPressed: _download,
                          ),
                        ),
                        const SizedBox(height: 14),
                        YmFadeSlide(index: 2, child: _purposeCard()),
                      ],
                      // the receipts of the fee payments, to download
                      if (_student != null) ...[
                        const SizedBox(height: 14),
                        YmFadeSlide(
                          index: 3,
                          child: FeeReceiptsCard(studentId: _student!['id'].toString()),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _photoBanner() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Ym.amber.withOpacity(0.16),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_a_photo_outlined, color: Ym.amberDark, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Add your photo so it appears on your pass.',
                  style: Ym.t(12.5, w: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StudentProfileScreen()));
                _load();
              },
              child: Text('Add photo',
                  style: Ym.t(12.5, color: Ym.amberDark, w: FontWeight.w800)),
            ),
          ],
        ),
      );

  Widget _lockedCard() {
    final status = _fee?['fee_status']?.toString() ?? 'unpaid';
    final msg = _forParent
        ? switch (status) {
            'no_year' => 'No academic year is active right now. Please contact the help desk.',
            'fee_not_set' => 'The fee for this route has not been set yet.',
            'partial' => 'Part of the fee is paid. The pass is issued when the full fee for this academic year is paid. You can pay the balance from Payments.',
            _ => 'The pass is issued when the full bus fee for this academic year is paid. You can pay from Payments.',
          }
        : switch (status) {
            'no_year' => 'No academic year is active right now. Please contact your in-charge.',
            'fee_not_set' => 'The fee for your route has not been set yet.',
            'partial' => 'Part of the fee is paid. Your pass is issued when the full fee for this academic year is paid.',
            _ => 'Your pass is issued when the full bus fee for this academic year is paid at the help desk.',
          };
    return YmCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Opacity(
            opacity: 0.18,
            child: QrImageView(
              data: 'YM1:locked',
              size: 130,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Ym.navy),
              dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square, color: Ym.navy),
            ),
          ),
          const SizedBox(height: 16),
          const YmChip('No active pass', color: Ym.red, icon: Icons.lock_outline_rounded),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center, style: Ym.t(13, color: Ym.grey)),
        ],
      ),
    );
  }

  Widget _passCard() {
    final st = _student!;
    final pass = _pass!;
    final name = (st['student_name'] ?? '').toString();

    Widget detail(IconData icon, String label, String? value) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: Ym.amberDark),
              const SizedBox(width: 10),
              SizedBox(
                  width: 96,
                  child: Text(label, style: Ym.t(12, color: Ym.grey))),
              Expanded(
                child: Text((value == null || value.isEmpty) ? '-' : value,
                    style: Ym.t(13, w: FontWeight.w700)),
              ),
            ],
          ),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6E3), Color(0xFFFFE9BD)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Ym.amber.withOpacity(0.6), width: 1.4),
        boxShadow: Ym.shadow(Ym.amberDark, 0.25),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            color: Ym.navy,
            child: Column(
              children: [
                Text(_institution.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: Ym.t(11.5, color: Colors.white, w: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('BUS PASS',
                    style: Ym.h(22, color: Ym.amber).copyWith(letterSpacing: 3)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 92,
                  height: 114,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Ym.amber, width: 2),
                    image: _photoUrl == null
                        ? null
                        : DecorationImage(
                            image: NetworkImage(_photoUrl!), fit: BoxFit.cover),
                  ),
                  child: _photoUrl == null
                      ? const Icon(Icons.person_rounded, size: 46, color: Ym.grey)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Ym.h(19)),
                      const SizedBox(height: 6),
                      Text((st['enrollment_no'] ?? '').toString(),
                          style: Ym.t(12.5, color: Ym.grey, w: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if ((st['department'] ?? '').toString().isNotEmpty)
                            YmChip(st['department'].toString(), color: Ym.blue),
                          if ((st['year'] ?? '').toString().isNotEmpty)
                            YmChip(st['year'].toString(), color: Ym.purple),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Column(
              children: [
                detail(Iconsax.call, 'Contact', st['student_phone']?.toString()),
                detail(Iconsax.location, 'Boarding point', _boarding),
                detail(Icons.route_rounded, 'Route',
                    (st['routes'] as Map?)?['route_name']?.toString()),
                detail(Iconsax.bus, 'Bus number',
                    (st['buses'] as Map?)?['bus_number']?.toString()),
                detail(Icons.calendar_month_rounded, 'Academic year',
                    pass['academic_year']?.toString()),
                detail(Icons.event_available_rounded, 'Valid till',
                    _date(pass['valid_till'])),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Pass ID  ${pass['token'].toString().substring(0, 8).toUpperCase()}',
                          style: Ym.t(12, w: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('Show this QR when you board.',
                          style: Ym.t(11.5, color: Ym.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: Ym.shadow(Ym.navy, 0.1),
                  ),
                  child: QrImageView(
                    data: 'YM1:${pass['token']}',
                    size: 112,
                    padding: EdgeInsets.zero,
                    eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square, color: Ym.navy),
                    dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square, color: Ym.navy),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _purposeCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Ym.blue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.verified_user_outlined, color: Ym.blue, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _forParent
                    ? 'This QR belongs to your child only. It proves the pass is valid and is replaced '
                        'with a new one every academic year after the fee is paid. Last year\'s pass '
                        'stops working and is deleted.'
                    : 'This QR is only yours. It proves your pass is valid and is replaced '
                        'with a new one every academic year after you pay. Last year\'s pass '
                        'stops working and is deleted.',
                style: Ym.t(12.5),
              ),
            ),
          ],
        ),
      );
}