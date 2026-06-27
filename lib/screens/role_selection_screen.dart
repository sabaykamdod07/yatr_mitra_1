import 'package:flutter/material.dart';
import 'login_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  final List<Map<String, dynamic>> roles = const [
    {"name": "Student", "icon": Icons.school_rounded, "desc": "Track your daily commute"},
    {"name": "Parent", "icon": Icons.family_restroom_rounded, "desc": "Monitor your child's safety"},
    {"name": "Driver", "icon": Icons.directions_bus_rounded, "desc": "Manage your active route"},
    {"name": "Faculty", "icon": Icons.badge_rounded, "desc": "Transit schedule updates"},
    {"name": "Helpdesk", "icon": Icons.support_agent_rounded, "desc": "Input data & support users"},
    {"name": "Admin", "icon": Icons.admin_panel_settings_rounded, "desc": "Full infrastructure control"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              const Text(
                "Select Your Role",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Choose an account profile to continue to the portal",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: GridView.builder(
                  physics: const BouncingScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 250,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: roles.length,
                  itemBuilder: (context, index) {
                    return _RoleCard(
                      name: roles[index]["name"],
                      icon: roles[index]["icon"],
                      description: roles[index]["desc"],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  final String name;
  final IconData icon;
  final String description;

  const _RoleCard({
    required this.name,
    required this.icon,
    required this.description,
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
                builder: (_) =>
                    LoginScreen(selectedRole: widget.name),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white
                  : const Color(0xFFEDF2F7).withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isHovered
                    ? const Color(0xFFD97706)
                    : Colors.black.withOpacity(0.03),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isHovered
                      ? const Color(0xFFD97706).withOpacity(0.12)
                      : Colors.black.withOpacity(0.01),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isHovered
                        ? const Color(0xFFFEF3C7)
                        : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.icon,
                    color: _isHovered
                        ? const Color(0xFFD97706)
                        : const Color(0xFF475569),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.description,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                    height: 1.2,
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