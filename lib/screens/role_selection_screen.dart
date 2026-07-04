import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'login_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  late VideoPlayerController _videoController;
  bool _videoReady = false;

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
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    _videoController = VideoPlayerController.asset(
      'assets/images/role_bg.mp4',
    );
    await _videoController.initialize();
    _videoController.setLooping(true);
    _videoController.setVolume(0);
    _videoController.play();
    if (mounted) {
      setState(() => _videoReady = true);
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Stack(
        children: [
          // Video background
          if (_videoReady)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController.value.size.width,
                  height: _videoController.value.size.height,
                  child: VideoPlayer(_videoController),
                ),
              ),
            ),

          // Dark overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.65),
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
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Yatra Mitra 🚍',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Select your role to continue',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
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
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isHovered
                  ? widget.color.withOpacity(0.25)
                  : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isHovered
                    ? widget.color
                    : Colors.white.withOpacity(0.15),
                width: 1.5,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: widget.color.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.icon,
                    color: _isHovered ? widget.color : Colors.white70,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _isHovered ? widget.color : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.description,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: _isHovered
                        ? Colors.white70
                        : Colors.white38,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
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