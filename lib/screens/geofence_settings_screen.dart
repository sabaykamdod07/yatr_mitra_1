import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:iconsax/iconsax.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Lets the student choose how close the bus must be to their boarding stop
/// before they get an alert.
///
/// Saved to `geofence_settings`. The database trigger `geofence_check` reads
/// this row every time a new bus position arrives (phone today, GPS hardware
/// later), so nothing here depends on the hardware.
class GeofenceSettingsScreen extends StatefulWidget {
  const GeofenceSettingsScreen({super.key});

  @override
  State<GeofenceSettingsScreen> createState() => _GeofenceSettingsScreenState();
}

class _GeofenceSettingsScreenState extends State<GeofenceSettingsScreen> {
  final _sb = Supabase.instance.client;

  StudentContext? _ctx;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  double _radius = 500;
  bool _enabled = true;
  bool _notify = true;

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
      final ctx = await StudentContext.load();
      final row = await _sb
          .from('geofence_settings')
          .select()
          .eq('user_id', ctx.userId)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        if (row != null) {
          _radius = (double.tryParse('${row['radius_meters']}') ?? 500)
              .clamp(100, 1000)
              .toDouble();
          _enabled = row['is_enabled'] as bool? ?? true;
          _notify = row['notifications_enabled'] as bool? ?? true;
        }
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

  Future<void> _save() async {
    final ctx = _ctx;
    if (ctx == null) return;
    if (ctx.stopLat == null || ctx.stopLng == null) {
      _snack('Your boarding stop has no location yet. Ask your institution.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _sb.from('geofence_settings').upsert({
        'user_id': ctx.userId,
        'radius_meters': _radius.round(),
        'lat': ctx.stopLat,
        'lng': ctx.stopLng,
        'is_enabled': _enabled,
        'notifications_enabled': _notify,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
      if (!mounted) return;
      _snack('Geofence saved.');
      Navigator.of(context).pop();
    } catch (e) {
      _snack('Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? _C.red : _C.navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Geofence Settings',
      subtitle: 'When should we alert you?',
      child: _loading
          ? const YmSkeletonList(count: 3, height: 140)
          : _error != null
              ? YmEmpty(
                  icon: Icons.error_outline_rounded,
                  color: Ym.red,
                  title: 'Could not load',
                  subtitle: _error,
                  action: YmButton(
                      label: 'Try again',
                      expanded: false,
                      icon: Icons.refresh_rounded,
                      onPressed: _load),
                )
              : _body(),
    );
  }

  Widget _body() {
    final ctx = _ctx!;
    final hasStop = ctx.stopLat != null && ctx.stopLng != null;
    final center = hasStop ? LatLng(ctx.stopLat!, ctx.stopLng!) : null;
    final zoom = _radius <= 250 ? 16.0 : (_radius <= 500 ? 15.0 : 14.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
      children: [
        YmFadeSlide(
          index: 0,
          child: Container(
            height: 250,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: Ym.shadow(Ym.navy, 0.1),
            ),
            clipBehavior: Clip.antiAlias,
            child: center == null
                ? Container(
                    color: Colors.white,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_off_rounded,
                            color: Ym.grey, size: 34),
                        const SizedBox(height: 10),
                        Text(
                          'Your boarding stop has no location yet, so the area can\'t be shown.',
                          textAlign: TextAlign.center,
                          style: Ym.t(13, color: Ym.grey),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      FlutterMap(
                        key: ValueKey(zoom), // rebuild when zoom bracket changes
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: zoom,
                          interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.yatramitra.app',
                          ),
                          CircleLayer(circles: [
                            CircleMarker(
                              point: center,
                              radius: _radius,
                              useRadiusInMeter: true,
                              color: Ym.amber.withOpacity(0.2),
                              borderColor: Ym.amberDark,
                              borderStrokeWidth: 2.5,
                            ),
                          ]),
                          MarkerLayer(markers: [
                            Marker(
                              point: center,
                              width: 44,
                              height: 44,
                              alignment: Alignment.topCenter,
                              child: const Icon(Icons.location_on_rounded,
                                  color: Ym.green, size: 42),
                            ),
                          ]),
                        ],
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text('${_radius.round()} m around your stop',
                              style: Ym.t(12, w: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        YmFadeSlide(
          index: 1,
          child: YmCard(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('How close?', style: Ym.h(15)),
                    const Spacer(),
                    Text(
                      _radius >= 1000
                          ? '1 km'
                          : '${_radius.round()} m',
                      style: Ym.h(18, color: Ym.amberDark),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('The alert comes when the bus gets this close to your stop.',
                    style: Ym.t(12, color: Ym.grey)),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Ym.amber,
                    inactiveTrackColor: Ym.line,
                    thumbColor: Ym.navy,
                    overlayColor: Ym.amber.withOpacity(0.18),
                    trackHeight: 6,
                  ),
                  child: Slider(
                    value: _radius,
                    min: 100,
                    max: 1000,
                    divisions: 18,
                    onChanged: (v) => setState(() => _radius = v),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in const [100.0, 250.0, 500.0, 750.0, 1000.0])
                      YmPressable(
                        onTap: () => setState(() => _radius = p),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _radius == p ? Ym.amber : Ym.creamTop,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: _radius == p ? Ym.amberDark : Ym.line),
                          ),
                          child: Text(p >= 1000 ? '1 km' : '${p.round()} m',
                              style: Ym.t(12.5,
                                  w: _radius == p
                                      ? FontWeight.w800
                                      : FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        YmFadeSlide(
          index: 2,
          child: YmCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                _switchRow(
                  Icons.notifications_active_outlined,
                  'Geofence alerts',
                  'Alert me when the bus enters or exits',
                  _enabled,
                  (v) => setState(() => _enabled = v),
                ),
                const Divider(height: 1, indent: 18, endIndent: 18, color: Ym.line),
                _switchRow(
                  Icons.inbox_outlined,
                  'Show in notifications',
                  'Alerts are kept for 24 hours',
                  _notify,
                  (v) => setState(() => _notify = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Ym.blue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Ym.blue, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You will receive alerts when the bus enters or exits this area around your boarding stop.',
                  style: Ym.t(12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        YmButton(
          label: 'Save Settings',
          icon: Icons.check_rounded,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }

  Widget _switchRow(IconData icon, String title, String sub, bool value,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Row(
        children: [
          YmIconBadge(icon: icon, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Ym.h(14, w: FontWeight.w700)),
                Text(sub, style: Ym.t(12, color: Ym.grey)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: Colors.white,
            activeTrackColor: Ym.amber,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}