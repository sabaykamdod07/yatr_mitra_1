import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';

class _C {
  static const bg = Color(0xFFFFF8F1);
  static const navy = Color(0xFF0F1B4D);
  static const orange = Color(0xFFFF9800);
  static const grey = Color(0xFF8E94A9);
  static const green = Color(0xFF0E9F6E);
  static const red = Color(0xFFE53935);
  static const blue = Color(0xFF3B6FF5);
}

/// Emergency SOS.
///
/// Every alert is a row in `emergencies`, with the bus's latest GPS position
/// (from `live_locations`) attached. A database trigger then notifies the
/// admin. When GPS hardware is connected the
/// location simply becomes the hardware's location – no change here.
class EmergencySosScreen extends StatefulWidget {
  const EmergencySosScreen({super.key});

  @override
  State<EmergencySosScreen> createState() => _EmergencySosScreenState();
}

class _EmergencySosScreenState extends State<EmergencySosScreen> {
  final _sb = Supabase.instance.client;

  StudentContext? _ctx;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ctx = await StudentContext.load();
      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _C.red : _C.navy,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action, style: const TextStyle(color: _C.red))),
        ],
      ),
    );
    return r == true;
  }

  /// Latest known position of the student's bus (null if none yet).
  Future<({double lat, double lng})?> _busPosition() async {
    final busId = _ctx?.busId;
    if (busId == null) return null;
    try {
      final rows = await _sb
          .from('live_locations')
          .select('lat, lng')
          .eq('bus_id', busId)
          .order('timestamp', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      final lat = double.tryParse('${rows.first['lat']}');
      final lng = double.tryParse('${rows.first['lng']}');
      if (lat == null || lng == null) return null;
      return (lat: lat, lng: lng);
    } catch (_) {
      return null;
    }
  }

  /// Saves the emergency. type must be one of the `emergency_type` values:
  /// accident, breakdown, health, security, traffic, other.
  Future<bool> _raise(String type, String description) async {
    final ctx = _ctx;
    if (ctx == null) return false;
    setState(() => _sending = true);
    try {
      final pos = await _busPosition();
      await _sb.from('emergencies').insert({
        'bus_id': ctx.busId,
        'raised_by': ctx.userId,
        'type': type,
        'description': description,
        if (pos != null) 'lat': pos.lat,
        if (pos != null) 'lng': pos.lng,
      });
      return true;
    } catch (e) {
      if (mounted) _snack('Could not send alert: $e', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ───────────────────────── ACTIONS ─────────────────────────

  Future<void> _sos() async {
    final ok = await _confirm(
        'Send SOS?',
        'Your institution admin will be alerted immediately.',
        'Send SOS');
    if (!ok) return;
    if (await _raise('other', 'SOS pressed by student')) {
      if (mounted) _showSent('SOS sent', 'Help has been alerted. Stay safe.');
    }
  }

  Future<void> _medical() async {
    final ok = await _confirm(
        'Medical emergency?',
        'This alerts your admin. You can then call an ambulance or notify your parent.',
        'Send alert');
    if (!ok) return;
    if (await _raise('health', 'Medical emergency')) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Alert sent. What next?',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _C.navy)),
              const SizedBox(height: 14),
              _sheetButton(Icons.call, 'Call ambulance (108)', _C.red, () {
                Navigator.pop(context);
                _callAmbulance();
              }),
              _sheetButton(
                  Icons.local_hospital, 'Find nearest hospital', _C.blue, () {
                Navigator.pop(context);
                _nearestHospital();
              }),
              _sheetButton(Iconsax.user, 'Notify my parent', _C.green, () {
                Navigator.pop(context);
                _notifyParent();
              }),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _notifyAdmin() async {
    final c = TextEditingController();
    final msg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Message to admin'),
        content: TextField(
          controller: c,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText: 'Describe what is happening (optional)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Send')),
        ],
      ),
    );
    c.dispose();
    if (msg == null) return;
    if (await _raise('other', msg.isEmpty ? 'Urgent message from student' : msg)) {
      if (mounted) _showSent('Admin notified', 'Your message has been sent.');
    }
  }

  Future<void> _nearestHospital() async {
    final pos = await _busPosition();
    final uri = pos == null
        ? Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=hospital+near+me')
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=hospital&center=${pos.lat},${pos.lng}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack('Could not open maps.', error: true);
  }

  Future<void> _callAmbulance() async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: '108'));
    if (!ok && mounted) _snack('Could not open the dialer.', error: true);
  }

  Future<void> _notifyParent() async {
    final phone = _ctx?.student['parent_phone']?.toString();
    if (phone == null || phone.isEmpty) {
      _snack('No parent phone number is saved for you.', error: true);
      return;
    }
    final name = _ctx?.student['student_name']?.toString() ?? 'Your child';
    final pos = await _busPosition();
    final where = pos == null
        ? ''
        : ' Bus location: https://maps.google.com/?q=${pos.lat},${pos.lng}';
    final body = '$name needs help on the college bus (Yatra Mitra).$where';
    final ok = await launchUrl(
        Uri(scheme: 'sms', path: phone, queryParameters: {'body': body}));
    if (!ok && mounted) _snack('Could not open messages.', error: true);
  }

  void _showSent(String title, String text) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const YmGradientTile(
                  icon: Icons.check_rounded, color: Ym.green, size: 72),
              const SizedBox(height: 18),
              Text(title, style: Ym.h(21)),
              const SizedBox(height: 8),
              Text(text,
                  textAlign: TextAlign.center,
                  style: Ym.t(13.5, color: Ym.grey)),
              const SizedBox(height: 22),
              YmButton(label: 'Done', onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── UI ─────────────────────────

  Widget _sheetButton(
          IconData icon, String label, Color color, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: YmPressable(
          onTap: onTap,
          scale: 0.97,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                YmGradientTile(icon: icon, color: color, size: 44),
                const SizedBox(width: 14),
                Expanded(child: Text(label, style: Ym.h(15))),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      );

  Widget _smallCard(IconData icon, Color color, String title, String sub,
          VoidCallback onTap) =>
      Expanded(
        child: YmCard(
          onTap: _sending ? null : onTap,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              YmGradientTile(icon: icon, color: color, size: 48),
              const SizedBox(height: 14),
              Text(title, style: Ym.h(15)),
              const SizedBox(height: 3),
              Text(sub, style: Ym.t(11.5, color: Ym.grey)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final busNumber = _ctx?.bus?['bus_number']?.toString();

    return YmPage(
      title: 'Emergency SOS',
      subtitle: 'Help is one tap away',
      child: _loading
          ? const YmSkeletonList(count: 3, height: 120)
          : _error != null
              ? YmEmpty(
                  icon: Iconsax.warning_2,
                  color: Ym.red,
                  title: 'Could not load',
                  subtitle: _error,
                  action: YmButton(
                      label: 'Try again',
                      expanded: false,
                      icon: Icons.refresh_rounded,
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        _load();
                      }),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  children: [
                    YmFadeSlide(
                      index: 0,
                      child: Center(
                        child: _SosButton(onTap: _sos, sending: _sending),
                      ),
                    ),
                    YmFadeSlide(
                      index: 1,
                      child: Column(
                        children: [
                          Text('Tap for emergency',
                              style: Ym.h(18, color: Ym.red)),
                          const SizedBox(height: 6),
                          Text(
                              'Your admin is\nalerted instantly with your bus location.',
                              textAlign: TextAlign.center,
                              style: Ym.t(12.5, color: Ym.grey)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (busNumber != null)
                      YmFadeSlide(
                        index: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Ym.green.withOpacity(0.09),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const YmPulse(color: Ym.green, size: 7),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                    'Location of $busNumber is attached to every alert',
                                    style: Ym.t(12.5,
                                        color: Ym.green, w: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 22),
                    YmFadeSlide(
                      index: 3,
                      child: YmPressable(
                        onTap: _sending ? null : _medical,
                        scale: 0.98,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
                            ),
                            boxShadow: Ym.shadow(Ym.red, 0.35),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.favorite_rounded,
                                    color: Colors.white, size: 26),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Medical Emergency',
                                        style: Ym.h(17, color: Colors.white)),
                                    const SizedBox(height: 3),
                                    Text(
                                        'Alert admin, then call an ambulance or your parent',
                                        style: Ym.t(12,
                                            color:
                                                Colors.white.withOpacity(0.85))),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    YmFadeSlide(
                      index: 4,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _smallCard(Iconsax.notification, const Color(0xFFEA580C),
                              'Notify Admin', 'Urgent message', _notifyAdmin),
                          const SizedBox(width: 14),
                          _smallCard(Icons.local_hospital_rounded, Ym.blue,
                              'Nearest Hospital', 'Show on map', _nearestHospital),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    YmFadeSlide(
                      index: 5,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _smallCard(Icons.call_rounded, Ym.red, 'Call Ambulance',
                              'Directly call 108', _callAmbulance),
                          const SizedBox(width: 14),
                          _smallCard(Iconsax.user, Ym.green, 'Notify Parent',
                              'Send SMS alert', _notifyParent),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// The big red SOS button with three expanding rings.
class _SosButton extends StatefulWidget {
  const _SosButton({required this.onTap, required this.sending});
  final VoidCallback onTap;
  final bool sending;

  @override
  State<_SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<_SosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 290,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Builder(builder: (_) {
                final t = (_c.value + i / 3) % 1;
                return Opacity(
                  opacity: (1 - t) * 0.32,
                  child: Transform.scale(
                    scale: 1 + t * 0.6,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Ym.red),
                    ),
                  ),
                );
              }),
            YmPressable(
              onTap: widget.sending ? null : widget.onTap,
              scale: 0.93,
              child: Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.3, -0.4),
                    colors: [Color(0xFFFF6B63), Ym.red, Color(0xFFB91C1C)],
                    stops: [0, 0.55, 1],
                  ),
                  border: Border.all(color: Colors.white, width: 5),
                  boxShadow: [
                    BoxShadow(
                        color: Ym.red.withOpacity(0.5),
                        blurRadius: 34,
                        spreadRadius: 3),
                  ],
                ),
                child: Center(
                  child: widget.sending
                      ? const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 3)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('SOS',
                                style: Ym.h(44,
                                    color: Colors.white, w: FontWeight.w900)),
                            Text('TAP',
                                style: Ym.t(12,
                                    color: Colors.white.withOpacity(0.85),
                                    w: FontWeight.w800)),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}