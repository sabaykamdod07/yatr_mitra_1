import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';
import '../widgets/parent_child_picker.dart';

/// Who to call, in one place: the child's driver, the help desk, the school
/// office and the emergency numbers. Everything is one tap to call.
class ParentContactScreen extends StatefulWidget {
  const ParentContactScreen({
    super.key,
    required this.children,
    required this.selected,
    required this.onComplaint,
  });

  final List<Map<String, dynamic>> children;
  final int selected;

  /// opens the Complaints screen (a shortcut at the bottom of this page)
  final VoidCallback onComplaint;

  @override
  State<ParentContactScreen> createState() => _ParentContactScreenState();
}

class _ParentContactScreenState extends State<ParentContactScreen> {
  final _sb = Supabase.instance.client;

  late int _sel = widget.selected;
  bool _loading = true;
  String? _error;
  StudentContext? _ctx;
  Map<String, dynamic>? _institution;
  List<Map<String, dynamic>> _helpDesk = [];

  Map<String, dynamic> get _child => widget.children[_sel];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ctx = await StudentContext.load(studentId: _child['id'].toString());
      final instId = _child['institution_id'];

      Map<String, dynamic>? inst;
      var desk = <Map<String, dynamic>>[];
      if (instId != null) {
        try {
          inst = await _sb
              .from('institutions')
              .select()
              .eq('id', instId)
              .maybeSingle();
        } catch (_) {}
        try {
          final rows = await _sb
              .from('helpdesk_accounts')
              .select()
              .eq('institution_id', instId);
          desk = [
            for (final r in rows)
              if (r['is_active'] != false) Map<String, dynamic>.from(r),
          ];
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _institution = inst;
        _helpDesk = desk;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _call(String? phone) async {
    final p = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: p));
  }

  Future<void> _mail(String? email) async {
    if ((email ?? '').isEmpty) return;
    await launchUrl(Uri(scheme: 'mailto', path: email));
  }

  String _first(Map<String, dynamic>? m, List<String> keys) {
    for (final k in keys) {
      final v = m?[k]?.toString().trim() ?? '';
      if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final instPhone = _first(_institution, ['phone', 'contact_phone', 'office_phone']);
    final instEmail = _first(_institution, ['email', 'contact_email', 'office_email']);

    return YmPage(
      title: 'Help & Contact',
      subtitle: 'Who to call',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: YmSkeletonList(count: 3, height: 90),
            )
          : _error != null
              ? YmEmpty(
                  icon: Icons.cloud_off_rounded,
                  color: Ym.red,
                  title: 'Could not load contacts',
                  subtitle: _error,
                  action: YmButton(
                      label: 'Try again',
                      icon: Icons.refresh_rounded,
                      expanded: false,
                      onPressed: _load),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  children: [
                    ParentChildPicker(
                      children: widget.children,
                      selected: _sel,
                      onChanged: (i) {
                        setState(() => _sel = i);
                        _load();
                      },
                    ),

                    const YmSectionTitle('Bus driver'),
                    _person(
                      icon: Icons.directions_bus_rounded,
                      color: Ym.green,
                      title: (_ctx?.driverName ?? '').isEmpty
                          ? 'No driver assigned'
                          : _ctx!.driverName!,
                      sub: _ctx?.bus?['bus_number']?.toString() ?? 'Bus not assigned',
                      phone: _ctx?.driverPhone,
                    ),
                    const SizedBox(height: 22),

                    const YmSectionTitle('Transport help desk'),
                    if (_helpDesk.isEmpty)
                      YmCard(
                        child: Text(
                          'The school has not added help desk contacts yet.',
                          style: Ym.t(13, color: Ym.grey),
                        ),
                      )
                    else
                      for (final h in _helpDesk)
                        _person(
                          icon: Icons.support_agent_rounded,
                          color: Ym.blue,
                          title: (h['name'] ?? 'Help desk').toString(),
                          sub: (h['email'] ?? '').toString(),
                          phone: h['phone']?.toString(),
                          email: h['email']?.toString(),
                        ),
                    const SizedBox(height: 22),

                    const YmSectionTitle('School'),
                    _person(
                      icon: Icons.apartment_rounded,
                      color: Ym.purple,
                      title: _first(_institution, ['name']).isEmpty
                          ? 'School office'
                          : _first(_institution, ['name']),
                      sub: _first(_institution, ['city']),
                      phone: instPhone,
                      email: instEmail,
                    ),
                    const SizedBox(height: 22),

                    const YmSectionTitle('Emergency numbers'),
                    Row(
                      children: [
                        _sos('112', 'Emergency'),
                        const SizedBox(width: 10),
                        _sos('108', 'Ambulance'),
                        const SizedBox(width: 10),
                        _sos('100', 'Police'),
                      ],
                    ),
                    const SizedBox(height: 24),

                    YmCard(
                      onTap: widget.onComplaint,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const YmIconBadge(
                              icon: Icons.mail_outline_rounded,
                              color: Ym.amberDark),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Something wrong with the bus?',
                                    style: Ym.h(14.5)),
                                Text('Send a complaint to the school.',
                                    style: Ym.t(12, color: Ym.grey)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Ym.grey),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _person({
    required IconData icon,
    required Color color,
    required String title,
    required String sub,
    String? phone,
    String? email,
  }) {
    final hasPhone = (phone ?? '').trim().isNotEmpty;
    final hasEmail = (email ?? '').trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: YmCard(
        padding: const EdgeInsets.all(14),
        radius: 22,
        child: Row(
          children: [
            YmIconBadge(icon: icon, color: color, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Ym.h(14.5)),
                  if (sub.isNotEmpty)
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ym.t(12, color: Ym.grey)),
                  if (hasPhone)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(phone!, style: Ym.t(12.5, w: FontWeight.w700)),
                    ),
                  if (!hasPhone)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Phone number not added',
                          style: Ym.t(11.5, color: Ym.grey)),
                    ),
                ],
              ),
            ),
            if (hasEmail)
              _round(Icons.mail_outline_rounded, Ym.blue, () => _mail(email)),
            if (hasPhone) ...[
              const SizedBox(width: 8),
              _round(Icons.call_rounded, Ym.green, () => _call(phone)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _round(IconData icon, Color color, VoidCallback onTap) => YmPressable(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      );

  Widget _sos(String number, String label) => Expanded(
        child: YmPressable(
          onTap: () => _call(number),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Ym.red.withOpacity(0.25)),
            ),
            child: Column(
              children: [
                Text(number, style: Ym.h(20, color: Ym.red)),
                const SizedBox(height: 2),
                Text(label, style: Ym.t(11.5, color: Ym.grey)),
              ],
            ),
          ),
        ),
      );
}