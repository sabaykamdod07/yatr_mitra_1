import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/ym_ui.dart';

/// Admin "Drivers" tab.
///
///  * Add Driver  -> calls the `create-driver` edge function, which creates the
///                   login, e-mails the password and saves the driver.
///  * The driver's BUS is never typed in: the database links it automatically
///    from the route (one bus per route).
///  * Edit        -> name, phone, licence and route.
///  * Deactivate  -> the driver can no longer log in, but ALL their records stay.
///                   Reactivate brings them back. Use this when a driver leaves.
///  * Delete      -> removes the driver for good (and, through a database trigger,
///                   the login). Their trip history goes too.
class AdminDriversTab extends StatefulWidget {
  const AdminDriversTab({
    super.key,
    required this.supabase,
    required this.institutionId,
    required this.routes,
    this.onChanged,
  });

  final SupabaseClient supabase;
  final String? institutionId;

  /// Rows with at least `id` and `route_name`.
  final List<Map<String, dynamic>> routes;

  /// Called after a driver is added / edited / deactivated / deleted (to refresh the home counts).
  final VoidCallback? onChanged;

  @override
  State<AdminDriversTab> createState() => _AdminDriversTabState();
}

class _AdminDriversTabState extends State<AdminDriversTab> {
  static const _navy = Color(0xFF0F1B4C);
  static const _amber = Color(0xFFFBB03B);
  static const _grey = Color(0xFF8892AA);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _drivers = [];
  String? _busyId; // the driver being deactivated / reactivated

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminDriversTab old) {
    super.didUpdateWidget(old);
    // The admin screen builds every tab at launch, before the institution is known.
    if (old.institutionId == null && widget.institutionId != null) _load();
  }

  bool _isActive(Map<String, dynamic> d) => d['is_active'] != false;

  Future<void> _load() async {
    final inst = widget.institutionId;
    if (inst == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await widget.supabase
          .from('drivers')
          .select('*, routes(route_name), buses(bus_number)')
          .eq('institution_id', inst)
          .order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows);
      // active drivers first, deactivated ones at the end
      list.sort((a, b) {
        final x = _isActive(a) ? 0 : 1;
        final y = _isActive(b) ? 0 : 1;
        return x.compareTo(y);
      });
      if (!mounted) return;
      setState(() {
        _drivers = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load drivers: $e';
        _loading = false;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ───────────────────────── ADD / EDIT ─────────────────────────

  Future<void> _openDriverDialog({Map<String, dynamic>? driver}) async {
    final editing = driver != null;
    final name = TextEditingController(text: driver?['driver_name']?.toString() ?? '');
    final phone = TextEditingController(text: driver?['driver_phone']?.toString() ?? '');
    final email = TextEditingController(text: driver?['driver_email']?.toString() ?? '');
    final license = TextEditingController(text: driver?['license_number']?.toString() ?? '');
    String? routeId = driver?['route_id']?.toString();
    // If the saved route no longer exists in the list, don't crash the dropdown.
    if (routeId != null &&
        !widget.routes.any((r) => r['id'].toString() == routeId)) {
      routeId = null;
    }
    var saving = false;
    String? error;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModal) {
          InputDecoration deco(String label, IconData icon) => InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon, size: 20, color: _grey),
                filled: true,
                fillColor: const Color(0xFFF8F9FB),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              );

          Future<void> submit() async {
            final n = name.text.trim();
            final p = phone.text.trim();
            final em = email.text.trim().toLowerCase();
            if (n.isEmpty || p.isEmpty) {
              setModal(() => error = 'Name and phone are required.');
              return;
            }
            if (!editing &&
                !RegExp(r'^[\w\.\-+]+@([\w\-]+\.)+[a-zA-Z]{2,}$').hasMatch(em)) {
              setModal(() => error = 'Enter a valid email address.');
              return;
            }
            setModal(() {
              saving = true;
              error = null;
            });
            try {
              if (editing) {
                await widget.supabase.from('drivers').update({
                  'driver_name': n,
                  'driver_phone': p,
                  'license_number': license.text.trim().isEmpty ? null : license.text.trim(),
                  'route_id': routeId,
                  // route -> bus is automatic in the database; clearing the route clears the bus
                  if (routeId == null) 'bus_id': null,
                }).eq('id', driver['id']);
              } else {
                await widget.supabase.functions.invoke('create-driver', body: {
                  'name': n,
                  'phone': p,
                  'email': em,
                  'licenseNumber':
                      license.text.trim().isEmpty ? null : license.text.trim(),
                  'routeId': routeId,
                  'institutionId': widget.institutionId,
                  'adminId': widget.supabase.auth.currentUser!.id,
                });
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _snack(editing
                  ? 'Driver updated.'
                  : 'Driver added. Login details were emailed to $em.');
              await _load();
              widget.onChanged?.call();
            } catch (e) {
              var msg = e.toString();
              if (e is FunctionException) {
                final d = e.details;
                if (d is Map && d['error'] != null) msg = d['error'].toString();
              }
              setModal(() {
                error = msg;
                saving = false;
              });
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Text(editing ? 'Edit Driver' : 'Add Driver',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: _navy)),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: name, decoration: deco('Full name', Icons.person_outline)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration: deco('Phone number', Icons.phone_outlined)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: email,
                        enabled: !editing,
                        keyboardType: TextInputType.emailAddress,
                        decoration: deco(
                            editing ? 'Email (cannot be changed)' : 'Email address',
                            Icons.email_outlined)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: license,
                        decoration: deco('Licence number (optional)', Icons.badge_outlined)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: routeId,
                      isExpanded: true,
                      decoration: deco('Route (optional)', Icons.route_outlined),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('No route yet')),
                        ...widget.routes.map((r) => DropdownMenuItem<String?>(
                              value: r['id'].toString(),
                              child: Text(r['route_name']?.toString() ?? 'Route',
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setModal(() => routeId = v),
                    ),
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'The bus is linked automatically from the route.',
                        style: TextStyle(fontSize: 11.5, color: _grey),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(error!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel', style: TextStyle(color: _grey)),
              ),
              ElevatedButton.icon(
                onPressed: saving ? null : submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _amber,
                  foregroundColor: _navy,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _navy))
                    : Icon(editing ? Icons.save_rounded : Icons.send_rounded,
                        size: 16),
                label: Text(editing ? 'Save changes' : 'Add & email login',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );

    name.dispose();
    phone.dispose();
    email.dispose();
    license.dispose();
  }

  // ───────────────────────── DEACTIVATE / REACTIVATE ─────────────────────────

  Future<void> _setActive(Map<String, dynamic> d, bool active) async {
    final name = (d['driver_name'] ?? 'This driver').toString();

    if (!active) {
      // do not switch someone off in the middle of a trip
      try {
        final running = await widget.supabase
            .from('trips')
            .select('id')
            .eq('driver_id', d['id'])
            .eq('status', 'in_progress')
            .limit(1);
        if (running.isNotEmpty) {
          _snack('$name has a trip running now. Please wait until it ends.', error: true);
          return;
        }
      } catch (_) {
        // if the check is not possible, carry on to the confirmation
      }

      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Deactivate $name?', style: Ym.h(18)),
          content: Text(
            '$name will no longer be able to log in.\n\n'
            'All their trips and records stay. You can reactivate them at any time.',
            style: Ym.t(13.5, color: Ym.grey).copyWith(height: 1.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text('Deactivate',
                    style: Ym.t(14, color: Ym.amberDark, w: FontWeight.w800))),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busyId = d['id'].toString());
    try {
      await widget.supabase.rpc('set_driver_active',
          params: {'p_driver': d['id'], 'p_active': active});
      _snack(active
          ? '$name is active again and can log in.'
          : '$name has been deactivated. Their records are kept.');
      await _load();
      widget.onChanged?.call();
    } on PostgrestException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('Could not change this driver: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // ───────────────────────── DELETE ─────────────────────────

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Delete driver?', style: Ym.h(18)),
        content: Text(
          '${d['driver_name']} will be removed for good and can no longer log in.\n\n'
          'Their past trips and check-in history will also be deleted.\n\n'
          'If the driver has only left, use Deactivate instead. It keeps all the history.',
          style: Ym.t(13.5, color: Ym.grey).copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: Ym.t(14, color: Ym.red, w: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.supabase.from('drivers').delete().eq('id', d['id']);
      _snack('Driver deleted.');
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      _snack('Could not delete: $e', error: true);
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final active = _drivers.where(_isActive).length;
    final inactive = _drivers.length - active;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                const YmIconBadge(icon: Icons.local_taxi_rounded, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Drivers', style: Ym.h(22)),
                      Text(
                        _loading
                            ? 'Loading'
                            : '$active active${inactive > 0 ? '  •  $inactive inactive' : ''}',
                        style: Ym.t(12.5, color: Ym.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: YmButton(
              label: 'Add Driver',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: widget.institutionId == null ? null : () => _openDriverDialog(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: YmSkeletonList(count: 3, height: 150),
                  )
                : _error != null
                    ? YmEmpty(
                        icon: Icons.cloud_off_rounded,
                        color: Ym.red,
                        title: 'Could not load drivers',
                        subtitle: _error,
                        action: YmButton(
                            label: 'Try again',
                            icon: Icons.refresh_rounded,
                            expanded: false,
                            onPressed: _load),
                      )
                    : RefreshIndicator(
                        color: Ym.amber,
                        onRefresh: _load,
                        child: _drivers.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 40),
                                  YmEmpty(
                                    icon: Icons.local_taxi_rounded,
                                    color: Ym.amberDark,
                                    title: 'No drivers added yet',
                                    subtitle: 'Press Add Driver. Their login is emailed to them.',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                                itemCount: _drivers.length,
                                itemBuilder: (_, i) => YmFadeSlide(
                                  index: i > 6 ? 6 : i,
                                  child: _card(_drivers[i]),
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _action(String label, IconData icon, Color color, VoidCallback? onTap) => Expanded(
        child: YmPressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(onTap == null ? 0.06 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Icon(icon, size: 19, color: onTap == null ? Ym.grey : color),
                const SizedBox(height: 3),
                Text(label,
                    style: Ym.t(11.5,
                        color: onTap == null ? Ym.grey : color, w: FontWeight.w800)),
              ],
            ),
          ),
        ),
      );

  Widget _card(Map<String, dynamic> d) {
    final route = (d['routes'] as Map?)?['route_name']?.toString();
    final bus = (d['buses'] as Map?)?['bus_number']?.toString();
    final active = _isActive(d);
    final busy = _busyId == d['id'].toString();
    final name = (d['driver_name'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: active ? 1 : 0.72,
        child: YmCard(
          padding: const EdgeInsets.all(16),
          radius: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: active
                          ? const LinearGradient(colors: [Ym.amber, Ym.amberDark])
                          : const LinearGradient(
                              colors: [Color(0xFFCBD2DF), Color(0xFF9AA3B5)]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: Ym.h(20, color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: Ym.h(15.5)),
                        const SizedBox(height: 2),
                        Text((d['driver_phone'] ?? '-').toString(),
                            style: Ym.t(12.5, color: Ym.amberDark, w: FontWeight.w700)),
                        Text((d['driver_email'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ym.t(11.5, color: Ym.grey)),
                      ],
                    ),
                  ),
                  YmChip(active ? 'Active' : 'Inactive',
                      color: active ? Ym.green : Ym.grey,
                      icon: active ? Icons.check_circle_outline_rounded : Icons.block_rounded),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                YmChip(route == null ? 'No route assigned' : route,
                    color: route == null ? Ym.grey : Ym.blue, icon: Icons.alt_route_rounded),
                if (bus != null)
                  YmChip(bus, color: Ym.green, icon: Icons.directions_bus_rounded),
                if ((d['license_number'] ?? '').toString().isNotEmpty)
                  YmChip(d['license_number'].toString(),
                      color: Ym.purple, icon: Icons.badge_outlined),
              ]),
              if (!active) ...[
                const SizedBox(height: 10),
                Text('Cannot log in. Their records are kept.',
                    style: Ym.t(11.5, color: Ym.grey)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _action('Edit', Icons.edit_outlined, Ym.blue,
                      busy ? null : () => _openDriverDialog(driver: d)),
                  const SizedBox(width: 8),
                  active
                      ? _action('Deactivate', Icons.person_off_outlined, Ym.amberDark,
                          busy ? null : () => _setActive(d, false))
                      : _action('Reactivate', Icons.person_add_alt_1_outlined, Ym.green,
                          busy ? null : () => _setActive(d, true)),
                  const SizedBox(width: 8),
                  _action('Delete', Icons.delete_outline_rounded, Ym.red,
                      busy ? null : () => _delete(d)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}