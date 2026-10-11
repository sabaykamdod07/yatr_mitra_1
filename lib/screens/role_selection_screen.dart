import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/ym_ui.dart';
import 'login_screen.dart';

/// "Select your role to continue": a light cream page with six role cards.
/// Each card has a soft coloured icon tile, an arrow chip, the role name and one
/// line about it. Pressing or hovering a card outlines it in orange.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  static const _cream = Color(0xFFFBF6EA);
  static const _navy = Color(0xFF14153A);
  static const _grey = Color(0xFF5B6275);

  // label shown, role passed to the login page, icon, description, tile colours
  static const _roles = <(String, String, IconData, String, Color, Color)>[
    ('Student', 'Student', Icons.school_rounded, 'Track your daily commute',
        Color(0xFFE2AE4A), Color(0xFFC9922D)),
    ('Parent', 'Parent', Icons.family_restroom_rounded,
        "Monitor your child's safety", Color(0xFF8DAA8F), Color(0xFF6E8D71)),
    ('Driver', 'Driver', Icons.directions_bus_rounded,
        'Manage your active route', Color(0xFFD8734A), Color(0xFFBF5B33)),
    ('Faculty', 'Faculty', Icons.apartment_rounded, 'Transit schedule updates',
        Color(0xFF7C9BC6), Color(0xFF5F7FAE)),
    ('Helpdesk', 'Help Desk', Icons.headset_mic_rounded,
        'Input data & support users', Color(0xFF5FA8A6), Color(0xFF408886)),
    ('Admin', 'Admin', Icons.admin_panel_settings_rounded,
        'Full infrastructure control', Color(0xFFA596C6), Color(0xFF8576AA)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: Stack(
        children: [
          // the soft line drawing of the college and the bus (your role_bg.png).
          // It is scaled up from the bottom so the small logo that is part of the
          // picture is pushed off the top.
          Positioned.fill(
            child: ClipRect(
              child: Transform.scale(
                scale: 1.3,
                alignment: Alignment.bottomCenter,
                child: Image.asset('assets/images/role_bg.png', fit: BoxFit.cover),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: _navy, size: 22),
                            onPressed: () => Navigator.maybePop(context),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Yatra Mitra',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: _navy,
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                    )),
                                Text('Select your role to continue',
                                    style: GoogleFonts.inter(
                                      color: _grey,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    )),
                              ],
                            ),
                          ),
                          // the Yatra Mitra logo
                          Image.asset(
                            'assets/images/yatra_logo.png',
                            height: 58,
                            filterQuality: FilterQuality.high,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: _roles.length,
                        itemBuilder: (context, i) {
                          final r = _roles[i];
                          return YmFadeSlide(
                            index: i,
                            child: _RoleCard(
                              label: r.$1,
                              loginRole: r.$2,
                              icon: r.$3,
                              description: r.$4,
                              colorA: r.$5,
                              colorB: r.$6,
                            ),
                          );
                        },
                      ),
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

class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.label,
    required this.loginRole,
    required this.icon,
    required this.description,
    required this.colorA,
    required this.colorB,
  });

  final String label;
  final String loginRole;
  final IconData icon;
  final String description;
  final Color colorA;
  final Color colorB;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _hover = false;
  bool _down = false;

  static const _orange = Color(0xFFD2692F);
  static const _border = Color(0xFFE6D9BD);
  static const _navy = Color(0xFF14153A);
  static const _grey = Color(0xFF5B6275);

  @override
  Widget build(BuildContext context) {
    final active = _hover || _down;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LoginScreen(selectedRole: widget.loginRole),
          ),
        ),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF3).withOpacity(0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: active ? _orange : _border,
                width: active ? 1.8 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: active
                      ? _orange.withOpacity(0.18)
                      : const Color(0xFF8A6A2F).withOpacity(0.07),
                  blurRadius: active ? 20 : 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [widget.colorA, widget.colorB],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: widget.colorB.withOpacity(0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 27),
                    ),
                    const Spacer(),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? _orange : const Color(0xFFEFE6D6),
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: active ? Colors.white : _navy,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: _grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}