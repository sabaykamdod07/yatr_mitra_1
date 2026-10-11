import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';
import 'change_password_screen.dart';

/// The parent's profile: who the parent is, each child, and the child's bus
/// arrangement and fee / pass status. Read-only. The help desk keeps the
/// student record and the fees up to date.
class ParentProfileScreen extends StatefulWidget {
  const ParentProfileScreen({
    super.key,
    required this.children,
    required this.selected,
    required this.institution,
    required this.onLogout,
  });

  final List<Map<String, dynamic>> children;
  final int selected;
  final Map<String, dynamic>? institution;
  final Future<void> Function() onLogout;

  @override
  State<ParentProfileScreen> createState() => _ParentProfileScreenState();
}

class _ParentProfileScreenState extends State<ParentProfileScreen> {
  final _sb = Supabase.instance.client;

  late int _sel = widget.selected;
  bool _loading = true;
  Map<String, dynamic>? _fee;
  StudentContext? _ctx;

  Map<String, dynamic> get _child => widget.children[_sel];

  @override
  void initState() {
    super.initState();
    _loadChild();
  }

  Future<void> _loadChild() async {
    setState(() => _loading = true);
    try {
      final ctx = await StudentContext.load(studentId: _child['id'].toString());
      Map<String, dynamic>? fee;
      try {
        fee = await _sb
            .from('student_fee_status')
            .select()
            .eq('student_id', _child['id'])
            .maybeSingle();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _fee = fee;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _v(dynamic v, [String fallback = 'Not added']) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty || s.toLowerCase() == 'null' ? fallback : s;
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Log out?', style: Ym.h(18)),
        content: Text('You will need to sign in again to see your child\'s bus.',
            style: Ym.t(13.5, color: Ym.grey)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Log out',
                  style: Ym.t(14, color: Ym.red, w: FontWeight.w800))),
        ],
      ),
    );
    if (ok == true) await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final c = _child;
    final email = _v(c['parent_email'] ?? _sb.auth.currentUser?.email);
    final parentName = _v(c['parent_name'], 'Parent account');

    final status = (_fee?['fee_status'] ?? 'unknown').toString();
    final paid = status == 'paid';
    final till = DateTime.tryParse('${_fee?['valid_till']}');

    return YmPage(
      title: 'My Profile',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          // parent header
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
                    child: Text(
                      parentName.isEmpty ? 'P' : parentName[0].toUpperCase(),
                      style: Ym.h(30, color: Ym.amberDark),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(parentName, textAlign: TextAlign.center, style: Ym.h(21)),
                const SizedBox(height: 3),
                Text(email, style: Ym.t(12.5, color: Ym.grey)),
                const SizedBox(height: 12),
                const YmChip('Parent account',
                    color: Ym.green, icon: Icons.verified_user_rounded),
              ],
            ),
          ),
          const SizedBox(height: 22),

          if (widget.children.length > 1) ...[
            const YmSectionTitle('My children'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < widget.children.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: YmPressable(
                        onTap: () {
                          if (i == _sel) return;
                          setState(() => _sel = i);
                          _loadChild();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: i == _sel
                                ? const LinearGradient(
                                    colors: [Ym.amber, Ym.amberDark])
                                : null,
                            color: i == _sel ? null : Colors.white,
                            boxShadow: Ym.shadow(Ym.navy, 0.07),
                          ),
                          child: Text(
                            _v(widget.children[i]['student_name'], 'Student')
                                .split(' ')
                                .first,
                            style: Ym.t(13,
                                color: i == _sel ? Ym.navy : Ym.grey,
                                w: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          const YmSectionTitle('Parent information'),
          _card([
            _row(Icons.person_outline_rounded, 'Full name', parentName, Ym.blue),
            _row(Icons.email_outlined, 'Email address', email,
                const Color(0xFF0D9488)),
            _row(Icons.phone_outlined, 'Phone number', _v(c['parent_phone']),
                Ym.amberDark),
          ]),
          const SizedBox(height: 22),

          const YmSectionTitle('Student details'),
          _card([
            _row(Icons.school_rounded, 'Student name', _v(c['student_name']),
                Ym.blue),
            _row(Icons.badge_outlined, 'Enrollment number',
                _v(c['enrollment_no'] ?? c['usn']), Ym.purple),
            _row(Icons.menu_book_rounded, 'Department / year',
                '${_v(c['department'], '-')}  •  ${_v(c['year'], '-')}',
                const Color(0xFF0D9488)),
            _row(Icons.apartment_rounded, 'Institution',
                _v(widget.institution?['name']), Ym.amberDark),
          ]),
          const SizedBox(height: 22),

          const YmSectionTitle('Transport'),
          _loading
              ? const YmSkeleton(height: 190)
              : _card([
                  _row(Icons.directions_bus_rounded, 'Bus number',
                      _v(_ctx?.bus?['bus_number']), Ym.green),
                  _row(Icons.alt_route_rounded, 'Route',
                      _v(_ctx?.route?['route_name']), Ym.blue),
                  _row(Icons.pin_drop_outlined, 'Boarding stop',
                      _v(_ctx?.stop?['stop_name']), Ym.amberDark),
                  _row(Icons.access_time_rounded, 'Pickup time',
                      _v(_ctx?.stop?['timing']), Ym.purple),
                  _row(Icons.person_rounded, 'Driver', _v(_ctx?.driverName),
                      const Color(0xFF0D9488)),
                ]),
          const SizedBox(height: 22),

          const YmSectionTitle('Bus pass & fee'),
          YmCard(
            padding: const EdgeInsets.all(16),
            radius: 22,
            child: _loading
                ? const SizedBox(height: 60)
                : Column(
                    children: [
                      Row(
                        children: [
                          YmIconBadge(
                            icon: paid
                                ? Icons.verified_rounded
                                : Icons.pending_actions_rounded,
                            color: paid ? Ym.green : Ym.amberDark,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(_v(_fee?['academic_year'], 'This year'),
                                style: Ym.h(14.5)),
                          ),
                          YmChip(
                            paid
                                ? 'PAID'
                                : status == 'partial'
                                    ? 'PARTLY PAID'
                                    : status == 'unpaid'
                                        ? 'FEE DUE'
                                        : 'NOT SET',
                            color: paid ? Ym.green : Ym.amberDark,
                          ),
                        ],
                      ),
                      const Divider(height: 26, color: Ym.line),
                      _kv('Fee for the year',
                          _fee?['fee_due'] == null ? 'Not set' : '₹ ${_fee!['fee_due']}'),
                      const SizedBox(height: 10),
                      _kv('Paid so far', '₹ ${_fee?['amount_paid'] ?? 0}'),
                      const SizedBox(height: 10),
                      _kv('Bus pass valid till',
                          till == null ? 'Not active' : fmtDate(till)),
                    ],
                  ),
          ),
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
            onPressed: _confirmLogout,
          ),
          const SizedBox(height: 10),
          Text(
            'Some details may show as "Not added" if they are missing from the student record. '
            'Please ask the help desk to update them.',
            textAlign: TextAlign.center,
            style: Ym.t(11, color: Ym.grey).copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Row(
        children: [
          Expanded(child: Text(k, style: Ym.t(13, color: Ym.grey))),
          Text(v, style: Ym.h(13.5)),
        ],
      );

  Widget _row(IconData icon, String label, String value, Color color) => Padding(
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

  Widget _card(List<Widget> rows) => YmCard(
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
}