
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui';
import '../widgets/welcome_button.dart';
import '../widgets/section_title.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  late VideoPlayerController _videoController;
  late AnimationController _fadeController;
  late Animation<double> _fadeInAnimation;

  @override
  void initState() {
    super.initState();

    _videoController = VideoPlayerController.asset('assets/images/bus_intro.mp4') 
      ..initialize().then((_) {
        setState(() {});
        _videoController.setLooping(true);
        _videoController.setVolume(0.0); 
        _videoController.play();
      });

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _fadeInAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _fadeController.forward();
  }

  @override
  void dispose() {
    _videoController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: Colors.white.withOpacity(0.9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFFBB03B), width: 1.5),
          ),
          title: const Text(
            "About Yatra Mitra",
            style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "Yatra Mitra represents the next generation of safe transit infrastructure. By fusing real-time telematics with rapid emergency routing tools, our software directly targets safety and access gaps to give women full environmental control over their daily journeys.",
            style: TextStyle(color: Color(0xFF475569), height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close", style: TextStyle(color: Color(0xFFFBB03B), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showTeamModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                spreadRadius: 5,
              )
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Project Creators",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B), 
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "The Innovators Behind Yatra Mitra",
                style: TextStyle(
                  color: Color(0xFFD97706), 
                  fontSize: 13, 
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              
              _TeamMemberTile(name: "Saba Yasmeen", phone: "8088493591"),
              _TeamMemberTile(name: "Pruthvi B C", phone: "74833 82436"),
              _TeamMemberTile(name: "Aasthishree T P", phone: "93536 56718"),
              _TeamMemberTile(name: "Neha M R", phone: "99729 17022"),
              
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Dismiss", 
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Video Canvas Layer
          SizedBox.expand(
            child: _videoController.value.isInitialized
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _videoController.value.size.width,
                      height: _videoController.value.size.height,
                      child: VideoPlayer(_videoController),
                    ),
                  )
                : Container(color: Colors.black),
          ),

          // 2. Dark Layer Mask
          SizedBox.expand(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    const Color(0xFF0F0C20).withOpacity(0.75),
                    const Color(0xFF06030F).withOpacity(0.95),
                  ],
                ),
              ),
            ),
          ),

          // 3. UI Control Elements Layer
          FadeTransition(
            opacity: _fadeInAnimation,
            child: SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      
                      const SectionTitle(
                        title: "YATRA MITRA",
                        subtitle: "Smart Women's Travel Assistant",
                      ),
                      
                      SizedBox(height: size.height * 0.08),

                      // =========================================================
                      // ✨ "WOW!" HIGH-TECH TYPOGRAPHY SECTION
                      // =========================================================
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 850),
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                // Layer 1: Massive Outer Neon Blur Background Glow
                                Text(
                                  "Empowering Child Safety Through Safe Digital Transportation",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    height: 1.25,
                                    fontFamily: 'sans-serif-condensed',
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = 6
                                      ..color = const Color(0xFF00F0FF).withOpacity(0.3),
                                    shadows: const [
                                      Shadow(color: Color(0xFF00F0FF), blurRadius: 25),
                                      Shadow(color: Color(0xFF5E17EB), blurRadius: 40),
                                    ],
                                  ),
                                ),
                                // Layer 2: Clean Sharp Foreground White Text
                                const Text(
                                  "Empowering Child Safety Through Safe Digital Transportation",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                    height: 1.25,
                                    fontFamily: 'sans-serif-condensed',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              "Yatra Mitra is an AI-powered platform designed to improve Children's safety during travel by providing smart route assistance, emergency support, and digital accessibility.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white.withOpacity(0.75),
                                height: 1.65,
                                letterSpacing: 0.4,
                                fontFamily: 'sans-serif-light',
                                shadows: [
                                  Shadow(color: Colors.black.withOpacity(0.5), offset: const Offset(0, 2), blurRadius: 4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      SizedBox(height: size.height * 0.06),
                      
                      // Feature Cards Grid Array
                      Center(
                        child: Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          alignment: WrapAlignment.center,
                          children: const [
                            _LocalGlassCard(
                              icon: Icons.directions_bus_rounded,
                              title: "Smart Bus Tracking",
                              description: "Track buses with real-time updates.",
                            ),
                            _LocalGlassCard(
                              icon: Icons.shield_rounded,
                              title: "Child's Safety",
                              description: "Emergency assistance and secure travel.",
                            ),
                            _LocalGlassCard(
                              icon: Icons.phone_android_rounded,
                              title: "Digital Empowerment",
                              description: "Helping Child and Parents gain confidence through technology.",
                            ),
                          ],
                        ),
                      ),
                      
                      SizedBox(height: size.height * 0.06),
                      
                      // Performance Metric Statistics Panel
                      Center(
                        child: Wrap(
                          spacing: 40,
                          runSpacing: 20,
                          alignment: WrapAlignment.center,
                          children: const [
                            _LocalStatWidget(metric: "5000+", label: "Women Supported"),
                            _LocalStatWidget(metric: "100+", label: "Routes Active"),
                            _LocalStatWidget(metric: "24x7", label: "Emergency Help"),
                          ],
                        ),
                      ),
                      
                      SizedBox(height: size.height * 0.08),
                      
                      // Interactive Navigation Action Cluster
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          children: [
                            WelcomeButton(
                              text: "LOGIN",
                              isGradient: true,
                              onPressed: () {
                                print("Navigate to Login");
                              },
                            ),
                            const SizedBox(height: 14),
                            WelcomeButton(
                              text: "ABOUT PROJECT",
                              isGradient: false,
                              onPressed: _showAboutDialog,
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _showTeamModal,
                              child: Text(
                                "Learn More",
                                style: TextStyle(
                                  color: Colors.cyanAccent.withOpacity(0.9),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      Text(
                        "Made with ❤️ for Women's Safety",
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamMemberTile extends StatelessWidget {
  final String name;
  final String phone;
  const _TeamMemberTile({required this.name, required this.phone});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline_rounded, color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 14),
              Text(
                name,
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.phone_iphone_rounded, color: Colors.black38, size: 16),
              const SizedBox(width: 6),
              Text(
                phone,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 14,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocalGlassCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  const _LocalGlassCard({
    required this.icon,
    required this.title,
    required this.description,
  });
  @override
  State<_LocalGlassCard> createState() => _LocalGlassCardState();
}

class _LocalGlassCardState extends State<_LocalGlassCard> {
  bool _isHovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        transform: _isHovered ? (Matrix4.identity()..translate(0, -6, 0)) : Matrix4.identity(),
        width: 260,
        height: 180,
        decoration: BoxDecoration(
          boxShadow: _isHovered ? [BoxShadow(color: Colors.purpleAccent.withOpacity(0.15), blurRadius: 15, spreadRadius: 1)] : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(_isHovered ? 0.08 : 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isHovered ? Colors.cyanAccent.withOpacity(0.4) : Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, color: _isHovered ? Colors.cyanAccent : const Color(0xFFA155FF), size: 32),
                  const SizedBox(height: 14),
                  Text(
                    widget.title,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.description,
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalStatWidget extends StatelessWidget {
  final String metric;
  final String label;
  const _LocalStatWidget({required this.metric, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          metric,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.cyanAccent,
            shadows: [Shadow(color: Colors.cyan, blurRadius: 8)],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}