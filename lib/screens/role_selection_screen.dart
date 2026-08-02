import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  final List<Map<String, dynamic>> roles = const [
    {
      "name": "Student",
      "icon": Icons.school_rounded,
      "desc": "Track your daily commute",
      "color": Color(0xFF6C63FF),
    },
    {
      "name": "Parent",
      "icon": Icons.family_restroom_rounded,
      "desc": "Monitor your child's safety",
      "color": Color(0xFF00C9A7),
    },
    {
      "name": "Driver",
      "icon": Icons.directions_bus_rounded,
      "desc": "Manage your active route",
      "color": Color(0xFFFF6B6B),
    },
    {
      "name": "Faculty",
      "icon": Icons.badge_rounded,
      "desc": "Transit schedule updates",
      "color": Color(0xFFFFBE0B),
    },
    {
      "name": "Helpdesk",
      "icon": Icons.support_agent_rounded,
      "desc": "Input data & support users",
      "color": Color(0xFF4CC9F0),
    },
    {
      "name": "Admin",
      "icon": Icons.admin_panel_settings_rounded,
      "desc": "Full infrastructure control",
      "color": Color(0xFFFF9F1C),
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Stack(
        children: [
          // Static background image (replaces the old looping video).
          // NOTE: the artwork has its own "Yatra Mitra" logo near the top,
          // which would duplicate the header title below. We scale the
          // image up and anchor the scale at the BOTTOM so the top of the
          // frame (and that logo) gets pushed up and clipped away by
          // ClipRect, leaving just the road/skyline illustration visible.
          Positioned.fill(
            child: ClipRect(
              child: Transform.scale(
                scale: 1.45,
                alignment: Alignment.bottomCenter,
                child: Image.asset(
                  'assets/images/role_bg.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          // Soft gradient overlay — keeps the header text and cards
          // legible while still letting the illustration show through.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.55),
                    Colors.black.withOpacity(0.25),
                    Colors.black.withOpacity(0.20),
                    Colors.black.withOpacity(0.45),
                  ],
                  stops: const [0.0, 0.25, 0.6, 1.0],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Back button + title
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Yatra Mitra',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black45,
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Select your role to continue',
                              style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Role cards grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: roles.length,
                      itemBuilder: (context, index) {
                        return _RoleCard(
                          name: roles[index]["name"],
                          icon: roles[index]["icon"],
                          description: roles[index]["desc"],
                          color: roles[index]["color"],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  final String name;
  final IconData icon;
  final String description;
  final Color color;

  const _RoleCard({
    required this.name,
    required this.icon,
    required this.description,
    required this.color,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: _isHovered
            ? (Matrix4.identity()..translate(0, -4, 0))
            : Matrix4.identity(),
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LoginScreen(selectedRole: widget.name),
              ),
            );
          },
          child: ClipRRect(
            // Frosted-glass card: a subtle blur behind a semi-transparent
            // white fill reads clearly against the lighter background,
            // instead of the low-opacity flat fill that used to blend
            // into the dark overlay.
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isHovered
                      ? widget.color.withOpacity(0.30)
                      : Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isHovered
                        ? widget.color
                        : Colors.white.withOpacity(0.30),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _isHovered
                          ? widget.color.withOpacity(0.35)
                          : Colors.black.withOpacity(0.18),
                      blurRadius: _isHovered ? 18 : 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.color.withOpacity(0.28),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.icon,
                        color: _isHovered ? widget.color : Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                        color: _isHovered ? widget.color : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.description,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: _isHovered
                            ? Colors.white.withOpacity(0.9)
                            : Colors.white.withOpacity(0.75),
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                        letterSpacing: 0.05,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}