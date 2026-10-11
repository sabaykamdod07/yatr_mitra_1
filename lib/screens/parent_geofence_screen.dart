import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_context.dart';
import '../theme/ym_ui.dart';
import '../widgets/parent_child_picker.dart';

/// "Tell me when the bus is near." The parent picks how far from the child's
/// stop the alert should come (for example 500 m, about two minutes before).
/// This is the parent's own setting: it does not change the student's alerts.
class ParentGeofenceScreen extends StatefulWidget {
  const ParentGeofenceScreen({
    super.key,
    required this.children,
    required this.selected,
  });

  final List<Map<String, dynamic>> children;
  final int selected;

  @override
  State<ParentGeofenceScreen> createState() => _ParentGeofenceScreenState();
}

class _ParentGeofenceScreenState extends State<ParentGeofenceScreen> {
  final _sb = Supabase.instance.client;

  late int _sel = widget.selected;
  bool _loading = true;
  bool _saving = false;
  bool _enabled = true;
  double _radius = 500;
  bool _stopOnMap = true;
  String _stopName = '';
  String? _error;

  static const _quick = [100, 250, 500, 750, 1000];

  String get _childId => widget.children[_sel]['id'].toString();
  String get _childName =>
      (widget.children[_sel]['student_name'] ?? 'your child').toString();

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
      final row = await _sb
          .from('parent_geofence')
          .select()
          .eq('student_id', _childId)
          .maybeSingle();
      final ctx = await StudentContext.load(studentId: _childId);
      if (!mounted) return;
      setState(() {
        _enabled = row == null ? true : row['is_enabled'] != false;
        _radius = (num.tryParse('${row?['radius_meters']}') ?? 500).toDouble();
        _stopOnMap = ctx.stopLat != null && ctx.stopLng != null;
        _stopName = (ctx.stop?['stop_name'] ?? '').toString();
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _sb.rpc('set_parent_geofence', params: {
        'p_student': _childId,
        'p_radius': _radius.round(),
        'p_enabled': _enabled,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_enabled
            ? 'Saved. You will be told when the bus is within ${_label(_radius)} of the stop.'
            : 'Saved. Bus alerts for $_childName are off.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is PostgrestException ? e.message : '$e'),
        backgroundColor: Ym.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _label(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km' : '${m.round()} m';

  /// a rough idea: a city bus moves at about 20 km/h
  String get _minutes {
    final min = _radius / (20000 / 60);
    if (min < 1) return 'less than a minute';
    return 'about ${min.round()} minute${min.round() == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Alert Distance',
      subtitle: 'How early should we tell you?',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: YmSkeletonList(count: 2, height: 140),
            )
          : _error != null
              ? YmEmpty(
                  icon: Icons.cloud_off_rounded,
                  color: Ym.red,
                  title: 'Could not load the setting',
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
                    YmCard(
                      padding: const EdgeInsets.all(18),
                      radius: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const YmIconBadge(
                                  icon: Icons.notifications_active_rounded,
                                  color: Ym.red),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Bus is near alert', style: Ym.h(15)),
                                    Text(
                                        _stopName.isEmpty
                                            ? 'For $_childName\'s stop'
                                            : 'For $_childName at $_stopName',
                                        style: Ym.t(12, color: Ym.grey)),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _enabled,
                                activeColor: Ym.navy,
                                activeTrackColor: Ym.amber,
                                onChanged: (v) => setState(() => _enabled = v),
                              ),
                            ],
                          ),
                          if (!_stopOnMap) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Ym.amber.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline_rounded,
                                      color: Ym.amberDark, size: 19),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'The school has not placed this stop on the map yet, so alerts will start once it is added.',
                                      style: Ym.t(12).copyWith(height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedOpacity(
                      opacity: _enabled ? 1 : 0.4,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_enabled,
                        child: YmCard(
                          padding: const EdgeInsets.all(18),
                          radius: 24,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tell me when the bus is within',
                                  style: Ym.t(12.5, color: Ym.grey, w: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Text(_label(_radius), style: Ym.h(34)),
                              Text('That is $_minutes before the bus reaches the stop.',
                                  style: Ym.t(12, color: Ym.grey)),
                              const SizedBox(height: 10),
                              Slider(
                                value: _radius.clamp(50, 3000),
                                min: 50,
                                max: 3000,
                                divisions: 59,
                                activeColor: Ym.amberDark,
                                inactiveColor: Ym.line,
                                onChanged: (v) => setState(
                                    () => _radius = (v / 50).round() * 50.0),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final m in _quick)
                                    YmPressable(
                                      onTap: () =>
                                          setState(() => _radius = m.toDouble()),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 9),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(20),
                                          gradient: _radius == m
                                              ? const LinearGradient(
                                                  colors: [Ym.amber, Ym.amberDark])
                                              : null,
                                          color: _radius == m ? null : Ym.creamTop,
                                          border: Border.all(
                                              color: _radius == m
                                                  ? Ym.amberDark
                                                  : Ym.line),
                                        ),
                                        child: Text(_label(m.toDouble()),
                                            style: Ym.t(12.5,
                                                color: _radius == m
                                                    ? Ym.navy
                                                    : Ym.grey,
                                                w: FontWeight.w800)),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This is your own setting. It does not change the alerts your child gets.',
                      style: Ym.t(11.5, color: Ym.grey),
                    ),
                    const SizedBox(height: 16),
                    YmButton(
                      label: 'Save',
                      icon: Icons.check_rounded,
                      loading: _saving,
                      onPressed: _save,
                    ),
                  ],
                ),
    );
  }
}