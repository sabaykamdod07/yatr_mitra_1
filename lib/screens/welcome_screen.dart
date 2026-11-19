import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../theme/ym_ui.dart';
import 'role_selection_screen.dart';

/// Welcome page, in the soft cream style of the design:
///   brand row, the headline, a short paragraph, the BUS VIDEO in the picture area,
///   and a curved bottom sheet with three feature cards, the Login button, and the
///   About Project / Learn More links.
/// The video is the same bus clip that used to fill the whole page. Only its
/// middle band holds the scene, so that band is what is shown in the picture area.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with WidgetsBindingObserver {
  // the design's colours
  static const _cream = Color(0xFFFDF3E3);
  static const _sheetColor = Color(0xFFFFF8EC);
  static const _navy = Color(0xFF14284B);
  static const _amber = Color(0xFFFFA826);
  static const _muted = Color(0xFF6B7385);

  late VideoPlayerController _video;
  bool _videoOk = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _video = VideoPlayerController.asset(
      'assets/images/welcome_scene.mp4',
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _video.initialize().then((_) async {
      if (!mounted) return;
      await _video.setLooping(true);
      await _video.setVolume(0);
      await _video.play();
      if (mounted) setState(() => _videoOk = true);
    }).catchError((_) {
      // the picture area simply stays as a soft placeholder
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_video.value.isInitialized) return;
    if (state == AppLifecycleState.resumed) _video.play();
    if (state == AppLifecycleState.paused) _video.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _video.dispose();
    super.dispose();
  }

  // ───────────────────────── pop-ups ─────────────────────────

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YmGradientTile(
                  icon: Icons.directions_bus_rounded, color: Ym.amberDark, size: 56),
              const SizedBox(height: 16),
              Text('About Yatra Mitra', style: Ym.h(21)),
              const SizedBox(height: 10),
              Text(
                'Yatra Mitra represents the next generation of safe transit infrastructure. '
                'By fusing real-time telematics with rapid emergency routing tools, our '
                'software directly targets safety and access gaps to give children full '
                'environmental control over their daily journeys.',
                style: Ym.t(14, color: Ym.grey).copyWith(height: 1.6),
              ),
              const SizedBox(height: 18),
              YmButton(
                label: 'Close',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTeamModal() {
    const members = [
      ('Saba Yasmeen', '8088493591'),
      ('Pruthvi B C', '74833 82436'),
      ('Aasthishree T P', '93536 56718'),
      ('Neha M R', '99729 17022'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(
                    color: Ym.line, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(height: 18),
              Text('Project Creators', style: Ym.h(22)),
              const SizedBox(height: 4),
              Text('The innovators behind Yatra Mitra',
                  style: Ym.t(13, color: Ym.amberDark, w: FontWeight.w700)),
              const SizedBox(height: 20),
              for (final m in members) _TeamMemberTile(name: m.$1, phone: m.$2),
              const SizedBox(height: 8),
              YmButton(label: 'Dismiss', onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }

  void _showFeature(IconData icon, Color tile, String title, String text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 26),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4.5,
                  decoration:
                      BoxDecoration(color: Ym.line, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 60,
                height: 60,
                decoration:
                    BoxDecoration(color: tile, borderRadius: BorderRadius.circular(20)),
                child: Icon(icon, color: _navy, size: 30),
              ),
              const SizedBox(height: 14),
              Text(title, style: Ym.h(20)),
              const SizedBox(height: 8),
              Text(text, style: Ym.t(14, color: Ym.grey).copyWith(height: 1.6)),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── page ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final h = c.maxHeight;
                final bottomInset = MediaQuery.of(context).padding.bottom;

                // the top part (brand, headline, paragraph, video) and the curved sheet
                final heroH = math.max(430.0, math.min(h * 0.55, 520.0));
                final sheetTop = heroH - 34;
                final sheetH = math.max(h - sheetTop, 420.0 + bottomInset);
                final total = sheetTop + sheetH;

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    height: total,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: heroH,
                          child: _hero(w, heroH),
                        ),
                        Positioned(
                          top: sheetTop,
                          left: 0,
                          right: 0,
                          height: sheetH,
                          child: _sheet(bottomInset),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── top part ──

  Widget _hero(double w, double h) {
    final videoW = w * 0.66;
    final videoH = videoW * 528 / 720; // the shape of the video file

    return Stack(
      children: [
        // the bus video, in the picture area (right, under the headline)
        Positioned(
          right: 0,
          bottom: 0, // the curved sheet covers the lowest part, like in the design
          width: videoW,
          height: videoH,
          child: _videoWindow(videoW, videoH),
        ),

        // the dotted route and pin, top right
        Positioned(
          top: 6,
          right: 14,
          width: 120,
          height: 96,
          child: const CustomPaint(painter: _RoutePinPainter()),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _brand(),
              const SizedBox(height: 24),
              _headline(w),
            ],
          ),
        ),
      ],
    );
  }

  Widget _brand() => Row(
        children: [
          // the Yatra Mitra logo
          Image.asset(
            'assets/images/yatra_logo.png',
            height: 62,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                  children: const [
                    TextSpan(text: 'YATRA ', style: TextStyle(color: _navy)),
                    TextSpan(text: 'MITRA', style: TextStyle(color: _amber)),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text('Safe Journeys  \u2022  Smarter Campus',
                  style: GoogleFonts.inter(
                      fontSize: 11.5, color: _muted, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      );

  Widget _headline(double w) {
    final style = GoogleFonts.plusJakartaSans(
      fontSize: w < 360 ? 25 : 28,
      height: 1.18,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
    );
    return RichText(
      text: TextSpan(
        style: style,
        children: const [
          TextSpan(text: 'Empowering\nChildren Through\n', style: TextStyle(color: _navy)),
          TextSpan(text: 'Safe Digital\nTransportation', style: TextStyle(color: _amber)),
        ],
      ),
    );
  }

  /// The picture area. The file is the bus scene cut out of the old welcome video,
  /// with its left and top edges already faded into the page colour, so it is just
  /// played as it is.
  Widget _videoWindow(double w, double h) {
    if (!_videoOk) return Container(color: Colors.transparent);
    return SizedBox(
      width: w,
      height: h,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _video.value.size.width,
          height: _video.value.size.height,
          child: VideoPlayer(_video),
        ),
      ),
    );
  }

  // ── bottom sheet ──

  Widget _sheet(double bottomInset) {
    return Container(
      decoration: BoxDecoration(
        color: _sheetColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(58),
          topRight: Radius.circular(34),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF2B65A).withOpacity(0.16),
            blurRadius: 26,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(58),
          topRight: Radius.circular(34),
        ),
        child: Stack(
          children: [
            // the soft waves and leaves along the bottom
            const Positioned.fill(child: CustomPaint(painter: _BottomArtPainter())),
            Padding(
              padding: EdgeInsets.fromLTRB(18, 22, 18, 12 + bottomInset),
              child: Column(
                children: [
                  IntrinsicHeight(
                   child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _featureCard(
                          icon: Icons.directions_bus_rounded,
                          tile: const Color(0xFFFED888),
                          arrow: const Color(0xFFFEAE1B),
                          title: 'Smart Bus\nTracking',
                          sub: 'Live location &\nroute updates',
                          detail:
                              'See where your bus is, live on the map, and when it will reach your stop. '
                              'Alerts tell you when it starts, when it is near, and when it arrives.',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _featureCard(
                          icon: Icons.shield_outlined,
                          tile: const Color(0xFFA3E5BD),
                          arrow: const Color(0xFF67B298),
                          title: "Children's\nSafety",
                          sub: 'Secure & reliable\ntravel',
                          detail:
                              'An SOS button, boarding alerts for parents, and a bus pass checked by the '
                              'in-charge, so every child travels safely and is accounted for.',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _featureCard(
                          icon: Icons.smartphone_rounded,
                          tile: const Color(0xFFDAC9F6),
                          arrow: const Color(0xFF9E79F7),
                          title: 'Digital\nEmpowerment',
                          sub: 'Easy access for\nparents & students',
                          detail:
                              'Students, parents, faculty, drivers and staff all use one simple app: '
                              'passes, payments, complaints and announcements, with no paperwork.',
                        ),
                      ),
                    ],
                   ),
                  ),
                  const Spacer(),
                  _loginButton(),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _linkItem(Icons.info_outline_rounded, 'About Project', _showAboutDialog),
                      Container(
                        width: 1,
                        height: 26,
                        color: const Color(0xFFE6D9BD),
                        margin: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      _linkItem(Icons.school_outlined, 'Learn More', _showTeamModal),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureCard({
    required IconData icon,
    required Color tile,
    required Color arrow,
    required String title,
    required String sub,
    required String detail,
  }) {
    return GestureDetector(
      onTap: () => _showFeature(icon, tile, title.replaceAll('\n', ' '), detail),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF4),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF3E7D0), width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE9C98A).withOpacity(0.18),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, color: _navy, size: 29),
            ),
            const SizedBox(height: 12),
            // scaleDown: a long word like "Empowerment" shrinks instead of breaking
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: _navy)),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(sub,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 11, height: 1.35, color: _muted)),
            ),
            const SizedBox(height: 10),
            Icon(Icons.arrow_forward_rounded, color: arrow, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _loginButton() => GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        ),
        child: Container(
          width: double.infinity,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _navy,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: _navy.withOpacity(0.30),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Login',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
            ],
          ),
        ),
      );

  Widget _linkItem(IconData icon, String label, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: _navy),
              const SizedBox(width: 8),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w500, color: _navy)),
            ],
          ),
        ),
      );
}

/// The dotted route that ends in a map pin, top right of the page.
class _RoutePinPainter extends CustomPainter {
  const _RoutePinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.92)
      ..cubicTo(size.width * 0.18, size.height * 0.55, size.width * 0.42, size.height * 0.98,
          size.width * 0.58, size.height * 0.62)
      ..cubicTo(size.width * 0.72, size.height * 0.34, size.width * 0.95, size.height * 0.62,
          size.width * 0.88, size.height * 0.30);

    final paint = Paint()
      ..color = const Color(0xFFFFC857).withOpacity(0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), paint);
        d += 10;
      }
    }

    // the pin
    final pc = Offset(size.width * 0.88, size.height * 0.2);
    final pin = Path()
      ..moveTo(pc.dx, pc.dy + 22)
      ..cubicTo(pc.dx - 20, pc.dy + 2, pc.dx - 14, pc.dy - 20, pc.dx, pc.dy - 20)
      ..cubicTo(pc.dx + 14, pc.dy - 20, pc.dx + 20, pc.dy + 2, pc.dx, pc.dy + 22)
      ..close();
    canvas.drawPath(pin, Paint()..color = const Color(0xFFFFA826));
    canvas.drawCircle(pc.translate(0, -4), 5, Paint()..color = const Color(0xFFFFF8EC));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// The soft yellow waves and green leaves along the bottom of the sheet.
class _BottomArtPainter extends CustomPainter {
  const _BottomArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final wave1 = Path()
      ..moveTo(0, h * 0.90)
      ..cubicTo(w * 0.25, h * 0.80, w * 0.5, h * 0.98, w * 0.78, h * 0.86)
      ..cubicTo(w * 0.9, h * 0.81, w * 0.97, h * 0.84, w, h * 0.83)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(wave1, Paint()..color = const Color(0xFFFCEBC6).withOpacity(0.75));

    final wave2 = Path()
      ..moveTo(0, h * 0.95)
      ..cubicTo(w * 0.3, h * 0.88, w * 0.6, h * 1.0, w, h * 0.92)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(wave2, Paint()..color = const Color(0xFFFBE3B0).withOpacity(0.7));

    // leaves, bottom right
    void leaf(Offset base, double len, double wid, double angle, Color c) {
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.rotate(angle);
      final p = Path()
        ..moveTo(0, 0)
        ..cubicTo(-wid, -len * 0.3, -wid * 0.7, -len * 0.8, 0, -len)
        ..cubicTo(wid * 0.7, -len * 0.8, wid, -len * 0.3, 0, 0)
        ..close();
      canvas.drawPath(p, Paint()..color = c);
      canvas.restore();
    }

    final base = Offset(w * 0.93, h * 1.02);
    leaf(base, 78, 22, -0.35, const Color(0xFFA9C79A).withOpacity(0.85));
    leaf(base.translate(10, 0), 92, 24, 0.12, const Color(0xFF8DB27C).withOpacity(0.85));
    leaf(base.translate(-8, 2), 62, 18, -0.75, const Color(0xFFBBD4A9).withOpacity(0.8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _TeamMemberTile extends StatelessWidget {
  final String name;
  final String phone;
  const _TeamMemberTile({required this.name, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Ym.creamTop,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Ym.line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Ym.amber, Ym.amberDark]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(name[0], style: Ym.h(18, color: Ym.navy)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: Ym.h(14.5))),
          const Icon(Icons.phone_rounded, color: Ym.grey, size: 15),
          const SizedBox(width: 5),
          Text(phone, style: Ym.t(12.5, color: Ym.grey, w: FontWeight.w700)),
        ],
      ),
    );
  }
}