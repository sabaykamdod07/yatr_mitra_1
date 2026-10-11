import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/ym_ui.dart';
import 'change_password_screen.dart';

/// The faculty member's profile: who they are, their route and stop, and (if the
/// admin made them in-charge) the route they look after. Read only. The help desk
/// and the admin keep the faculty record up to date.
class FacultyProfileScreen extends StatelessWidget {
  const FacultyProfileScreen({
    super.key,
    required this.me,
    required this.route,
    required this.stop,
    required this.institution,
    required this.inchargeRoute,
    required this.onLogout,
  });

  final Map<String, dynamic> me;
  final Map<String, dynamic>? route;
  final Map<String, dynamic>? stop;
  final Map<String, dynamic>? institution;
  final Map<String, dynamic>? inchargeRoute;
  final Future<void> Function() onLogout;

  String _v(dynamic v, [String fallback = 'Not added']) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty || s.toLowerCase() == 'null' ? fallback : s;
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Log out?', style: Ym.h(18)),
        content: Text('You will need to sign in again.', style: Ym.t(13.5, color: Ym.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Log out', style: Ym.t(14, color: Ym.red, w: FontWeight.w800))),
        ],
      ),
    );
    if (ok == true) await onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final name = _v(me['faculty_name'], 'Faculty');
    final email = _v(me['faculty_email'] ?? Supabase.instance.client.auth.currentUser?.email);

    Widget row(IconData icon, String label, String value, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              YmIconBadge(icon: icon, color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Ym.t(11, color: Ym.grey)),
                    const SizedBox(height: 2),
                    Text(value, style: Ym.h(13.5)),
                  ],
                ),
              ),
            ],
          ),
        );

    Widget card(List<Widget> rows) => YmCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          radius: 22,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i != rows.length - 1) const Divider(height: 1, color: Ym.line),
              ],
            ],
          ),
        );

    return YmPage(
      title: 'My Profile',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF6E3), Color(0xFFFFE3AE)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Ym.amber.withOpacity(0.45)),
              boxShadow: Ym.shadow(Ym.amberDark, 0.22),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Ym.amber, Ym.amberDark]),
                  ),
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white,
                    child: Text(name[0].toUpperCase(),
                        style: Ym.h(30, color: Ym.amberDark)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(name, textAlign: TextAlign.center, style: Ym.h(21)),
                const SizedBox(height: 3),
                Text(email, style: Ym.t(12.5, color: Ym.grey)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  const YmChip('Faculty', color: Ym.blue, icon: Icons.badge_outlined),
                  if (inchargeRoute != null)
                    YmChip('In-charge of ${inchargeRoute!['route_name'] ?? 'a route'}',
                        color: Ym.green, icon: Icons.verified_user_rounded),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const YmSectionTitle('Details'),
          card([
            row(Icons.person_outline_rounded, 'Full name', name, Ym.blue),
            row(Icons.badge_outlined, 'Employee ID', _v(me['employee_id']), Ym.purple),
            row(Icons.menu_book_rounded, 'Department', _v(me['department']),
                const Color(0xFF0D9488)),
            row(Icons.phone_outlined, 'Phone number', _v(me['faculty_phone']), Ym.amberDark),
            row(Icons.apartment_rounded, 'Institution', _v(institution?['name']), Ym.blue),
          ]),
          const SizedBox(height: 22),
          const YmSectionTitle('Transport'),
          card([
            row(Icons.alt_route_rounded, 'Route', _v(route?['route_name']), Ym.blue),
            row(Icons.pin_drop_outlined, 'Boarding stop',
                _v(stop?['stop_name'] ?? me['boarding_point']), Ym.amberDark),
            row(Icons.access_time_rounded, 'Pickup time', _v(stop?['timing']), Ym.purple),
          ]),
          const SizedBox(height: 26),
          YmButton(
            label: 'Change password',
            icon: Icons.lock_reset_rounded,
            outline: true,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            ),
          ),
          const SizedBox(height: 10),
          YmButton(
            label: 'Log out of account',
            icon: Icons.logout_rounded,
            outline: true,
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }
}