import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

/// Scan a student's bus pass QR and see who it belongs to and whether it is
/// valid right now.
///
/// This only SHOWS the result. It never marks attendance (that is the RFID
/// card's job). The database (`verify_bus_pass`) lets only the driver and the
/// in-charge check a pass, so the same screen can be used in both apps.
class ScanPassScreen extends StatefulWidget {
  const ScanPassScreen({super.key});

  @override
  State<ScanPassScreen> createState() => _ScanPassScreenState();
}

class _ScanPassScreenState extends State<ScanPassScreen> {
  final _sb = Supabase.instance.client;
  final _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final _code = TextEditingController();

  bool _checking = false;
  String? _error;
  Map<String, dynamic>? _result;

  /// 'board' = students getting on, 'alight' = students getting off
  String _mode = 'board';

  /// what was recorded for the last scan (boarded, got off, or why nothing was recorded)
  Map<String, dynamic>? _attend;

  @override
  void dispose() {
    _scanner.dispose();
    _code.dispose();
    super.dispose();
  }

  /// The QR holds "YM1:<token>". Anything else is treated as a bare token.
  String _tokenOf(String raw) {
    final t = raw.trim();
    return t.startsWith('YM1:') ? t.substring(4) : t;
  }

  Future<void> _check(String raw) async {
    final token = _tokenOf(raw);
    if (token.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
      _attend = null;
    });
    try {
      await _scanner.stop();
    } catch (_) {}
    try {
      final rows = await _sb.rpc('verify_bus_pass', params: {'p_token': token}) as List;
      final result = rows.isEmpty ? null : Map<String, dynamic>.from(rows.first as Map);

      // a valid pass is also recorded as boarding or getting off, and the parent is told
      Map<String, dynamic>? attend;
      if (result != null && result['valid'] == true) {
        try {
          final a = await _sb.rpc('scan_pass_attendance',
              params: {'p_token': token, 'p_mode': _mode});
          attend = Map<String, dynamic>.from(a as Map);
        } catch (e) {
          attend = {
            'status': 'error',
            'message': e is PostgrestException ? e.message : e.toString(),
          };
        }
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _attend = attend;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is PostgrestException ? e.message : e.toString();
        _checking = false;
      });
    }
  }

  Future<void> _scanNext() async {
    setState(() {
      _result = null;
      _attend = null;
      _error = null;
      _code.clear();
    });
    try {
      await _scanner.start();
    } catch (_) {}
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  String _date(dynamic v) {
    final d = DateTime.tryParse('$v');
    if (d == null) return '-';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final showResult = _result != null || _error != null || _checking;
    return YmPage(
      title: 'Scan Bus Pass',
      subtitle: 'Check the pass and mark boarding or getting off',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          if (!showResult) ...[
            _modeToggle(),
            const SizedBox(height: 14),
            YmFadeSlide(index: 0, child: _scannerBox()),
            const SizedBox(height: 14),
            Text('Point the camera at the QR on the student\'s pass. '
                'If the camera does not open, paste the code below.',
                style: Ym.t(12.5, color: Ym.grey)),
            const SizedBox(height: 14),
            _manualBox(),
          ] else if (_checking)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: CircularProgressIndicator(color: Ym.amber)),
            )
          else if (_error != null)
            _errorCard()
          else
            YmFadeSlide(index: 0, child: _resultCard()),
        ],
      ),
    );
  }

  Widget _scannerBox() => Container(
        height: 320,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Ym.navy,
          borderRadius: BorderRadius.circular(28),
          boxShadow: Ym.shadow(Ym.navy, 0.2),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _scanner,
              onDetect: (capture) {
                for (final b in capture.barcodes) {
                  final raw = b.rawValue;
                  if (raw != null && raw.isNotEmpty) {
                    _check(raw);
                    break;
                  }
                }
              },
            ),
            // viewfinder frame
            Center(
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Ym.amber, width: 3),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _manualBox() => YmCard(
        padding: const EdgeInsets.all(14),
        radius: 22,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                style: Ym.t(13.5),
                decoration: InputDecoration(
                  hintText: 'Paste the pass code (YM1:…)',
                  hintStyle: Ym.t(13, color: Ym.grey),
                  filled: true,
                  fillColor: const Color(0xFFF8F9FB),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
                onSubmitted: _check,
              ),
            ),
            const SizedBox(width: 10),
            YmButton(
              label: 'Check',
              expanded: false,
              onPressed: () => _check(_code.text),
            ),
          ],
        ),
      );

  Widget _errorCard() => Column(
        children: [
          YmEmpty(
            icon: Icons.error_outline_rounded,
            color: Ym.red,
            title: 'Could not check the pass',
            subtitle: _error,
          ),
          const SizedBox(height: 10),
          YmButton(label: 'Scan again', icon: Icons.qr_code_scanner_rounded, onPressed: _scanNext),
        ],
      );

  /// Boarding / Getting off: what the next scan will record.
  Widget _modeToggle() {
    Widget tab(String mode, IconData icon, String label) {
      final on = _mode == mode;
      return Expanded(
        child: YmPressable(
          onTap: () => setState(() => _mode = mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: on ? const LinearGradient(colors: [Ym.amber, Ym.amberDark]) : null,
              color: on ? null : Colors.white,
              boxShadow: Ym.shadow(Ym.navy, 0.06),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: on ? Ym.navy : Ym.grey),
                const SizedBox(width: 8),
                Text(label,
                    style: Ym.t(13.5, color: on ? Ym.navy : Ym.grey, w: FontWeight.w800)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            tab('board', Icons.login_rounded, 'Boarding'),
            const SizedBox(width: 10),
            tab('alight', Icons.logout_rounded, 'Getting off'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _mode == 'board'
              ? 'Each scan marks the student as on the bus, and the parent is told.'
              : 'Each scan marks the student as got off, and the parent is told.',
          style: Ym.t(12, color: Ym.grey),
        ),
      ],
    );
  }

  /// What was recorded (or why nothing was) after a scan of a valid pass.
  Widget _attendBanner(Map<String, dynamic> a) {
    final status = (a['status'] ?? '').toString();
    final at = parseUtc(a['at']);
    final stop = (a['stop'] ?? '').toString();

    late final Color color;
    late final IconData icon;
    late final String title;
    switch (status) {
      case 'boarded':
        color = Ym.navy;
        icon = Icons.login_rounded;
        title = 'MARKED AS BOARDED';
      case 'alighted':
        color = Ym.blue;
        icon = Icons.logout_rounded;
        title = 'MARKED AS GOT OFF';
      case 'already_on':
        color = Ym.amberDark;
        icon = Icons.info_outline_rounded;
        title = 'ALREADY ON THE BUS';
      case 'already_off':
        color = Ym.amberDark;
        icon = Icons.info_outline_rounded;
        title = 'ALREADY GOT OFF';
      default:
        color = Ym.red;
        icon = Icons.warning_amber_rounded;
        title = 'NOT RECORDED';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.45), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: Ym.h(15, color: color))),
              if (at != null)
                Text(fmtClock(at), style: Ym.t(13, color: color, w: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text((a['message'] ?? '').toString(),
              style: Ym.t(12.5).copyWith(height: 1.4)),
          if (stop.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('At: $stop', style: Ym.t(12, color: Ym.grey)),
          ],
          if (a['other_route'] == true) ...[
            const SizedBox(height: 8),
            const YmChip('Not usually on this route',
                color: Ym.amberDark, icon: Icons.swap_horiz_rounded),
          ],
        ],
      ),
    );
  }

  Widget _resultCard() {
    final r = _result;
    if (r == null) {
      return YmEmpty(
        icon: Icons.help_outline_rounded,
        title: 'No answer',
        subtitle: 'Try scanning again.',
        action: YmButton(
            label: 'Scan again',
            expanded: false,
            icon: Icons.qr_code_scanner_rounded,
            onPressed: _scanNext),
      );
    }
    final valid = r['valid'] == true;
    final color = valid ? Ym.green : Ym.red;
    final hasStudent = r['student_id'] != null;
    final photo = r['photo']?.toString();
    final phone = r['student_phone']?.toString();

    Widget line(IconData icon, String label, String? value) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: Ym.amberDark),
              const SizedBox(width: 10),
              SizedBox(width: 92, child: Text(label, style: Ym.t(12, color: Ym.grey))),
              Expanded(
                child: Text((value == null || value.isEmpty) ? '-' : value,
                    style: Ym.t(13, w: FontWeight.w700)),
              ),
            ],
          ),
        );

    return Column(
      children: [
        // big verdict
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
            boxShadow: Ym.shadow(color, 0.35),
          ),
          child: Column(
            children: [
              Icon(valid ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: Colors.white, size: 46),
              const SizedBox(height: 6),
              Text(valid ? 'VALID PASS' : 'NOT VALID',
                  style: Ym.h(22, color: Colors.white)),
              const SizedBox(height: 4),
              Text(r['reason']?.toString() ?? '',
                  textAlign: TextAlign.center,
                  style: Ym.t(13, color: Colors.white.withOpacity(0.95), w: FontWeight.w600)),
            ],
          ),
        ),
        if (_attend != null) ...[
          const SizedBox(height: 14),
          _attendBanner(_attend!),
        ],
        if (hasStudent) ...[
          const SizedBox(height: 16),
          YmCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 88,
                      height: 108,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Ym.amber, width: 2),
                        image: (photo == null || photo.isEmpty)
                            ? null
                            : DecorationImage(
                                image: NetworkImage(photo), fit: BoxFit.cover),
                      ),
                      child: (photo == null || photo.isEmpty)
                          ? const Icon(Icons.person_rounded, size: 44, color: Ym.grey)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((r['student_name'] ?? '').toString(), style: Ym.h(19)),
                          const SizedBox(height: 6),
                          Text((r['enrollment_no'] ?? '').toString(),
                              style: Ym.t(12.5, color: Ym.grey, w: FontWeight.w600)),
                          const SizedBox(height: 10),
                          YmChip('Valid till ${_date(r['valid_till'])}',
                              color: valid ? Ym.green : Ym.red,
                              icon: Icons.event_available_rounded),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                line(Icons.call_rounded, 'Contact', phone),
                line(Icons.location_on_rounded, 'Boarding point', r['stop_name']?.toString()),
                line(Icons.route_rounded, 'Route', r['route_name']?.toString()),
                line(Icons.directions_bus_rounded, 'Bus number', r['bus_number']?.toString()),
                if (phone != null && phone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: YmButton(
                      label: 'Call student',
                      icon: Icons.call_rounded,
                      outline: true,
                      onPressed: () => _call(phone),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        YmButton(
          label: 'Scan next pass',
          icon: Icons.qr_code_scanner_rounded,
          onPressed: _scanNext,
        ),
      ],
    );
  }
}