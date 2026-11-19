import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csv/csv.dart';
import 'package:iconsax/iconsax.dart';
import 'package:latlong2/latlong.dart';
import 'pending_credentials_screen.dart';
import 'role_selection_screen.dart';
import 'map_picker_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:web/web.dart' as web;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'admin_drivers_tab.dart';
import 'admin_fees_screen.dart';
import 'admin_alerts_screen.dart';
import 'admin_buses_screen.dart';
import 'inbox_screen.dart';
import 'admin_attendance_screen.dart';
import 'admin_reports_screen.dart';
import '../widgets/account_sheet.dart';
import '../widgets/link_rfid_sheet.dart';
import '../theme/ym_ui.dart';


class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => AdminDashboardScreenState();
}

class AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentIndex = 0;
  final _supabase = Supabase.instance.client;
  DateTime? _lastBackPress;

  String _institutionName = '';
  String _institutionCity = '';
  String? _institutionId;
  int _totalStudents = 0;
  int _totalBuses = 0;
  int _totalRoutes = 0;
  int _totalDrivers = 0;
  int _helpdeskCount = 0;
  int _tripsToday = 0; // trips completed today
  int _tripsRunning = 0; // trips running right now
  int _pendingCredentials = 0;
  bool _isLoadingStats = true;

  List<Map<String, dynamic>> _stagedExcelRoutes = [];
  bool _isProcessingExcel = false;
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _availableRoutes = [];
  List<Map<String, dynamic>> _liveDatabaseRoutesWithStops = [];
  bool _isLoadingLiveRoutes = false;
  List<Map<String, dynamic>> _buses = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _fetchRouteRequests();
    _fetchLiveRoutesAndStops();
    _fetchBuses();
  }

  Future<void> _fetchRouteRequests() async {
    try {
      final adminId = _supabase.auth.currentUser?.id;
      if (adminId == null) return;

      final institution = await _supabase
          .from('institutions')
          .select('id')
          .eq('admin_id', adminId)
          .maybeSingle();

      if (institution == null) {
        if (mounted) {
          setState(() {
            _pendingRequests = [];
            _availableRoutes = [];
          });
        }
        return;
      }

      final institutionId = institution['id'];
      final requestsData = await _supabase
          .from('route_requests')
          .select(
              'id, requested_boarding_point, created_at, status, requested_by, institution_id, custom_stop_lat, custom_stop_lng')
          .eq('institution_id', institutionId)
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      final routesData = await _supabase
          .from('routes')
          .select('id, route_name')
          .eq('institution_id', institutionId);

      if (mounted) {
        setState(() {
          _pendingRequests = List<Map<String, dynamic>>.from(requestsData);
          _availableRoutes = List<Map<String, dynamic>>.from(routesData);
        });
      }
    } on PostgrestException catch (e) {
      debugPrint('Supabase error: ${e.message}');
    } catch (e) {
      debugPrint('Error: $e');
    }
  }


  Future<void> _fetchBuses() async {
    try {
      if (_institutionId == null) return;
      final buses = await _supabase
          .from('buses')
          .select('id, bus_number')
          .eq('institution_id', _institutionId!);
      setState(() {
        _buses = List<Map<String, dynamic>>.from(buses);
      });
    } catch (e) {
      debugPrint('Error fetching buses: $e');
    }
  }

  Future<void> _fetchLiveRoutesAndStops() async {
    setState(() => _isLoadingLiveRoutes = true);
    try {
      final adminId = _supabase.auth.currentUser!.id;
      final institution = await _supabase
          .from('institutions')
          .select('id')
          .eq('admin_id', adminId)
          .maybeSingle();

      if (institution != null) {
        final institutionId = institution['id'];
        final routesResponse = await _supabase
            .from('routes')
            .select(
                'id, route_name, stops(id, stop_name, timing, lat, lng)')
            .eq('institution_id', institutionId)
            .order('route_name', ascending: true);

        setState(() {
          _liveDatabaseRoutesWithStops =
              List<Map<String, dynamic>>.from(routesResponse);
        });
      }
    } catch (e) {
      debugPrint('Error fetching live records: $e');
    } finally {
      setState(() => _isLoadingLiveRoutes = false);
    }
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoadingStats = true);
    try {
      final adminId = _supabase.auth.currentUser!.id;
      final institution = await _supabase
          .from('institutions')
          .select()
          .eq('admin_id', adminId)
          .maybeSingle();

      if (institution != null) {
        _institutionName = institution['name'] ?? '';
        _institutionCity = institution['city'] ?? '';
        _institutionId = institution['id'];
        final institutionId = institution['id'];

        final students = await _supabase
            .from('students')
            .select('id')
            .eq('institution_id', institutionId);
        final buses = await _supabase
            .from('buses')
            .select('id')
            .eq('institution_id', institutionId);
        final routes = await _supabase
            .from('routes')
            .select('id')
            .eq('institution_id', institutionId);
        final helpdesks = await _supabase
            .from('helpdesk_accounts')
            .select('id')
            .eq('institution_id', institutionId);
        final pending = await _supabase
            .from('students')
            .select('id')
            .eq('institution_id', institutionId)
            .eq('credential_generated', false);

        // a deactivated driver is not counted
        final drivers = await _supabase
          .from('drivers')
          .select('id')
          .eq('institution_id', institutionId)
          .or('is_active.is.null,is_active.eq.true');

        // trips that started today (the admin's own day, midnight to midnight)
        var tripsDone = 0;
        var tripsRun = 0;
        try {
          final now = DateTime.now();
          final dayStart = DateTime(now.year, now.month, now.day).toUtc();
          final todays = await _supabase
              .from('trips')
              .select('status')
              .eq('institution_id', institutionId)
              .gte('started_at', dayStart.toIso8601String());
          for (final t in todays) {
            final st = (t['status'] ?? '').toString();
            if (st == 'completed') tripsDone++;
            if (st == 'in_progress') tripsRun++;
          }
        } catch (_) {
          // if trips cannot be read, the card simply shows 0
        }

        setState(() {
        _totalStudents = (students as List).length;
        _totalBuses = (buses as List).length;
        _totalDrivers = (drivers as List).length;
        _totalRoutes = (routes as List).length;
        _helpdeskCount = (helpdesks as List).length;
        _pendingCredentials = (pending as List).length;
        _tripsToday = tripsDone;
        _tripsRunning = tripsRun;
        });
        await _fetchBuses();
      }
      setState(() => _isLoadingStats = false);
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      setState(() => _isLoadingStats = false);
    }
  }

    Future<void> _importExcelFile() async {
    setState(() => _isProcessingExcel = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, // gives the file bytes on both web and phone
      );

      // user closed the picker without choosing a file
      if (result == null || result.files.single.bytes == null) return;

      var csvString =
          utf8.decode(result.files.single.bytes!, allowMalformed: true);
      // files from Notepad / Excel / Mac differ in how a line ends and may start
      // with an invisible marker; make them all the same before reading
      if (csvString.startsWith('\uFEFF')) csvString = csvString.substring(1);
      csvString = csvString
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .replaceAll('\n', '\r\n');
      // Excel in some regions saves with ; instead of ,
      final firstLine = csvString.split('\r\n').first;
      if (firstLine.contains(';') && !firstLine.contains(',')) {
        csvString = csvString.replaceAll(';', ',');
      }
      final List<List<dynamic>> csvTable =
          const CsvToListConverter().convert(csvString);

      final List<Map<String, dynamic>> temporarilyLoaded = [];
      for (int i = 1; i < csvTable.length; i++) {
        final row = csvTable[i];
        if (row.length >= 2) {
          final routeVal = row[0] != null ? row[0].toString().trim() : '';
          final stopVal = row[1] != null ? row[1].toString().trim() : '';
          if (routeVal.isEmpty && stopVal.isEmpty) continue;
          String timingVal = '07:30:00';
          if (row.length > 2 && row[2] != null) {
            timingVal = row[2].toString().trim();
          }
          temporarilyLoaded.add({
            'route_name': routeVal,
            'stop_name': stopVal,
            'timing': timingVal,
          });
        }
      }

      if (!mounted) return;
      setState(() => _stagedExcelRoutes = temporarilyLoaded);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Read: ${_stagedExcelRoutes.length} entries queued.'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('File Import Failure'),
            content: Text('Error: $e'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'))
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingExcel = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // CSV upload. The first time, routes are simply saved. After that the admin
  // chooses:
  //   * ADD NEW ROUTES   routes that already exist are left exactly as they are
  //   * UPDATE FROM FILE routes in the file are updated IN PLACE
  // Nothing is ever deleted and re-created, so stops keep their map location and
  // the students, faculty and drivers assigned to them keep their stop. Routes and
  // stops that are not in the file are removed only if nobody uses them.
  // ───────────────────────────────────────────────────────────────────────────

  String _nm(dynamic s) => (s ?? '').toString().trim().toLowerCase();

  _ImportPlan _planImport({
    required bool update,
    required Map<String, List<Map<String, dynamic>>> grouped,
    required List<Map<String, dynamic>> dbRoutes,
    required List<Map<String, dynamic>> dbStops,
    required Set<String> usedStops,
    required Set<String> usedRoutes,
  }) {
    final plan = _ImportPlan();
    final dbByName = {for (final r in dbRoutes) _nm(r['route_name']): r};

    for (final e in grouped.entries) {
      final named = e.value.where((st) => _nm(st['stop_name']).isNotEmpty).toList();
      final db = dbByName[_nm(e.key)];
      if (db == null) {
        plan.routesAdd.add(e.key);
        plan.stopsAdd += named.length;
        continue;
      }
      if (!update) {
        plan.routesSkip.add(e.key);
        continue;
      }
      plan.routesUpdate.add(e.key);
      final existing =
          dbStops.where((st) => st['route_id'].toString() == db['id'].toString()).toList();
      final byName = {for (final st in existing) _nm(st['stop_name']): st};
      final fileNames = <String>{};
      for (final st in named) {
        final nm = _nm(st['stop_name']);
        fileNames.add(nm);
        if (byName.containsKey(nm)) {
          plan.stopsUpdate++;
        } else {
          plan.stopsAdd++;
        }
      }
      for (final st in existing) {
        if (!fileNames.contains(_nm(st['stop_name']))) {
          if (usedStops.contains(st['id'].toString())) {
            plan.stopsKept++;
          } else {
            plan.stopsRemove++;
          }
        }
      }
    }

    if (update) {
      final inFile = grouped.keys.map(_nm).toSet();
      for (final r in dbRoutes) {
        if (!inFile.contains(_nm(r['route_name']))) {
          if (usedRoutes.contains(r['id'].toString())) {
            plan.routesKept.add(r['route_name'].toString());
          } else {
            plan.routesRemove.add(r['route_name'].toString());
          }
        }
      }
    }
    return plan;
  }

  Future<void> _applyImport({
    required bool update,
    required dynamic institutionId,
    required Map<String, List<Map<String, dynamic>>> grouped,
    required List<Map<String, dynamic>> dbRoutes,
    required List<Map<String, dynamic>> dbStops,
    required Set<String> usedStops,
    required Set<String> usedRoutes,
  }) async {
    final dbByName = {for (final r in dbRoutes) _nm(r['route_name']): r};

    for (final e in grouped.entries) {
      final db = dbByName[_nm(e.key)];
      dynamic routeId;
      var existing = <Map<String, dynamic>>[];

      if (db == null) {
        final created = await _supabase
            .from('routes')
            .insert({'institution_id': institutionId, 'route_name': e.key})
            .select('id')
            .single();
        routeId = created['id'];
      } else if (!update) {
        continue; // "add new routes only": an existing route is left as it is
      } else {
        routeId = db['id'];
        existing =
            dbStops.where((st) => st['route_id'].toString() == routeId.toString()).toList();
      }

      final byName = {for (final st in existing) _nm(st['stop_name']): st};
      final fileNames = <String>{};
      final toInsert = <Map<String, dynamic>>[];
      var order = 0;

      for (final st in e.value) {
        final sName = (st['stop_name'] ?? '').toString().trim();
        if (sName.isEmpty) continue;
        order++;
        final nm = _nm(sName);
        fileNames.add(nm);
        final lat = double.tryParse((st['lat'] ?? '').toString().trim());
        final lng = double.tryParse((st['lng'] ?? '').toString().trim());
        final timing = (st['timing'] ?? '').toString().trim();
        final match = byName[nm];
        if (match != null) {
          // same stop: keep it (and everyone on it); update the time and the order.
          // The map location is only changed when the file really has one.
          final upd = <String, dynamic>{'timing': timing, 'stop_order': order};
          if (lat != null && lng != null) {
            upd['lat'] = lat;
            upd['lng'] = lng;
          }
          await _supabase.from('stops').update(upd).eq('id', match['id']);
        } else {
          toInsert.add({
            'route_id': routeId,
            'stop_name': sName,
            'timing': timing,
            'lat': lat,
            'lng': lng,
            'stop_order': order,
          });
        }
      }
      if (toInsert.isNotEmpty) {
        await _supabase.from('stops').insert(toInsert);
      }

      // stops that are not in the file: removed only if nobody uses them
      for (final st in existing) {
        if (!fileNames.contains(_nm(st['stop_name'])) &&
            !usedStops.contains(st['id'].toString())) {
          await _supabase.from('stops').delete().eq('id', st['id']);
        }
      }
    }

    if (update) {
      final inFile = grouped.keys.map(_nm).toSet();
      for (final r in dbRoutes) {
        if (!inFile.contains(_nm(r['route_name'])) &&
            !usedRoutes.contains(r['id'].toString())) {
          await _supabase.from('stops').delete().eq('route_id', r['id']);
          await _supabase.from('routes').delete().eq('id', r['id']);
        }
      }
    }
  }

  List<String> _previewLines(_ImportPlan p, bool update) {
    String names(List<String> l) =>
        l.length <= 5 ? l.join(', ') : '${l.take(5).join(', ')} and ${l.length - 5} more';
    final out = <String>[];
    if (!update) {
      out.add(p.routesAdd.isEmpty
          ? 'No new routes in this file.'
          : 'Will add ${p.routesAdd.length} new route${p.routesAdd.length == 1 ? '' : 's'} '
              '(${p.stopsAdd} stops): ${names(p.routesAdd)}.');
      if (p.routesSkip.isNotEmpty) {
        out.add('Will leave ${p.routesSkip.length} existing route'
            '${p.routesSkip.length == 1 ? '' : 's'} untouched: ${names(p.routesSkip)}.');
      }
    } else {
      out.add('Routes updated in place: ${p.routesUpdate.length}.');
      if (p.routesAdd.isNotEmpty) {
        out.add('New routes added: ${names(p.routesAdd)}.');
      }
      out.add('Stops: ${p.stopsAdd} added, ${p.stopsUpdate} updated, ${p.stopsRemove} removed.');
      if (p.routesRemove.isNotEmpty) {
        out.add('Routes removed (nobody uses them): ${names(p.routesRemove)}.');
      }
      if (p.stopsKept > 0 || p.routesKept.isNotEmpty) {
        out.add('Kept because people use them: ${p.stopsKept} stop${p.stopsKept == 1 ? '' : 's'}'
            '${p.routesKept.isEmpty ? '' : ', routes ${names(p.routesKept)}'}.');
      }
    }
    return out;
  }

  /// true = update from the file, false = add new routes only, null = cancelled
  Future<bool?> _askImportMode(int fileRoutes, int dbRouteCount, _ImportPlan add, _ImportPlan upd) {
    var update = false;
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          Widget option(bool isUpdate, IconData icon, String title, String sub) {
            final on = update == isUpdate;
            return YmPressable(
              onTap: () => setSheet(() => update = isUpdate),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: on ? Ym.amber.withOpacity(0.16) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: on ? Ym.amberDark : Ym.line, width: on ? 1.6 : 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    YmIconBadge(icon: icon, color: on ? Ym.amberDark : Ym.grey, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: Ym.h(14.5)),
                          const SizedBox(height: 3),
                          Text(sub, style: Ym.t(12, color: Ym.grey).copyWith(height: 1.4)),
                        ],
                      ),
                    ),
                    Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        color: on ? Ym.amberDark : Ym.grey, size: 22),
                  ],
                ),
              ),
            );
          }

          final lines = _previewLines(update ? upd : add, update);
          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.88),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4.5,
                        decoration:
                            BoxDecoration(color: Ym.line, borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('You already have $dbRouteCount route${dbRouteCount == 1 ? '' : 's'}',
                        style: Ym.h(20)),
                    const SizedBox(height: 4),
                    Text('This file has $fileRoutes. How should it be applied?',
                        style: Ym.t(13, color: Ym.grey)),
                    const SizedBox(height: 16),
                    option(false, Icons.add_road_rounded, 'Add new routes only',
                        'Routes that already exist stay exactly as they are. Only routes that are new are added.'),
                    const SizedBox(height: 10),
                    option(true, Icons.sync_alt_rounded, 'Update from this file',
                        'Routes in the file are updated in place. Stops keep their map location and the people on them. '
                        'Routes and stops that are not in the file are removed only if nobody uses them.'),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Ym.creamTop,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('What will happen',
                              style: Ym.t(12, color: Ym.grey, w: FontWeight.w800)),
                          const SizedBox(height: 6),
                          for (final l in lines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(l, style: Ym.t(13).copyWith(height: 1.4)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: YmButton(
                              label: 'Cancel',
                              outline: true,
                              onPressed: () => Navigator.pop(c, null)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: YmButton(
                              label: 'Apply',
                              icon: Icons.check_rounded,
                              onPressed: () => Navigator.pop(c, update)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveExcelDataToDatabase() async {
    if (_stagedExcelRoutes.isEmpty) return;
    setState(() => _isLoadingStats = true);
    try {
      final adminId = _supabase.auth.currentUser!.id;
      final institution = await _supabase
          .from('institutions')
          .select('id')
          .eq('admin_id', adminId)
          .single();
      final institutionId = institution['id'];

      // the file, grouped by route name (the order of the file is kept)
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final item in _stagedExcelRoutes) {
        final rName = (item['route_name'] ?? '').toString().trim();
        if (rName.isEmpty) continue;
        grouped.putIfAbsent(rName, () => []).add(item);
      }
      if (grouped.isEmpty) throw Exception('The file has no route names.');

      // what exists today
      final dbRoutes = List<Map<String, dynamic>>.from(await _supabase
          .from('routes')
          .select('id, route_name')
          .eq('institution_id', institutionId));
      final routeIds = [for (final r in dbRoutes) r['id']];
      var dbStops = <Map<String, dynamic>>[];
      if (routeIds.isNotEmpty) {
        dbStops = List<Map<String, dynamic>>.from(await _supabase
            .from('stops')
            .select('id, route_id, stop_name')
            .inFilter('route_id', routeIds));
      }

      // what people are using (an upload never removes these)
      final usedStops = <String>{};
      final usedRoutes = <String>{};
      Future<void> collect(String table, {required bool withStop}) async {
        try {
          final rows = await _supabase
              .from(table)
              .select(withStop ? 'route_id, stop_id' : 'route_id')
              .eq('institution_id', institutionId);
          for (final r in rows) {
            if (r['route_id'] != null) usedRoutes.add(r['route_id'].toString());
            if (withStop && r['stop_id'] != null) usedStops.add(r['stop_id'].toString());
          }
        } catch (_) {
          // a table or column that is not there simply uses nothing
        }
      }

      await collect('students', withStop: true);
      await collect('faculty', withStop: true);
      await collect('drivers', withStop: false);
      if (routeIds.isNotEmpty) {
        try {
          final t = await _supabase
              .from('trips')
              .select('route_id')
              .inFilter('route_id', routeIds)
              .limit(5000);
          for (final r in t) {
            if (r['route_id'] != null) usedRoutes.add(r['route_id'].toString());
          }
        } catch (_) {}
      }

      _ImportPlan planFor(bool update) => _planImport(
            update: update,
            grouped: grouped,
            dbRoutes: dbRoutes,
            dbStops: dbStops,
            usedStops: usedStops,
            usedRoutes: usedRoutes,
          );

      // first time: just save. After that the admin chooses.
      var update = false;
      if (dbRoutes.isNotEmpty) {
        setState(() => _isLoadingStats = false);
        final choice =
            await _askImportMode(grouped.length, dbRoutes.length, planFor(false), planFor(true));
        if (choice == null) return; // cancelled: nothing was changed
        update = choice;
        setState(() => _isLoadingStats = true);
      }
      final plan = planFor(update);

      await _applyImport(
        update: update,
        institutionId: institutionId,
        grouped: grouped,
        dbRoutes: dbRoutes,
        dbStops: dbStops,
        usedStops: usedStops,
        usedRoutes: usedRoutes,
      );

      setState(() => _stagedExcelRoutes.clear());
      await _loadDashboardData();
      await _fetchRouteRequests();
      await _fetchLiveRoutesAndStops();

      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(children: [
              const Icon(Icons.check_circle_rounded, color: Ym.green),
              const SizedBox(width: 10),
              Text('Routes saved', style: Ym.h(18)),
            ]),
            content: Text(_previewLines(plan, update).join('\n\n'),
                style: Ym.t(13.5, color: Ym.grey).copyWith(height: 1.5)),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sync Failure'),
            content: Text(e.toString()),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  void _openApprovalDialog(Map<String, dynamic> request) {
    String? selectedRouteId;
    final timingController = TextEditingController(text: "07:30:00");
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Approve "${request['requested_boarding_point']}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Assign to a route:',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                hint: const Text('Select route'),
                value: selectedRouteId,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFFAFBFF),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _availableRoutes.map((route) {
                  return DropdownMenuItem<String>(
                    value: route['id'].toString(),
                    child: Text(route['route_name'] ?? ''),
                  );
                }).toList(),
                onChanged: (val) => setModalState(() => selectedRouteId = val),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: timingController,
                decoration: InputDecoration(
                  labelText: 'Morning Pickup Timing',
                  hintText: 'HH:MM',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Ym.amber, foregroundColor: Ym.navy, elevation: 0),
              onPressed: selectedRouteId == null
                  ? null
                  : () async {
                      try {
                        final dynamic finalRouteId =
                            (int.tryParse(selectedRouteId!) != null)
                                ? int.parse(selectedRouteId!)
                                : selectedRouteId!;
                        await _supabase.from('stops').insert({
                          'route_id': finalRouteId,
                          'stop_name': request['requested_boarding_point'],
                          'timing': timingController.text.trim(),
                          if (request['custom_stop_lat'] != null)
                            'lat': request['custom_stop_lat'],
                          if (request['custom_stop_lng'] != null)
                            'lng': request['custom_stop_lng'],
                        });
                        await _supabase
                            .from('route_requests')
                            .update({'status': 'approved'}).eq('id', request['id']);
                        if (request['requested_by'] != null) {
                          await _supabase.from('notifications').insert({
                            'institution_id': request['institution_id'],
                            'recipient_id': request['requested_by'],
                            'title': 'Request Approved',
                            'message':
                                '"${request['requested_boarding_point']}" approved.',
                          });
                        }
                        if (context.mounted) Navigator.pop(context);
                        _fetchRouteRequests();
                        _fetchLiveRoutesAndStops();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Failed: $e'),
                                backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    },
              child: const Text('Confirm', style: TextStyle(color: Ym.navy, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rejectRequest(dynamic requestId) async {
    try {
      final request = _pendingRequests.firstWhere(
          (r) => r['id'] == requestId, orElse: () => {});
      await _supabase
          .from('route_requests')
          .update({'status': 'rejected'}).eq('id', requestId);
      if (request.isNotEmpty && request['requested_by'] != null) {
        await _supabase.from('notifications').insert({
          'institution_id': request['institution_id'],
          'recipient_id': request['requested_by'],
          'title': 'Request Declined',
          'message': '"${request['requested_boarding_point']}" was declined.',
        });
      }
      _fetchRouteRequests();
    } catch (e) {
      debugPrint('Error rejecting: $e');
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
          (route) => false,
        );
      }
    }
  }

  void _showPendingRequestsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SizedBox(
        height: 400,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Pending Route Requests',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Expanded(
              child: _pendingRequests.isEmpty
                  ? const Center(child: Text('No pending requests.'))
                  : ListView.builder(
                      itemCount: _pendingRequests.length,
                      itemBuilder: (context, index) {
                        final request = _pendingRequests[index];
                        return ListTile(
                          title: Text(request['requested_boarding_point'] ?? ''),
                          subtitle: Text(
                              'Submitted: ${request['created_at'].toString().substring(0, 10)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _openApprovalDialog(request);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _rejectRequest(request['id']);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateRouteName(dynamic routeId, String newName) async {
    if (newName.trim().isEmpty) return;
    try {
      await _supabase
          .from('routes')
          .update({'route_name': newName.trim()}).eq('id', routeId);
      await _fetchLiveRoutesAndStops();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route updated.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _deleteRoute(dynamic routeId) async {
    try {
      await _supabase.from('routes').delete().eq('id', routeId);
      await _fetchLiveRoutesAndStops();
      await _loadDashboardData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route deleted.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _updateStop(dynamic stopId, String newName, String newTiming) async {
    if (newName.trim().isEmpty) return;
    try {
      await _supabase.from('stops').update({
        'stop_name': newName.trim(),
        'timing': newTiming.trim().isEmpty ? '07:30:00' : newTiming.trim(),
      }).eq('id', stopId);
      await _fetchLiveRoutesAndStops();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // ──────────────────────────────────────────────
  // NEW: Opens the OpenStreetMap picker for a stop, then saves the
  // resulting lat/lng straight into the `stops` table (columns are
  // `lat` and `lng` in this project, confirmed from the schema check).
  // `onDone` lets the caller refresh the open Edit Route dialog so the
  // pin icon turns green immediately without closing/reopening it.
  // ──────────────────────────────────────────────
  Future<void> _pickStopLocation(
      Map<String, dynamic> stop, VoidCallback onDone) async {
    double? existingLat =
        stop['lat'] != null ? double.tryParse(stop['lat'].toString()) : null;
    double? existingLng =
        stop['lng'] != null ? double.tryParse(stop['lng'].toString()) : null;

    LatLng? initialLocation;
    if (existingLat != null && existingLng != null) {
      initialLocation = LatLng(existingLat, existingLng);
    }

    final LatLng? selected = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLocation: initialLocation,
          title: 'Pick Stop Location',
        ),
      ),
    );

    if (selected == null) return;

    try {
      await _supabase.from('stops').update({
        'lat': selected.latitude,
        'lng': selected.longitude,
      }).eq('id', stop['id']);

      await _fetchLiveRoutesAndStops();
      onDone();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location saved ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save location: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _deleteStop(dynamic stopId) async {
    try {
      await _supabase.from('stops').delete().eq('id', stopId);
      await _fetchLiveRoutesAndStops();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _addStop(dynamic routeId, String name, String timing) async {
    if (name.trim().isEmpty) return;
    try {
      await _supabase.from('stops').insert({
        'route_id': routeId,
        'stop_name': name.trim(),
        'timing': timing.trim().isEmpty ? '07:30:00' : timing.trim(),
      });
      await _fetchLiveRoutesAndStops();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _openEditRouteDialog(Map<String, dynamic> initialRoute) {
    final routeId = initialRoute['id'];
    final routeNameController =
        TextEditingController(text: initialRoute['route_name'] ?? '');
    final newStopNameController = TextEditingController();
    final newStopTimingController = TextEditingController(text: '07:30:00');

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) {
          final liveRoute = _liveDatabaseRoutesWithStops.firstWhere(
            (r) => r['id'] == routeId,
            orElse: () => initialRoute,
          );
          final List stops = (liveRoute['stops'] as List?) ?? [];

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Edit Route'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: routeNameController,
                      decoration: InputDecoration(
                        labelText: 'Route Name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Stops', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),

                    // ── Stop rows: name + timing + 📍 location + save + delete ──
                    ...stops.map((stop) {
                      final nameCtrl =
                          TextEditingController(text: stop['stop_name'] ?? '');
                      final timingCtrl =
                          TextEditingController(text: stop['timing'] ?? '');
                      final hasLocation =
                          stop['lat'] != null && stop['lng'] != null;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: nameCtrl,
                                decoration: const InputDecoration(labelText: 'Stop', isDense: true),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: timingCtrl,
                                decoration: const InputDecoration(labelText: 'Timing', isDense: true),
                              ),
                            ),
                            IconButton(
                              tooltip: hasLocation ? 'Edit location' : 'Add location',
                              icon: Icon(
                                hasLocation ? Icons.location_on : Icons.location_on_outlined,
                                color: hasLocation ? Colors.green : Colors.grey,
                                size: 20,
                              ),
                              onPressed: () => _pickStopLocation(
                                stop,
                                () => setModalState(() {}),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.save_outlined, color: Color(0xFF3B5BFF), size: 18),
                              onPressed: () async {
                                await _updateStop(stop['id'], nameCtrl.text, timingCtrl.text);
                                setModalState(() {});
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                              onPressed: () async {
                                await _deleteStop(stop['id']);
                                setModalState(() {});
                              },
                            ),
                          ],
                        ),
                      );
                    }),

                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: newStopNameController,
                            decoration: const InputDecoration(labelText: 'New stop name', isDense: true),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: newStopTimingController,
                            decoration: const InputDecoration(labelText: 'HH:MM:SS', isDense: true),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.green),
                          onPressed: () async {
                            await _addStop(routeId, newStopNameController.text, newStopTimingController.text);
                            newStopNameController.clear();
                            newStopTimingController.text = '07:30:00';
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: dialogContext,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Route?'),
                      content: const Text('This will delete all stops too.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _deleteRoute(routeId);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  }
                },
                child: const Text('Delete Route', style: TextStyle(color: Colors.redAccent)),
              ),
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Ym.amber, foregroundColor: Ym.navy, elevation: 0),
                onPressed: () async {
                  await _updateRouteName(routeId, routeNameController.text);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('Save', style: TextStyle(color: Ym.navy, fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Staying signed in: back button should exit the app, not fall
      // through to Role Selection. Only _handleLogout() is allowed to
      // leave this screen (it clears the stack itself).
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        final now = DateTime.now();
        final isSecondPress = _lastBackPress != null &&
            now.difference(_lastBackPress!) < const Duration(seconds: 2);
        if (isSecondPress) {
          SystemNavigator.pop();
        } else {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Ym.creamTop,
        body: YmBackground(
          child: IndexedStack(
          index: _currentIndex,
          children: [
            _HomeTab(
              institutionName: _institutionName,
              institutionCity: _institutionCity,
              totalStudents: _totalStudents,
              totalBuses: _totalBuses,
              totalRoutes: _totalRoutes,
              totalDrivers: _totalDrivers,
              helpdeskCount: _helpdeskCount,
              tripsToday: _tripsToday,
              tripsRunning: _tripsRunning,
              pendingCredentials: _pendingCredentials,
              isLoading: _isLoadingStats,
              onRefresh: () async {
                await _loadDashboardData();
                await _fetchRouteRequests();
                await _fetchLiveRoutesAndStops();
              },
              pendingRequests: _pendingRequests,
              onApproveRequest: _openApprovalDialog,
              onRejectRequest: _rejectRequest,
              onBellTap: _showPendingRequestsSheet,
              onLogout: _handleLogout,
              stagedExcelRoutes: _stagedExcelRoutes,
              isProcessingExcel: _isProcessingExcel,
              onImportExcel: _importExcelFile,
              onSaveExcel: _saveExcelDataToDatabase,
              onRemoveStagedItem: (idx) => setState(() => _stagedExcelRoutes.removeAt(idx)),
              onUpdateStagedItem: (idx, field, newVal) =>
                  setState(() => _stagedExcelRoutes[idx][field] = newVal.toString()),
            ),
            // ✅ HELP DESK TAB — fully connected
            _HelpdeskManagementTab(
              supabase: _supabase,
              institutionId: _institutionId,
              onHelpdeskAdded: () {
                _loadDashboardData();
              },
            ),
            _CommutersTab(
              supabase: _supabase,
              institutionId: _institutionId,
            ),
            _BusDetailsTab(
              liveRoutes: _liveDatabaseRoutesWithStops,
              isLoading: _isLoadingLiveRoutes,
              onRefresh: _fetchLiveRoutesAndStops,
              onEditRoute: _openEditRouteDialog,
            ),
            AdminDriversTab(
              supabase: _supabase,
              institutionId: _institutionId,
              routes: _availableRoutes,
              onChanged: _loadDashboardData,
            ),
            _AnnouncementsTab(
              supabase: _supabase,
              institutionId: _institutionId,
              buses: _buses,
              routes: _availableRoutes,
            ),
          ],
        )),
        bottomNavigationBar: SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: Ym.shadow(Ym.navy, 0.18),
            ),
            child: Row(
              children: [
                Expanded(child: _NavItem(icon: Icons.home_rounded, label: 'Home', index: 0, currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i))),
                Expanded(child: _NavItem(icon: Icons.support_agent_rounded, label: 'Helpdesk', index: 1, currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i))),
                Expanded(child: _NavItem(icon: Icons.people_rounded, label: 'Commuters', index: 2, currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i))),
                Expanded(child: _NavItem(icon: Icons.directions_bus_rounded, label: 'Bus Details', index: 3, currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i))),
                Expanded(child: _NavItem(icon: Icons.person_rounded, label: 'Drivers', index: 4, currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i))),
                Expanded(child: _NavItem(icon: Icons.campaign_rounded, label: 'Announcements', index: 5, currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// HELPDESK MANAGEMENT TAB
// ══════════════════════════════════════════════
class _HelpdeskManagementTab extends StatefulWidget {
  final SupabaseClient supabase;
  final String? institutionId;
  final VoidCallback onHelpdeskAdded;

  const _HelpdeskManagementTab({
    required this.supabase,
    required this.institutionId,
    required this.onHelpdeskAdded,
  });

  @override
  State<_HelpdeskManagementTab> createState() => _HelpdeskManagementTabState();
}

class _HelpdeskManagementTabState extends State<_HelpdeskManagementTab> {
  List<Map<String, dynamic>> _helpdesks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHelpdesks();
  }

  @override
  void didUpdateWidget(covariant _HelpdeskManagementTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // IndexedStack builds this tab immediately on app launch, often before
    // the parent's async _loadDashboardData() has resolved _institutionId.
    // The very first _fetchHelpdesks() call above can run with a null ID
    // and silently bail out — and since this State object is never
    // recreated (IndexedStack keeps it alive), initState never fires again.
    // This catches the moment institutionId actually arrives and re-fetches.
    if (oldWidget.institutionId == null && widget.institutionId != null) {
      _fetchHelpdesks();
    }
  }

  Future<void> _fetchHelpdesks() async {
    setState(() => _isLoading = true);
    try {
      if (widget.institutionId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final data = await widget.supabase
          .from('helpdesk_accounts')
          .select()
          .eq('institution_id', widget.institutionId!)
          .order('created_at', ascending: false);
      setState(() {
        _helpdesks = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Error loading helpdesks: $e');
    }
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _generatePassword(String name) {
    final clean = name.replaceAll(' ', '')
        .substring(0, name.length > 4 ? 4 : name.length)
        .toUpperCase();
    final num = DateTime.now().millisecondsSinceEpoch % 9000 + 1000;
    return 'YM@$clean$num';
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool autoGenerate = true;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Help Desk Account',
              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F1B4C))),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field('Full Name', nameCtrl, hint: 'e.g. Rahul Kumar'),
                  const SizedBox(height: 12),
                  _field('Email', emailCtrl, hint: 'helpdesk@college.edu', isEmail: true),
                  const SizedBox(height: 12),
                  _field('Phone (optional)', phoneCtrl, hint: '9876543210'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Auto Generate Password',
                          style: TextStyle(fontSize: 13, color: Color(0xFF6B7A99))),
                      Switch(
                        value: autoGenerate,
                        activeColor: const Color(0xFF3B5BFF),
                        onChanged: (val) => setDialog(() => autoGenerate = val),
                      ),
                    ],
                  ),
                  if (!autoGenerate) ...[
                    const SizedBox(height: 8),
                    _field('Password', passCtrl, hint: 'Min 6 characters', isPassword: true),
                  ],
                  if (autoGenerate)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: Color(0xFF3B5BFF)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Password auto-generated and sent to email.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF3B5BFF)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Ym.amber,
                foregroundColor: Ym.navy,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: isLoading ? null : () async {
                final name = nameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                final phone = phoneCtrl.text.trim();

                if (name.isEmpty || email.isEmpty) {
                  _showSnack('Name and email are required');
                  return;
                }
                if (!autoGenerate && passCtrl.text.trim().length < 6) {
                  _showSnack('Password must be at least 6 characters');
                  return;
                }

                setDialog(() => isLoading = true);
                final password = autoGenerate ? _generatePassword(name) : passCtrl.text.trim();

                try {
                  final response = await widget.supabase.functions.invoke(
                    'create-helpdesk-user',
                    body: {
                      'name': name,
                      'email': email,
                      'password': password,
                      'phone': phone,
                      'role': 'help_desk',
                      'institution_id': widget.institutionId,
                    },
                  );

                  if (response.status == 200) {
                    if (mounted) Navigator.pop(context);
                    _fetchHelpdesks();
                    widget.onHelpdeskAdded();
                    _showSnack(
                      autoGenerate
                          ? 'Account created! Credentials sent to $email ✅'
                          : 'Account created successfully! ✅',
                      isError: false,
                    );
                    if (!autoGenerate && mounted) {
                      _showCredsDialog(email, password);
                    }
                  } else {
                    final error = response.data?['error'] ?? 'Unknown error';
                    _showSnack('Failed: $error');
                  }
                } catch (e) {
                  _showSnack('Error: $e');
                } finally {
                  setDialog(() => isLoading = false);
                }
              },
              child: isLoading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(color: Ym.navy, strokeWidth: 2),
                    )
                  : const Text('Create Account', style: TextStyle(color: Ym.navy, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCredsDialog(String email, String password, {String title = '✅ Account Created!'}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share these credentials:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📧 $email', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('🔑 $password',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B5BFF))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Ym.amber, foregroundColor: Ym.navy, elevation: 0),
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!', style: TextStyle(color: Ym.navy, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteHelpdesk(String userId, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text('This will permanently delete the helpdesk account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final response = await widget.supabase.functions.invoke(
          'delete-helpdesk-user',
          body: {'user_id': userId},
        );
        if (response.status == 200) {
          _fetchHelpdesks();
          widget.onHelpdeskAdded();
          _showSnack('Account deleted', isError: false);
        } else {
          _showSnack('Failed to delete account');
        }
      } catch (e) {
        _showSnack('Error: $e');
      }
    }
  }

  Future<void> _toggleActive(String id, bool current) async {
    try {
      await widget.supabase
          .from('helpdesk_accounts')
          .update({'is_active': !current})
          .eq('id', id);
      _fetchHelpdesks();
      _showSnack(!current ? 'Account enabled ✅' : 'Account disabled', isError: false);
    } catch (e) {
      _showSnack('Error: $e');
    }
  }

  Future<void> _resetAndEmailPassword(Map<String, dynamic> hd) async {
    final email = hd['email'] as String?;
    final name = hd['name'] as String?;

    if (email == null || email.isEmpty) {
      _showSnack('This account has no email on file');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset & Email Password?'),
        content: Text(
          'A new password will be generated and emailed to $email. Their current password will stop working immediately.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Ym.amber, foregroundColor: Ym.navy, elevation: 0),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset & Email', style: TextStyle(color: Ym.navy, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final newPassword = _generatePassword(name ?? 'User');

    try {
      final response = await widget.supabase.functions.invoke(
        'reset-helpdesk-password',
        body: {
          'email': email,
          'new_password': newPassword,
          'name': name ?? 'User',
        },
      );

      if (response.status == 200) {
        final emailSent = response.data?['email_sent'] == true;
        _showSnack(
          emailSent
              ? 'New password emailed to $email ✅'
              : 'Password was reset, but the email failed to send. New password: $newPassword',
          isError: !emailSent,
        );
        if (!emailSent && mounted) {
          _showCredsDialog(email, newPassword, title: '🔑 Password Reset');
        }
      } else {
        final error = response.data?['error'] ?? 'Unknown error';
        _showSnack('Failed to reset password: $error');
      }
    } catch (e) {
      _showSnack('Error: $e');
    }
  }

  Widget _field(String label, TextEditingController ctrl,
      {String hint = '', bool isEmail = false, bool isPassword = false}) {
    return TextField(
      controller: ctrl,
      obscureText: isPassword,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7A99)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0),
      body: SafeArea(
        child: Column(
          children: [
            _AdminHeader(
              title: 'Help Desk',
              subtitle: _isLoading
                  ? 'Manage help desk accounts'
                  : '${_helpdesks.length} account${_helpdesks.length == 1 ? '' : 's'}',
              icon: Icons.support_agent_rounded,
              trailing: _PillButton(label: 'Add', icon: Icons.add_rounded, onTap: _showAddDialog),
            ),
            Expanded(
              child: _isLoading
                  ? const YmSkeletonList(count: 4, height: 84)
                  : _helpdesks.isEmpty
                      ? const _AdminEmpty(
                          icon: Icons.support_agent_rounded,
                          title: 'No help desk accounts yet',
                          subtitle: 'Tap Add to create the first one.',
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchHelpdesks,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                            itemCount: _helpdesks.length,
                            itemBuilder: (context, index) {
                              final hd = _helpdesks[index];
                              final isActive = hd['is_active'] ?? true;
                              final name = (hd['name'] ?? 'Unknown').toString();
                              final phone = (hd['phone'] ?? '').toString();
                              return YmFadeSlide(
                                index: index,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: _adminShadow,
                                  ),
                                  child: Row(
                                    children: [
                                      _Avatar(
                                          name: name,
                                          color: isActive
                                              ? const Color(0xFF3B5BFF)
                                              : const Color(0xFF8892AA)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(name,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15,
                                                    color: Color(0xFF0F1B4C))),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                const Icon(Icons.mail_outline_rounded,
                                                    size: 13, color: Color(0xFF8892AA)),
                                                const SizedBox(width: 5),
                                                Expanded(
                                                  child: Text(hd['email'] ?? '',
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Color(0xFF8892AA))),
                                                ),
                                              ],
                                            ),
                                            if (phone.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.phone_outlined,
                                                        size: 13, color: Color(0xFF8892AA)),
                                                    const SizedBox(width: 5),
                                                    Text(phone,
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            color: Color(0xFF8892AA))),
                                                  ],
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            _InfoChip(isActive ? 'Active' : 'Inactive',
                                                icon: isActive
                                                    ? Icons.check_circle_rounded
                                                    : Icons.block_rounded,
                                                color: isActive
                                                    ? const Color(0xFF16A34A)
                                                    : Colors.redAccent),
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert_rounded,
                                            color: Color(0xFF8892AA), size: 20),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14)),
                                        onSelected: (value) {
                                          if (value == 'toggle') {
                                            _toggleActive(hd['id'], isActive);
                                          } else if (value == 'reset') {
                                            _resetAndEmailPassword(hd);
                                          } else if (value == 'delete') {
                                            _deleteHelpdesk(hd['user_id'], hd['id']);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'toggle',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  isActive
                                                      ? Icons.block_rounded
                                                      : Icons.check_circle_rounded,
                                                  color: isActive ? Colors.orange : Colors.green,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 10),
                                                Text(isActive ? 'Deactivate' : 'Activate'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'reset',
                                            child: Row(
                                              children: [
                                                Icon(Icons.lock_reset_rounded,
                                                    color: Color(0xFF3B5BFF), size: 18),
                                                SizedBox(width: 10),
                                                Text('Reset & Email Password'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete_rounded,
                                                    color: Colors.redAccent, size: 18),
                                                SizedBox(width: 10),
                                                Text('Delete',
                                                    style: TextStyle(color: Colors.redAccent)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// COMMUTERS TAB (Students / Faculty grouped by route)
// ══════════════════════════════════════════════
enum _CommutersView { menu, studentRoutes, studentList, facultyRoutes, facultyList }

class _CommutersTab extends StatefulWidget {
  final SupabaseClient supabase;
  final String? institutionId;

  const _CommutersTab({
    required this.supabase,
    required this.institutionId,
  });

  @override
  State<_CommutersTab> createState() => _CommutersTabState();
}

class _CommutersTabState extends State<_CommutersTab> {
  _CommutersView _view = _CommutersView.menu;
  bool _isLoading = false;

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _faculty = [];
  String? _selectedRouteName;
  String _search = '';

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _fetchStudents() async {
    if (widget.institutionId == null) {
      _showSnack('Institution not loaded yet — try again in a moment.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final data = await widget.supabase
          .from('students')
          .select(
              'id, student_name, enrollment_no, student_email, student_phone, '
              'department, year, admission_date, parent_name, parent_relation, '
              'parent_email, parent_phone, fee_status, boarding_point, pass_expiry, '
              'route_id, routes(route_name)')
          .eq('institution_id', widget.institutionId!)
          .eq('credential_generated', true)
          .order('student_name', ascending: true);
      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showSnack('Error loading students: $e');
    }
  }

  /// the admin makes this faculty member the in-charge of their route
  Future<void> _assignIncharge(Map<String, dynamic> f) async {
    final name = (f['faculty_name'] ?? 'this person').toString();
    if (f['route_id'] == null) {
      _showSnack('$name has no route yet. Assign a route first, then make them the in-charge.');
      return;
    }
    final route = ((f['routes'] as Map?)?['route_name'] ?? 'this route').toString();
    final hasOne = _faculty.any((p) =>
        p['route_id'] == f['route_id'] &&
        (p['routes'] as Map?)?['incharge_faculty_id'] == p['id']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Make $name the in-charge?', style: Ym.h(18)),
        content: Text(
          '$name will be the in-charge of $route. Their dashboard will show the in-charge tools '
          '(scan bus passes, route complaints and ride requests).'
          '\n\nA NEW password is emailed to ${f['faculty_email'] ?? 'them'}. It is the same login, '
          'so their old password stops working.'
          '${hasOne ? '\n\nThe current in-charge of this route will be replaced.' : ''}',
          style: Ym.t(13.5, color: Ym.grey).copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Make in-charge',
                  style: Ym.t(14, color: Ym.amberDark, w: FontWeight.w800))),
        ],
      ),
    );
    if (ok != true) return;
    await _callMakeIncharge(f, resend: false);
  }

  /// the admin puts a faculty member who has no route on one of the institution's routes
  Future<void> _assignRoute(Map<String, dynamic> f) async {
    final name = (f['faculty_name'] ?? 'This person').toString();
    if (widget.institutionId == null) {
      _showSnack('Institution not loaded yet — try again in a moment.');
      return;
    }
    try {
      final rows = await widget.supabase
          .from('routes')
          .select('id, route_name')
          .eq('institution_id', widget.institutionId!)
          .order('route_name');
      if (!mounted) return;
      if (rows.isEmpty) {
        _showSnack('There are no routes yet. Add a route first.');
        return;
      }
      final chosen = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (c) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4.5,
                    decoration: BoxDecoration(
                        color: Ym.line, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Choose a route for $name', style: Ym.h(18)),
                const SizedBox(height: 4),
                Text('They will appear under this route in Commuters.',
                    style: Ym.t(12.5, color: Ym.grey)),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final r in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: YmCard(
                            onTap: () => Navigator.pop(c, Map<String, dynamic>.from(r)),
                            padding: const EdgeInsets.all(14),
                            radius: 18,
                            child: Row(
                              children: [
                                const YmIconBadge(icon: Icons.route_rounded, size: 40),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text((r['route_name'] ?? 'Route').toString(),
                                      style: Ym.h(14.5)),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: Ym.grey),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (chosen == null) return;
      await widget.supabase
          .from('faculty')
          .update({'route_id': chosen['id']}).eq('id', f['id']);
      _showSnack('$name is now on ${chosen['route_name']}.');
      await _fetchFaculty();
    } catch (e) {
      _showSnack('Could not assign the route: $e');
    }
  }

  /// Runs the make-incharge function: it assigns the in-charge, sets a NEW password
  /// and emails it. With resend: true it only makes and emails another new password.
  Future<void> _callMakeIncharge(Map<String, dynamic> f, {required bool resend}) async {
    final name = (f['faculty_name'] ?? 'This person').toString();
    final route = ((f['routes'] as Map?)?['route_name'] ?? 'the route').toString();
    try {
      final res = await widget.supabase.functions.invoke('make-incharge', body: {
        'route_id': f['route_id'],
        'faculty_id': f['id'],
        'resend': resend,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      if (data['emailed'] == true) {
        _showSnack(resend
            ? 'New credentials emailed to ${data['email'] ?? 'the in-charge'}.'
            : '$name is now the in-charge of $route. Credentials emailed to ${data['email'] ?? 'them'}.');
      } else {
        _showSnack('${resend ? '' : '$name is now the in-charge of $route. '}'
            '${data['warning'] ?? 'The email could not be sent.'}');
      }
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = d is Map ? (d['error'] ?? d.toString()).toString() : '$d';
      if (e.status == 404 && !resend) {
        // the email function is not set up yet: still make them the in-charge
        try {
          await widget.supabase.rpc('assign_incharge',
              params: {'p_route': f['route_id'], 'p_faculty': f['id']});
          _showSnack('$name is now the in-charge of $route, but no email was sent: '
              'the make-incharge function is not set up yet.');
        } on PostgrestException catch (e2) {
          _showSnack(e2.message);
        }
      } else {
        _showSnack(msg);
      }
    } on PostgrestException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Could not complete this: $e');
    }
    await _fetchFaculty();
  }

  Future<void> _removeIncharge(Map<String, dynamic> f) async {
    final name = (f['faculty_name'] ?? 'this person').toString();
    final route = ((f['routes'] as Map?)?['route_name'] ?? 'this route').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Remove the in-charge?', style: Ym.h(18)),
        content: Text(
          '$name will no longer be the in-charge of $route. They stay as a normal faculty member.',
          style: Ym.t(13.5, color: Ym.grey).copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Remove', style: Ym.t(14, color: Ym.red, w: FontWeight.w800))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.supabase.rpc('remove_incharge', params: {'p_route': f['route_id']});
      _showSnack('$name is no longer the in-charge of $route.');
      await _fetchFaculty();
    } on PostgrestException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Could not remove the in-charge: $e');
    }
  }

  Future<void> _fetchFaculty() async {
    if (widget.institutionId == null) {
      _showSnack('Institution not loaded yet — try again in a moment.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final data = await widget.supabase
          .from('faculty')
          .select(
              'id, faculty_name, employee_id, faculty_email, faculty_phone, '
              'department, boarding_point, route_id, '
              'routes(route_name, incharge_faculty_id)')
          .eq('institution_id', widget.institutionId!)
          .eq('credential_generated', true)
          .order('faculty_name', ascending: true);
      if (mounted) {
        setState(() {
          _faculty = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showSnack('Error loading faculty: $e');
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupByRoute(List<Map<String, dynamic>> items) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final item in items) {
      final routeInfo = item['routes'];
      final routeName = (routeInfo != null && routeInfo['route_name'] != null)
          ? routeInfo['route_name'] as String
          : null;
      final key = routeName ?? 'Unassigned';
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    switch (_view) {
      case _CommutersView.menu:
        return _buildMenu();
      case _CommutersView.studentRoutes:
        return _buildRouteList(isStudent: true);
      case _CommutersView.studentList:
        return _buildPersonList(isStudent: true);
      case _CommutersView.facultyRoutes:
        return _buildRouteList(isStudent: false);
      case _CommutersView.facultyList:
        return _buildPersonList(isStudent: false);
    }
  }

  Widget _buildMenu() {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _AdminHeader(
            title: 'Commuters',
            subtitle: 'Students and faculty grouped by route',
            icon: Icons.people_rounded,
            color: Color(0xFF7C3AED),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Column(
              children: [
                YmFadeSlide(
                  index: 0,
                  child: _CommuterOptionCard(
                    icon: Icons.school_rounded,
                    iconBg: const Color(0xFFEDE9FE),
                    iconColor: const Color(0xFF7C3AED),
                    title: 'Students',
                    subtitle: 'Students with generated credentials',
                    onTap: () {
                      setState(() => _view = _CommutersView.studentRoutes);
                      _fetchStudents();
                    },
                  ),
                ),
                const SizedBox(height: 14),
                YmFadeSlide(
                  index: 1,
                  child: _CommuterOptionCard(
                    icon: Icons.badge_rounded,
                    iconBg: const Color(0xFFDBEAFE),
                    iconColor: const Color(0xFF2563EB),
                    title: 'Faculties',
                    subtitle: 'Faculty with generated credentials',
                    onTap: () {
                      setState(() => _view = _CommutersView.facultyRoutes);
                      _fetchFaculty();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteList({required bool isStudent}) {
    final items = isStudent ? _students : _faculty;
    final grouped = _groupByRoute(items);
    final routeNames = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'Unassigned') return 1;
        if (b == 'Unassigned') return -1;
        return a.compareTo(b);
      });
    final accent = isStudent ? const Color(0xFF7C3AED) : const Color(0xFF2563EB);

    return SafeArea(
      child: Column(
        children: [
          _AdminHeader(
            title: isStudent ? 'Students by Route' : 'Faculty by Route',
            subtitle: _isLoading
                ? 'Loading…'
                : '${items.length} ${isStudent ? 'student' : 'faculty member'}${items.length == 1 ? '' : 's'}  •  ${routeNames.length} route${routeNames.length == 1 ? '' : 's'}',
            icon: isStudent ? Icons.school_rounded : Icons.badge_rounded,
            color: accent,
            onBack: () => setState(() => _view = _CommutersView.menu),
          ),
          Expanded(
            child: _isLoading
                ? const YmSkeletonList(count: 4, height: 84)
                : routeNames.isEmpty
                    ? _AdminEmpty(
                        icon: isStudent ? Icons.school_outlined : Icons.badge_outlined,
                        color: accent,
                        title: isStudent
                            ? 'No students with credentials yet'
                            : 'No faculty with credentials yet',
                        subtitle: 'People appear here after the admin generates their login.',
                      )
                    : RefreshIndicator(
                        onRefresh: isStudent ? _fetchStudents : _fetchFaculty,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                          itemCount: routeNames.length,
                          itemBuilder: (context, index) {
                            final routeName = routeNames[index];
                            final list = grouped[routeName]!;
                            final isUnassigned = routeName == 'Unassigned';
                            final tint = isUnassigned ? Colors.redAccent : const Color(0xFF3B5BFF);
                            return YmFadeSlide(
                              index: index,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: YmPressable(
                                  scale: 0.98,
                                  onTap: () {
                                    setState(() {
                                      _search = '';
                                      _selectedRouteName = routeName;
                                      _view = isStudent
                                          ? _CommutersView.studentList
                                          : _CommutersView.facultyList;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: _adminShadow,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                tint.withOpacity(0.2),
                                                tint.withOpacity(0.07)
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(15),
                                          ),
                                          child: Icon(Icons.route_rounded, color: tint, size: 22),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(routeName,
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 15,
                                                      color: Color(0xFF0F1B4C))),
                                              const SizedBox(height: 3),
                                              Text(
                                                  '${list.length} ${isStudent ? 'student' : 'faculty member'}${list.length == 1 ? '' : 's'}',
                                                  style: const TextStyle(
                                                      fontSize: 12, color: Color(0xFF8892AA))),
                                            ],
                                          ),
                                        ),
                                        _InfoChip('${list.length}', color: tint),
                                        const SizedBox(width: 6),
                                        const Icon(Icons.chevron_right_rounded,
                                            color: Color(0xFF8892AA)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  bool _isIncharge(Map<String, dynamic> f) =>
      (f['routes'] as Map?)?['incharge_faculty_id'] == f['id'];

  /// "  •  In-charge: Name" or "  •  No in-charge yet"
  String _inchargeLine(List<Map<String, dynamic>> onRoute) {
    for (final f in onRoute) {
      if (_isIncharge(f)) return '  •  In-charge: ${f['faculty_name']}';
    }
    return '  •  No in-charge yet';
  }

  Widget _buildPersonList({required bool isStudent}) {
    final items = isStudent ? _students : _faculty;
    final grouped = _groupByRoute(items);
    final routeName = _selectedRouteName ?? 'Unassigned';
    final all = grouped[routeName] ?? [];
    final q = _search.trim().toLowerCase();
    final list = q.isEmpty
        ? all
        : all.where((p) {
            final fields = isStudent
                ? [p['student_name'], p['enrollment_no'], p['student_email'], p['student_phone']]
                : [p['faculty_name'], p['employee_id'], p['faculty_email'], p['faculty_phone']];
            return fields.any((f) => (f ?? '').toString().toLowerCase().contains(q));
          }).toList();
    final accent = isStudent ? const Color(0xFF7C3AED) : const Color(0xFF2563EB);

    return SafeArea(
      child: Column(
        children: [
          _AdminHeader(
            title: routeName,
            subtitle: '${all.length} ${isStudent ? 'student' : 'faculty member'}${all.length == 1 ? '' : 's'}'
                '${isStudent ? '' : _inchargeLine(all)}',
            icon: Icons.route_rounded,
            color: accent,
            onBack: () => setState(() {
              _search = '';
              _view = isStudent
                  ? _CommutersView.studentRoutes
                  : _CommutersView.facultyRoutes;
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: TextField(
              key: ValueKey('search_$routeName'),
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(fontSize: 14, color: Color(0xFF0F1B4C)),
              decoration: InputDecoration(
                hintText: 'Search by name, ID, email or phone',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF8892AA)),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF8892AA)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFF0E2C8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF3B5BFF), width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? _AdminEmpty(
                    icon: Icons.search_off_rounded,
                    color: accent,
                    title: q.isEmpty ? 'No records found' : 'No match for "$_search"',
                    subtitle: q.isEmpty ? 'Nobody on this route yet.' : 'Try a different name or ID.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final person = list[index];
                      return YmFadeSlide(
                        index: index,
                        child: isStudent
                            ? _StudentDetailCard(
                                student: person,
                                onLinkCard: () =>
                                    showLinkRfidSheet(context, person, onDone: _fetchStudents),
                              )
                            : _FacultyDetailCard(
                                faculty: person,
                                isIncharge: _isIncharge(person),
                                onMakeIncharge: () => _assignIncharge(person),
                                onRemoveIncharge: () => _removeIncharge(person),
                                onResendCredentials: () =>
                                    _callMakeIncharge(person, resend: true),
                                onAssignRoute: () => _assignRoute(person),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CommuterOptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CommuterOptionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return YmPressable(
      scale: 0.98,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, iconBg.withOpacity(0.55)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: _adminShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F1B4C))),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA))),
                ],
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chevron_right_rounded, color: iconColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentDetailCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final VoidCallback? onLinkCard;
  const _StudentDetailCard({required this.student, this.onLinkCard});

  @override
  Widget build(BuildContext context) {
    final feeStatus = (student['fee_status'] ?? 'unpaid').toString();
    final feeColor = feeStatus == 'paid'
        ? const Color(0xFF16A34A)
        : feeStatus == 'partial'
            ? const Color(0xFFD97706)
            : Colors.redAccent;
    final name = (student['student_name'] ?? 'Unknown').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: _adminShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(name: name, color: const Color(0xFF7C3AED), size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: Color(0xFF0F1B4C))),
                    const SizedBox(height: 2),
                    Text((student['enrollment_no'] ?? '—').toString(),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA))),
                  ],
                ),
              ),
              _InfoChip(feeStatus.toUpperCase(), color: feeColor),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((student['department'] ?? '').toString().isNotEmpty)
                _InfoChip(student['department'].toString(),
                    icon: Icons.apartment_rounded, color: const Color(0xFF3B5BFF)),
              if ((student['year'] ?? '').toString().isNotEmpty)
                _InfoChip('Year ${student['year']}',
                    icon: Icons.school_outlined, color: const Color(0xFF7C3AED)),
              if ((student['boarding_point'] ?? '').toString().isNotEmpty)
                _InfoChip(student['boarding_point'].toString(),
                    icon: Icons.location_on_outlined, color: const Color(0xFF059669)),
              if ((student['pass_expiry'] ?? '').toString().isNotEmpty)
                _InfoChip('Pass till ${student['pass_expiry']}',
                    icon: Icons.confirmation_number_outlined,
                    color: const Color(0xFFD97706)),
            ],
          ),
          const Divider(height: 22, color: Color(0xFFF0E2C8)),
          _IconRow(icon: Icons.mail_outline_rounded, label: 'Email', value: student['student_email']),
          _IconRow(icon: Icons.phone_outlined, label: 'Phone', value: student['student_phone']),
          _IconRow(icon: Icons.event_outlined, label: 'Admitted', value: student['admission_date']),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              iconColor: const Color(0xFF8892AA),
              title: const Text('Parent / Guardian',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F1B4C))),
              children: [
                _IconRow(icon: Icons.person_outline_rounded, label: 'Name', value: student['parent_name']),
                _IconRow(icon: Icons.family_restroom_rounded, label: 'Relation', value: student['parent_relation']),
                _IconRow(icon: Icons.mail_outline_rounded, label: 'Email', value: student['parent_email']),
                _IconRow(icon: Icons.phone_outlined, label: 'Phone', value: student['parent_phone']),
              ],
            ),
          ),
          if (onLinkCard != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLinkCard,
                icon: const Icon(Icons.contactless_outlined, size: 18),
                label: const Text('RFID card'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                  side: const BorderSide(color: Color(0xFFDDD6FE)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FacultyDetailCard extends StatelessWidget {
  final Map<String, dynamic> faculty;
  final bool isIncharge;
  final VoidCallback? onMakeIncharge;
  final VoidCallback? onRemoveIncharge;
  final VoidCallback? onResendCredentials;
  final VoidCallback? onAssignRoute;
  const _FacultyDetailCard({
    required this.faculty,
    this.isIncharge = false,
    this.onMakeIncharge,
    this.onRemoveIncharge,
    this.onResendCredentials,
    this.onAssignRoute,
  });

  @override
  Widget build(BuildContext context) {
    final name = (faculty['faculty_name'] ?? 'Unknown').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: _adminShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(name: name, color: const Color(0xFF2563EB), size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: Color(0xFF0F1B4C))),
                    const SizedBox(height: 2),
                    Text((faculty['employee_id'] ?? '—').toString(),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA))),
                  ],
                ),
              ),
              if (isIncharge)
                const _InfoChip('In-charge',
                    icon: Icons.verified_user_rounded, color: Color(0xFF059669)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((faculty['department'] ?? '').toString().isNotEmpty)
                _InfoChip(faculty['department'].toString(),
                    icon: Icons.apartment_rounded, color: const Color(0xFF3B5BFF)),
              if ((faculty['boarding_point'] ?? '').toString().isNotEmpty)
                _InfoChip(faculty['boarding_point'].toString(),
                    icon: Icons.location_on_outlined, color: const Color(0xFF059669)),
            ],
          ),
          const Divider(height: 22, color: Color(0xFFF0E2C8)),
          _IconRow(icon: Icons.mail_outline_rounded, label: 'Email', value: faculty['faculty_email']),
          _IconRow(icon: Icons.phone_outlined, label: 'Phone', value: faculty['faculty_phone']),
          if (onAssignRoute != null && faculty['route_id'] == null) ...[
            const SizedBox(height: 14),
            Text(
              'No route yet. Choose a route to see them under it, and to make them the in-charge.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA), height: 1.4),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAssignRoute,
                icon: const Icon(Icons.alt_route_rounded, size: 18),
                label: const Text('Assign a route'),
                style: FilledButton.styleFrom(
                  backgroundColor: Ym.amber,
                  foregroundColor: Ym.navy,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ] else if (onMakeIncharge != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: isIncharge
                  ? Column(
                      children: [
                        FilledButton.icon(
                          onPressed: onResendCredentials,
                          icon: const Icon(Icons.forward_to_inbox_rounded, size: 18),
                          label: const Text('Resend credentials'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Ym.amber,
                            foregroundColor: Ym.navy,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: onRemoveIncharge,
                          icon: const Icon(Icons.person_remove_rounded, size: 18),
                          label: const Text('Remove in-charge'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(color: Color(0xFFF3B8B5)),
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ],
                    )
                  : FilledButton.icon(
                      onPressed: onMakeIncharge,
                      icon: const Icon(Icons.verified_user_outlined, size: 18),
                      label: const Text('Make in-charge'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Ym.amber,
                        foregroundColor: Ym.navy,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// ANNOUNCEMENTS TAB
// Compose + send broadcasts targeted to everyone or one stakeholder
// group. Writes straight to the existing `announcements` table
// (institution_id, created_by, title, body, target_role). No schema
// or Edge Function changes needed.
//
// FUTURE INTEGRATION (student/faculty/driver/help-desk dashboards):
// query announcements where institution_id = <theirs> AND
// target_role in ('all', '<their role>') ordered by created_at desc.
// That's the only wiring those dashboards need — nothing here changes
// when they're built.
// ══════════════════════════════════════════════
class _AnnouncementsTab extends StatefulWidget {
  final SupabaseClient supabase;
  final String? institutionId;
  final List<Map<String, dynamic>> buses;
  final List<Map<String, dynamic>> routes;

  const _AnnouncementsTab({
    required this.supabase,
    required this.institutionId,
    required this.buses,
    required this.routes,
  });

  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _targetType = 'role'; // 'role', 'bus', 'route'
  String _targetRole = 'all';
  dynamic _selectedBusId;
  dynamic _selectedRouteId;
  bool _isSending = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _announcements = [];
  int _view = 0; // 0 = compose, 1 = sent
  String _filter = 'all'; // all | roles | bus | route
  final Set<dynamic> _expanded = {};

  static const Color _annCream = Color(0xFFFFFBF2);
  static const Color _annLine = Color(0xFFF1E3C4);

  static const List<Map<String, dynamic>> _audiences = [
    {'value': 'all', 'label': 'Everyone', 'icon': Icons.campaign_rounded},
    {'value': 'student', 'label': 'Students', 'icon': Icons.school_rounded},
    {'value': 'faculty', 'label': 'Faculty', 'icon': Icons.badge_rounded},
    {'value': 'driver', 'label': 'Drivers', 'icon': Icons.directions_bus_rounded},
    {'value': 'help_desk', 'label': 'Help Desk', 'icon': Icons.support_agent_rounded},
    {'value': 'parent', 'label': 'Parents', 'icon': Icons.family_restroom_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
  }

  @override
  void didUpdateWidget(covariant _AnnouncementsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId == null && widget.institutionId != null) {
      _fetchAnnouncements();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAnnouncements() async {
    if (widget.institutionId == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final data = await widget.supabase
          .from('announcements')
          .select()
          .eq('institution_id', widget.institutionId!)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _announcements = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showSnack('Error loading announcements: $e');
    }
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _sendAnnouncement() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _showSnack('Please add both a title and a message.');
      return;
    }
    if (_targetType == 'bus' && _selectedBusId == null) {
      _showSnack('Please choose a bus.');
      return;
    }
    if (_targetType == 'route' && _selectedRouteId == null) {
      _showSnack('Please choose a route.');
      return;
    }
    if (widget.institutionId == null) {
      _showSnack('Institution not loaded yet — try again in a moment.');
      return;
    }
    setState(() => _isSending = true);
    try {
      final adminId = widget.supabase.auth.currentUser?.id;
      String targetRole = 'all';
      
      if (_targetType == 'role') {
        targetRole = _targetRole;
      } else if (_targetType == 'bus') {
        targetRole = 'bus_' + (_selectedBusId?.toString() ?? '');
      } else if (_targetType == 'route') {
        targetRole = 'route_' + (_selectedRouteId?.toString() ?? '');
      }
      
      await widget.supabase.from('announcements').insert({
        'institution_id': widget.institutionId,
        'created_by': adminId,
        'title': title,
        'body': body,
        'target_role': targetRole,
      });
      _titleCtrl.clear();
      _bodyCtrl.clear();
      setState(() {
        _targetType = 'role';
        _targetRole = 'all';
        _selectedBusId = null;
        _selectedRouteId = null;
      });
      await _fetchAnnouncements();
      if (mounted) setState(() => _view = 1); // show it in the Sent list
      _showSnack('Announcement sent ✅', isError: false);
    } catch (e) {
      _showSnack('Failed to send: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _deleteAnnouncement(dynamic id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Announcement?'),
        content: const Text('This will remove it for everyone it was sent to.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.supabase.from('announcements').delete().eq('id', id);
      _fetchAnnouncements();
    } catch (e) {
      _showSnack('Failed to delete: $e');
    }
  }

  String _audienceLabel(String value) {
    return _audiences.firstWhere(
      (a) => a['value'] == value,
      orElse: () => _audiences[0],
    )['label'] as String;
  }

  IconData _audienceIcon(String value) {
    return _audiences.firstWhere(
      (a) => a['value'] == value,
      orElse: () => _audiences[0],
    )['icon'] as IconData;
  }

  Color _audienceColor(String value) {
    switch (value) {
      case 'student':
        return const Color(0xFF7C3AED);
      case 'faculty':
        return const Color(0xFF2563EB);
      case 'driver':
        return const Color(0xFFD97706);
      case 'help_desk':
        return const Color(0xFF059669);
      case 'parent':
        return const Color(0xFFDB2777);
      default:
        return const Color(0xFF3B5BFF);
    }
  }

  // ── Small icon-in-a-rounded-square, matching the icon language used
  // throughout the rest of the dashboard (stat cards, help desk rows). ──
  Widget _iconBadge(IconData icon, Color bg, Color fg, {double size = 44, double iconSize = 20}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, color: fg, size: iconSize),
    );
  }

  InputDecoration _composerFieldDecoration({required String label, required String hint, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: Ym.amberDark),
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6B7A99)),
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _annLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Ym.amberDark, width: 1.6),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  String _targetLabel(String target) {
    if (target.startsWith('bus_')) {
      final id = target.substring(4);
      final match = widget.buses.where((b) => b['id'].toString() == id);
      return match.isEmpty ? 'A bus' : 'Bus ${match.first['bus_number']}';
    }
    if (target.startsWith('route_')) {
      final id = target.substring(6);
      final match = widget.routes.where((r) => r['id'].toString() == id);
      return match.isEmpty ? 'A route' : (match.first['route_name'] ?? 'A route').toString();
    }
    return _audienceLabel(target);
  }

  String _ago(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  String get _audienceSummary {
    if (_targetType == 'bus') {
      final m = widget.buses.where((b) => b['id'] == _selectedBusId);
      return m.isEmpty
          ? 'Choose a bus below'
          : 'Bus ${m.first['bus_number']}: its students and faculty';
    }
    if (_targetType == 'route') {
      final m = widget.routes.where((r) => r['id'] == _selectedRouteId);
      return m.isEmpty
          ? 'Choose a route below'
          : '${m.first['route_name']}: its students and faculty';
    }
    return _targetRole == 'all' ? 'Everyone' : _audienceLabel(_targetRole);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Ym.creamTop,
      child: SafeArea(
        child: Column(
          children: [
            _AdminHeader(
              title: 'Announcements',
              subtitle: _announcements.isEmpty
                  ? 'Broadcast updates to campus transport'
                  : '${_announcements.length} sent',
              icon: Icons.campaign_rounded,
            ),
            _viewSwitch(),
            Expanded(child: _view == 0 ? _composeView() : _sentView()),
          ],
        ),
      ),
    );
  }

  Widget _viewSwitch() {
    Widget tab(int i, String label, IconData icon) {
      final on = _view == i;
      return Expanded(
        child: YmPressable(
          onTap: () => setState(() => _view = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: on ? const LinearGradient(colors: [Ym.amber, Ym.amberDark]) : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: on ? Ym.navy : Ym.grey),
                const SizedBox(width: 6),
                Text(label,
                    style: Ym.t(13, color: on ? Ym.navy : Ym.grey, w: FontWeight.w800)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _adminShadow,
      ),
      child: Row(
        children: [
          tab(0, 'Compose', Icons.edit_note_rounded),
          tab(1, 'Sent (${_announcements.length})', Icons.history_rounded),
        ],
      ),
    );
  }

  Widget _stepCard({
    required int step,
    required String title,
    String? hint,
    required Widget child,
    int index = 0,
  }) {
    return YmFadeSlide(
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: _annCream,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _annLine),
          boxShadow: _adminShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Ym.amber, Ym.amberDark]),
                  ),
                  child: Text('$step',
                      style: Ym.t(14, color: Ym.navy, w: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Ym.h(16)),
                      if (hint != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(hint, style: Ym.t(12, color: Ym.grey)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _composeView() {
    final hasDraft =
        _titleCtrl.text.trim().isNotEmpty || _bodyCtrl.text.trim().isNotEmpty;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            children: [
              _stepCard(
                step: 1,
                index: 0,
                title: 'Who should get it?',
                hint: 'Choose how to pick the audience',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _targetTypePicker(),
                    const SizedBox(height: 18),
                    if (_targetType == 'role')
                      _buildRoleSelector()
                    else if (_targetType == 'bus')
                      _buildBusSelector()
                    else
                      _buildRouteSelector(),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Ym.amber.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.send_rounded,
                              size: 16, color: Ym.amberDark),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Goes to: $_audienceSummary',
                                style: Ym.t(12.5, w: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _stepCard(
                step: 2,
                index: 1,
                title: 'Write your message',
                hint: 'Keep it short and clear',
                child: Column(
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      maxLength: 80,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF0F1B4C),
                          fontWeight: FontWeight.w600),
                      decoration: _composerFieldDecoration(
                        label: 'Title',
                        hint: 'e.g. Route 4 delayed by 15 minutes',
                        icon: Icons.title_rounded,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bodyCtrl,
                      maxLength: 500,
                      maxLines: 5,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF0F1B4C)),
                      decoration: _composerFieldDecoration(
                        label: 'Message',
                        hint: 'Write the announcement details...',
                        icon: Icons.notes_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasDraft)
                _stepCard(
                  step: 3,
                  index: 2,
                  title: 'Preview',
                  hint: 'How it will look to the people who get it',
                  child: _previewCard(),
                ),
            ],
          ),
        ),
        _sendBar(),
      ],
    );
  }

  Widget _targetTypePicker() {
    Widget tile(String type, String label, String sub, IconData icon) {
      final on = _targetType == type;
      return Expanded(
        child: YmPressable(
          onTap: () => setState(() => _targetType = type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.white.withOpacity(0.55),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: on ? Ym.amberDark : _annLine, width: on ? 1.6 : 1),
              boxShadow: on
                  ? [
                      BoxShadow(
                          color: Ym.amber.withOpacity(0.30),
                          blurRadius: 14,
                          offset: const Offset(0, 6))
                    ]
                  : [],
            ),
            child: Column(
              children: [
                YmShortcutTile(icon: icon, size: 48),
                const SizedBox(height: 8),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ym.t(13, w: FontWeight.w800)),
                const SizedBox(height: 1),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ym.t(11, color: Ym.grey)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile('role', 'By role', 'Groups', Icons.groups_rounded),
        tile('bus', 'One bus', 'Its riders', Icons.directions_bus_rounded),
        tile('route', 'One route', 'Its riders', Icons.alt_route_rounded),
      ],
    );
  }

  Widget _previewCard() {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final target = _targetType == 'role'
        ? _targetRole
        : _targetType == 'bus'
            ? 'bus_${_selectedBusId ?? ''}'
            : 'route_${_selectedRouteId ?? ''}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _annLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const YmShortcutTile(icon: Icons.campaign_rounded, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.isEmpty ? 'Your title' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Ym.h(14.5)),
                const SizedBox(height: 4),
                Text(body.isEmpty ? 'Your message appears here' : body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[700], height: 1.45)),
                const SizedBox(height: 8),
                _InfoChip('To: ${_targetLabel(target)}', color: Ym.amberDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF9EE),
        border: Border(top: BorderSide(color: _annLine)),
      ),
      child: YmPressable(
        onTap: _isSending ? null : _sendAnnouncement,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Ym.amber, Ym.amberDark]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Ym.amberDark.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: _isSending
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Ym.navy),
                    ),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.send_rounded, size: 18, color: Ym.navy),
                      SizedBox(width: 10),
                      Text('Send Announcement',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Ym.navy)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  bool _matchesFilter(Map<String, dynamic> a, String f) {
    final t = (a['target_role'] ?? 'all').toString();
    switch (f) {
      case 'roles':
        return !t.startsWith('bus_') && !t.startsWith('route_');
      case 'bus':
        return t.startsWith('bus_');
      case 'route':
        return t.startsWith('route_');
      default:
        return true;
    }
  }

  Widget _filterPill(String key, String label) {
    final on = _filter == key;
    final count = _announcements.where((a) => _matchesFilter(a, key)).length;
    return YmPressable(
      onTap: () => setState(() => _filter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? null : Colors.white,
          gradient: on ? const LinearGradient(colors: [Ym.amber, Ym.amberDark]) : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? Ym.amberDark : _annLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: Ym.t(12.5, color: on ? Ym.navy : Ym.grey, w: FontWeight.w800)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: on ? Colors.white.withOpacity(0.6) : const Color(0xFFFFF1D2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: Ym.t(11, color: Ym.navy, w: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sentView() {
    final list = _announcements.where((a) => _matchesFilter(a, _filter)).toList();

    return RefreshIndicator(
      color: Ym.amber,
      onRefresh: _fetchAnnouncements,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 40),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterPill('all', 'All'),
                const SizedBox(width: 8),
                _filterPill('roles', 'Roles'),
                const SizedBox(width: 8),
                _filterPill('bus', 'Bus'),
                const SizedBox(width: 8),
                _filterPill('route', 'Route'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 50),
              child: Center(child: CircularProgressIndicator(color: Ym.amber)),
            )
          else if (list.isEmpty)
            SizedBox(
              height: 340,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _AdminEmpty(
                    icon: Icons.campaign_outlined,
                    title: 'No announcements here',
                    subtitle: 'Announcements you send will appear in this list.',
                  ),
                  YmButton(
                    label: 'Write an announcement',
                    icon: Icons.edit_note_rounded,
                    expanded: false,
                    onPressed: () => setState(() => _view = 0),
                  ),
                ],
              ),
            )
          else
            for (var index = 0; index < list.length; index++)
              _sentCard(list[index], index),
        ],
      ),
    );
  }

  Widget _sentCard(Map<String, dynamic> ann, int index) {
    final targetRole = (ann['target_role'] ?? 'all').toString();
    final isBusTarget = targetRole.startsWith('bus_');
    final isRouteTarget = targetRole.startsWith('route_');
    final chipIcon = isBusTarget
        ? Icons.directions_bus_rounded
        : isRouteTarget
            ? Icons.alt_route_rounded
            : _audienceIcon(targetRole);
    final body = (ann['body'] ?? '').toString();
    final open = _expanded.contains(ann['id']);
    final long = body.length > 110;

    return YmFadeSlide(
      index: index > 6 ? 6 : index,
      child: GestureDetector(
        onTap: long
            ? () => setState(() {
                  if (open) {
                    _expanded.remove(ann['id']);
                  } else {
                    _expanded.add(ann['id']);
                  }
                })
            : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _annCream,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _annLine),
            boxShadow: _adminShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  YmShortcutTile(icon: chipIcon, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ann['title'] ?? 'Announcement',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: Color(0xFF0F1B4C))),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _InfoChip('To: ${_targetLabel(targetRole)}',
                                color: Ym.amberDark),
                            _InfoChip(_ago(ann['created_at']?.toString()),
                                icon: Icons.access_time_rounded,
                                color: const Color(0xFF8892AA)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _deleteAnnouncement(ann['id']),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: _annLine),
              const SizedBox(height: 12),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: Text(body,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5),
                    maxLines: open ? null : 3,
                    overflow: open ? TextOverflow.visible : TextOverflow.ellipsis),
              ),
              if (long)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(open ? 'Show less' : 'Read more',
                      style: Ym.t(12, color: Ym.amberDark, w: FontWeight.w800)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    final roles = [
      ('all', 'Everyone', Icons.public_rounded),
      ('student', 'Students', Icons.school_rounded),
      ('faculty', 'Faculty', Icons.badge_rounded),
      ('driver', 'Drivers', Icons.directions_car_rounded),
      ('help_desk', 'Help Desk', Icons.support_agent_rounded),
      ('parent', 'Parents', Icons.family_restroom_rounded),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select audience', style: Ym.t(12, w: FontWeight.w700)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.9,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: roles.length,
          itemBuilder: (context, index) {
            final (roleValue, roleLabel, roleIcon) = roles[index];
            final isSelected = _targetRole == roleValue;
            return GestureDetector(
              onTap: () => setState(() => _targetRole = roleValue),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Ym.amber.withOpacity(0.22) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? Ym.amberDark : _annLine,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(roleIcon,
                        size: 17,
                        color: isSelected ? Ym.navy : const Color(0xFF8892AA)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        roleLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Ym.navy : const Color(0xFF4A5468),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded,
                          size: 16, color: Ym.amberDark),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _pickerBox({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _annLine),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: child,
      );

  Widget _pickedNote(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Ym.amber.withOpacity(0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 16, color: Ym.amberDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: Ym.t(12, color: Ym.navy, w: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _buildBusSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select bus', style: Ym.t(12, w: FontWeight.w700)),
        const SizedBox(height: 10),
        _pickerBox(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<dynamic>(
              value: _selectedBusId,
              hint: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Text('Choose a bus...', style: TextStyle(color: Color(0xFF8892AA), fontSize: 13)),
              ),
              isExpanded: true,
              icon: const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.expand_more_rounded, color: Color(0xFF8892AA))),
              items: widget.buses.map((bus) => DropdownMenuItem(
                value: bus['id'],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_bus_rounded, size: 16, color: Ym.amberDark),
                      const SizedBox(width: 10),
                      Text(bus['bus_number'] ?? 'Bus', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F1B4C))),
                    ],
                  ),
                ),
              )).toList(),
              onChanged: (val) => setState(() => _selectedBusId = val),
            ),
          ),
        ),
        if (_selectedBusId != null) ...[
          const SizedBox(height: 12),
          _pickedNote('Message will go to all students and faculty on this bus route'),
        ],
      ],
    );
  }

  Widget _buildRouteSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select route', style: Ym.t(12, w: FontWeight.w700)),
        const SizedBox(height: 10),
        _pickerBox(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<dynamic>(
              value: _selectedRouteId,
              hint: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Text('Choose a route...', style: TextStyle(color: Color(0xFF8892AA), fontSize: 13)),
              ),
              isExpanded: true,
              icon: const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.expand_more_rounded, color: Color(0xFF8892AA))),
              items: widget.routes.map((route) => DropdownMenuItem(
                value: route['id'],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.alt_route_rounded, size: 16, color: Ym.amberDark),
                      const SizedBox(width: 10),
                      Text(route['route_name'] ?? 'Route', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F1B4C))),
                    ],
                  ),
                ),
              )).toList(),
              onChanged: (val) => setState(() => _selectedRouteId = val),
            ),
          ),
        ),
        if (_selectedRouteId != null) ...[
          const SizedBox(height: 12),
          _pickedNote('Message will go to all students and faculty assigned to this route'),
        ],
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }
}

// ══════════════════════════════════════════════
// NAV ITEM
// ══════════════════════════════════════════════
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final Function(int) onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;
    return YmPressable(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: isActive
              ? const LinearGradient(colors: [Ym.amber, Ym.amberDark])
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? Ym.navy : Ym.grey, size: 22),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: isActive ? Ym.navy : Ym.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// HOME TAB
// ══════════════════════════════════════════════
class _HomeTab extends StatelessWidget {
  final String institutionName;
  final String institutionCity;
  final int totalStudents;
  final int totalBuses;
  final int totalRoutes;
  final int totalDrivers;
  final int helpdeskCount;
  final int tripsToday;
  final int tripsRunning;
  final int pendingCredentials;
  final bool isLoading;
  final RefreshCallback onRefresh;
  final List<Map<String, dynamic>> pendingRequests;
  final Function(Map<String, dynamic>) onApproveRequest;
  final Function(dynamic) onRejectRequest;
  final VoidCallback onBellTap;
  final VoidCallback onLogout;
  final List<Map<String, dynamic>> stagedExcelRoutes;
  final bool isProcessingExcel;
  final VoidCallback onImportExcel;
  final VoidCallback onSaveExcel;
  final Function(int) onRemoveStagedItem;
  final Function(int, String, String) onUpdateStagedItem;

  const _HomeTab({
    required this.institutionName,
    required this.institutionCity,
    required this.totalStudents,
    required this.totalBuses,
    required this.totalRoutes,
    required this.totalDrivers,
    required this.helpdeskCount,
    this.tripsToday = 0,
    this.tripsRunning = 0,
    required this.pendingCredentials,
    required this.isLoading,
    required this.onRefresh,
    required this.pendingRequests,
    required this.onApproveRequest,
    required this.onRejectRequest,
    required this.onBellTap,
    required this.onLogout,
    required this.stagedExcelRoutes,
    required this.isProcessingExcel,
    required this.onImportExcel,
    required this.onSaveExcel,
    required this.onRemoveStagedItem,
    required this.onUpdateStagedItem,
  });

  // The CSV upload instructions, then the file chooser (logic unchanged).
  void _showCsvDialog(BuildContext context) {
                        showDialog(
                          context: context,
                          builder: (context) => Dialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 48, height: 48,
                                        decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(14)),
                                        child: const Icon(Icons.upload_file_rounded, color: Color(0xFF059669), size: 24),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Upload Master CSV Sheet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0F1B4C))),
                                            SizedBox(height: 2),
                                            Text('Bulk import routes & stops', style: TextStyle(fontSize: 12, color: Color(0xFF8892AA))),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  const Text('YOUR FILE NEEDS 3 COLUMNS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF8892AA), letterSpacing: 0.6)),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE8EAF0)),
                                    ),
                                    child: Column(
                                      children: [
                                        _CsvColumnRow(letter: 'A', label: 'Route Name', color: const Color(0xFF3B5BFF)),
                                        const SizedBox(height: 10),
                                        _CsvColumnRow(letter: 'B', label: 'Stop Name', color: const Color(0xFF059669)),
                                        const SizedBox(height: 10),
                                        _CsvColumnRow(letter: 'C', label: 'Timing (HH:MM)', color: const Color(0xFFD97706)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEF2FF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.lightbulb_outline_rounded, size: 15, color: Color(0xFF3B5BFF)),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Example: Route 1, MG Road, 07:30:00',
                                            style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF3B5BFF)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            foregroundColor: const Color(0xFF6B7A99),
                                          ),
                                          child: const Text('Cancel'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        flex: 2,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF059669),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          onPressed: () {
                                            Navigator.pop(context); // Closes the pop-up dialog window safely
                                            onImportExcel(); // Runs your file upload system logic smoothly!
                                          },
                                          icon: const Icon(Icons.file_open_rounded, size: 18),
                                          label: const Text('Choose CSV File'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
  }

  void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Ym.amber, Ym.amberDark]),
            boxShadow: Ym.shadow(Ym.amberDark, 0.3),
          ),
          child: GestureDetector(
            onTap: () => showAccountSheet(context,
                roleLabel: 'Admin', onLogout: () async => onLogout()),
            child: const CircleAvatar(
              radius: 21,
              backgroundColor: Colors.white,
              child: Icon(Icons.admin_panel_settings_rounded,
                  color: Ym.amberDark, size: 24),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(children: [
                  TextSpan(text: 'YATRA ', style: Ym.h(16)),
                  TextSpan(text: 'MITRA', style: Ym.h(16, color: Ym.green)),
                ]),
              ),
              Text('Admin', style: Ym.t(11.5, color: Ym.grey, w: FontWeight.w600)),
            ],
          ),
        ),
        YmRoundButton(
            icon: Iconsax.notification,
            badge: pendingRequests.length,
            onTap: onBellTap),
        const SizedBox(width: 10),
        YmRoundButton(icon: Iconsax.logout, color: Ym.red, onTap: onLogout),
      ],
    );
  }

  Widget _hero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6E3), Color(0xFFFFE3AE)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Ym.amber.withOpacity(0.45), width: 1.2),
        boxShadow: Ym.shadow(Ym.amberDark, 0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YmPulse(color: Ym.green, size: 7),
              const SizedBox(width: 8),
              Text('SMART TRANSPORT MANAGEMENT',
                  style: Ym.t(10.5, color: Ym.amberDark, w: FontWeight.w800)
                      .copyWith(letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 12),
          Text(institutionName.isEmpty ? 'Loading...' : institutionName,
              style: Ym.h(22)),
          if (institutionCity.isNotEmpty) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 15, color: Ym.grey),
                const SizedBox(width: 4),
                Text(institutionCity, style: Ym.t(13, color: Ym.grey)),
              ],
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: Image.asset(
                'assets/images/admin_dashboard_illustration.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Ym.amber.withOpacity(0.18),
                  child: const Icon(Icons.directions_bus_rounded,
                      size: 44, color: Ym.amberDark),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(Widget tile, String label, VoidCallback onTap) => Expanded(
        child: YmPressable(
          onTap: onTap,
          child: Column(
            children: [
              tile,
              const SizedBox(height: 9),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: Ym.t(11.5, w: FontWeight.w700)),
            ],
          ),
        ),
      );

  Widget _quickActions(BuildContext context) {
    return YmCard(
      color: const Color(0xFFFFFBF2),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _action(
                  const YmShortcutTile(icon: Icons.mail_outline_rounded, color: Ym.blue),
                  'Inbox',
                  () => _open(context, const InboxScreen(isAdmin: true))),
              _action(
                  const YmShortcutTile(
                      icon: Icons.notifications_active_outlined, color: Ym.red),
                  'Alerts',
                  () => _open(context, const AdminAlertsScreen())),
              _action(
                  const YmShortcutTile(icon: Iconsax.bus, color: Ym.green),
                  'Buses',
                  () => _open(context, const AdminBusesScreen())),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _action(
                  const YmShortcutTile(
                      icon: Icons.account_balance_wallet_outlined,
                      color: Ym.amberDark),
                  'Fees & Years',
                  () => _open(context, const AdminFeesScreen())),
              _action(
                  isProcessingExcel
                      ? const YmShortcutTile(
                          icon: null,
                          color: Ym.purple,
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Ym.navy)))
                      : const YmShortcutTile(
                          icon: Icons.note_add_rounded, color: Ym.purple),
                  'CSV Upload',
                  () => _showCsvDialog(context)),
              _action(
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const YmShortcutTile(
                          icon: Icons.badge_outlined, color: Color(0xFF0EA5E9)),
                      if (pendingCredentials > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Color(0xFFE5A323),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white, width: 1.8),
                            ),
                            child: Text('$pendingCredentials',
                                style: Ym.t(10.5,
                                    color: Colors.white, w: FontWeight.w800)),
                          ),
                        ),
                    ],
                  ),
                  'Pending Credentials',
                  () => _open(context, const PendingCredentialsScreen())),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: Ym.amber,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            YmFadeSlide(index: 0, child: _header(context)),
            const SizedBox(height: 22),
            YmFadeSlide(
              index: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome to', style: Ym.t(15, color: Ym.grey)),
                  const SizedBox(height: 3),
                  Text('Admin Dashboard', style: Ym.h(30)),
                ],
              ),
            ),
            const SizedBox(height: 18),
              if (stagedExcelRoutes.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.zero,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFA7F3D0), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Data Import Staging', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF065F46))),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              onPressed: onSaveExcel,
                              icon: const Icon(Icons.sync_rounded, size: 16),
                              label: const Text('Save Changes'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: stagedExcelRoutes.length,
                            itemBuilder: (context, idx) {
                              final dataItem = stagedExcelRoutes[idx];
                              return ListTile(
                                dense: true,
                                title: Row(
                                  children: [
                                    Expanded(child: TextFormField(initialValue: dataItem['route_name'].toString(), decoration: const InputDecoration(labelText: 'Route Name', border: InputBorder.none), onChanged: (val) => onUpdateStagedItem(idx, 'route_name', val))),
                                    const SizedBox(width: 8),
                                    Expanded(child: TextFormField(initialValue: dataItem['stop_name'].toString(), decoration: const InputDecoration(labelText: 'Stop Name', border: InputBorder.none), onChanged: (val) => onUpdateStagedItem(idx, 'stop_name', val))),
                                  ],
                                ),
                                subtitle: TextFormField(initialValue: dataItem['timing'].toString(), decoration: const InputDecoration(labelText: 'Timing', border: InputBorder.none), onChanged: (val) => onUpdateStagedItem(idx, 'timing', val)),
                                trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => onRemoveStagedItem(idx)),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

            YmFadeSlide(index: 2, child: _hero()),
            const SizedBox(height: 26),
            YmFadeSlide(index: 3, child: _quickActions(context)),
            const SizedBox(height: 26),
            const YmFadeSlide(index: 4, child: YmSectionTitle('Overview')),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator(color: Ym.amber)),
              )
            else
              YmFadeSlide(
                index: 4,
                child: GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // fixed card height (not a ratio) so the cards never overflow
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent: 196,
                  ),
                  children: [
                    _StatCard(icon: Icons.people_rounded, title: 'Total Commuters', value: '$totalStudents', subtitle: 'Students & Faculties', badge: 'Active'),
                    _StatCard(icon: Icons.support_agent_rounded, title: 'Help Desk Accounts', value: '$helpdeskCount', subtitle: 'Active Help Desk', badge: 'Active'),
                    _StatCard(icon: Icons.directions_bus_rounded, title: 'Total Buses', value: '$totalBuses', subtitle: 'Active Buses', badge: 'On Route'),
                    _StatCard(icon: Icons.person_rounded, title: 'Total Drivers', value: '$totalDrivers', subtitle: 'Active Drivers', badge: 'Active'),
                    _StatCard(icon: Icons.route_rounded, title: 'Total Routes', value: '$totalRoutes', subtitle: 'Active Routes', badge: 'Synced'),
                    _StatCard(icon: Icons.bar_chart_rounded, title: 'Trips Today', value: '$tripsToday', subtitle: tripsRunning > 0 ? '$tripsRunning running now' : 'Completed Trips', badge: tripsRunning > 0 ? 'Live' : 'Active'),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            YmFadeSlide(
              index: 5,
              child: YmCard(
                onTap: () => _open(context, const AdminAttendanceScreen()),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const YmIconBadge(icon: Icons.fact_check_rounded, size: 46),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Attendance', style: Ym.h(14.5)),
                          const SizedBox(height: 2),
                          Text('Who boarded and who was absent, route by route',
                              style: Ym.t(11.5, color: Ym.grey)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Ym.amber, Ym.amberDark]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text('Open', style: Ym.t(12, w: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            YmFadeSlide(
              index: 6,
              child: YmCard(
                onTap: () => _open(context, const AdminReportsScreen()),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const YmIconBadge(icon: Icons.bar_chart_rounded, size: 46),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Monthly Reports', style: Ym.h(14.5)),
                          const SizedBox(height: 2),
                          Text('Trips, days run and issues for every route',
                              style: Ym.t(11.5, color: Ym.grey)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Ym.amber, Ym.amberDark]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text('Open', style: Ym.t(12, w: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 26),
            const YmFadeSlide(index: 6, child: YmSectionTitle('System Status')),
            YmFadeSlide(
              index: 6,
              child: YmCard(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _SystemStatusItem(icon: Icons.storage_rounded, label: 'Database', status: 'Connected'),
                    _SystemStatusItem(icon: Icons.location_on_rounded, label: 'GPS Service', status: 'Active'),
                    _SystemStatusItem(icon: Icons.notifications_active_rounded, label: 'Notification', status: 'Running'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// CSV COLUMN ROW (used in the CSV upload format dialog)
// ══════════════════════════════════════════════
class _CsvColumnRow extends StatelessWidget {
  final String letter;
  final String label;
  final Color color;

  const _CsvColumnRow({
    required this.letter,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26, height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Text(letter, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        ),
        const SizedBox(width: 12),
        Text('Column $letter', style: const TextStyle(fontSize: 10, color: Color(0xFF8892AA))),
        const SizedBox(width: 6),
        Text('•', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F1B4C))),
      ],
    );
  }
}

// ══════════════════════════════════════════════
// TOP ICON BUTTON (Complaints / CSV Upload / Pending Credentials / Notifications / Logout)
// ══════════════════════════════════════════════
class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badgeCount;
  final bool isLoading;
  final Color iconColor;

  const _TopIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
    this.isLoading = false,
    this.iconColor = const Color(0xFF0F1B4C),
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Center(
                    child: isLoading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(icon, color: iconColor, size: 20),
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -4, top: -4,
                    child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(color: Color(0xFFE24B4A), shape: BoxShape.circle),
                      child: Center(child: Text('$badgeCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: Color(0xFF6B7A99), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// SYSTEM STATUS ITEM
// ══════════════════════════════════════════════
class _SystemStatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String status;

  const _SystemStatusItem({
    required this.icon,
    required this.label,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        YmIconBadge(icon: icon, color: Ym.green, size: 44),
        const SizedBox(height: 8),
        Text(label, style: Ym.t(11, color: Ym.grey)),
        const SizedBox(height: 2),
        Text(status, style: Ym.t(12, color: Ym.green, w: FontWeight.w800)),
      ],
    );
  }
}

// ══════════════════════════════════════════════
// STAT CARD
// ══════════════════════════════════════════════
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final String badge;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return YmCard(
      color: const Color(0xFFFFFBF2),
      padding: const EdgeInsets.all(16),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              YmShortcutTile(icon: icon, size: 48),
              const Spacer(),
              YmChip(badge,
                  color: badge == 'Live' ? Ym.green : Ym.amberDark),
            ],
          ),
          const Spacer(),
          Text(value, style: Ym.h(30)),
          const SizedBox(height: 3),
          Text(title,
              maxLines: 2,
              style: Ym.t(13.5, w: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle,
              maxLines: 2,
              style: Ym.t(11.5, color: Ym.grey)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// BUS DETAILS TAB
// ══════════════════════════════════════════════
class _BusDetailsTab extends StatelessWidget {
  final List<Map<String, dynamic>> liveRoutes;
  final bool isLoading;
  final RefreshCallback onRefresh;
  final Function(Map<String, dynamic>) onEditRoute;

  const _BusDetailsTab({
    required this.liveRoutes,
    required this.isLoading,
    required this.onRefresh,
    required this.onEditRoute,
  });

  bool _hasLocation(dynamic stop) => stop['lat'] != null && stop['lng'] != null;

  @override
  Widget build(BuildContext context) {
    var totalStops = 0;
    var missing = 0;
    for (final r in liveRoutes) {
      final stops = (r['stops'] as List?) ?? [];
      totalStops += stops.length;
      missing += stops.where((s) => !_hasLocation(s)).length;
    }

    return SafeArea(
      child: Column(
        children: [
          _AdminHeader(
            title: 'Bus Details',
            subtitle: 'Routes, stops and map locations',
            icon: Icons.directions_bus_rounded,
            color: const Color(0xFF2563EB),
          ),
          if (!isLoading && liveRoutes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  _MiniStat(
                      value: '${liveRoutes.length}',
                      label: 'Routes',
                      icon: Icons.route_rounded,
                      color: const Color(0xFF7C3AED)),
                  const SizedBox(width: 10),
                  _MiniStat(
                      value: '$totalStops',
                      label: 'Stops',
                      icon: Icons.location_on_outlined,
                      color: const Color(0xFF2563EB)),
                  const SizedBox(width: 10),
                  _MiniStat(
                      value: '$missing',
                      label: 'No location',
                      icon: missing == 0
                          ? Icons.check_circle_outline_rounded
                          : Icons.wrong_location_outlined,
                      color: missing == 0 ? const Color(0xFF16A34A) : Colors.redAccent),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: isLoading
                  ? const YmSkeletonList(count: 4, height: 84)
                  : liveRoutes.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 80),
                            _AdminEmpty(
                              icon: Icons.route_rounded,
                              title: 'No routes defined yet',
                              subtitle: 'Upload a CSV from Home to add routes and stops.',
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          itemCount: liveRoutes.length,
                          itemBuilder: (context, index) {
                            final route = liveRoutes[index];
                            final stops = List<Map<String, dynamic>>.from(
                                (route['stops'] as List?) ?? []);
                            stops.sort((a, b) => (a['timing'] ?? '')
                                .toString()
                                .compareTo((b['timing'] ?? '').toString()));
                            final located = stops.where(_hasLocation).length;
                            final allLocated = stops.isNotEmpty && located == stops.length;

                            return YmFadeSlide(
                              index: index,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: _adminShadow,
                                ),
                                child: Theme(
                                  data: Theme.of(context)
                                      .copyWith(dividerColor: Colors.transparent),
                                  child: ExpansionTile(
                                    tilePadding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                                    iconColor: const Color(0xFF8892AA),
                                    leading: Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            const Color(0xFF2563EB).withOpacity(0.2),
                                            const Color(0xFF2563EB).withOpacity(0.07),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                      child: const Icon(Icons.directions_bus_rounded,
                                          color: Color(0xFF2563EB), size: 22),
                                    ),
                                    title: Text(route['route_name'] ?? 'Unnamed Route',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                            color: Color(0xFF0F1B4C))),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          _InfoChip('${stops.length} stops',
                                              icon: Icons.pin_drop_outlined,
                                              color: const Color(0xFF2563EB)),
                                          _InfoChip(
                                              allLocated
                                                  ? 'All located'
                                                  : '$located/${stops.length} located',
                                              icon: allLocated
                                                  ? Icons.check_circle_rounded
                                                  : Icons.wrong_location_outlined,
                                              color: allLocated
                                                  ? const Color(0xFF16A34A)
                                                  : const Color(0xFFD97706)),
                                        ],
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          color: Color(0xFF3B5BFF), size: 20),
                                      onPressed: () => onEditRoute(route),
                                    ),
                                    children: [
                                      for (var i = 0; i < stops.length; i++)
                                        _stopRow(i, stops[i], i == stops.length - 1),
                                      if (stops.isEmpty)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 4),
                                          child: Text('No stops on this route yet.',
                                              style: TextStyle(
                                                  fontSize: 12.5, color: Color(0xFF8892AA))),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopRow(int i, Map<String, dynamic> stop, bool last) {
    final raw = (stop['timing'] ?? '').toString();
    final time = raw.length >= 5 ? raw.substring(0, 5) : raw;
    final has = _hasLocation(stop);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: has ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                    shape: BoxShape.circle,
                  ),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: const Color(0xFFF0E2C8),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text((stop['stop_name'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F1B4C))),
                  ),
                  if (time.isNotEmpty) _InfoChip(time, icon: Icons.access_time_rounded),
                  const SizedBox(width: 6),
                  Icon(has ? Icons.location_on_rounded : Icons.location_off_outlined,
                      size: 18,
                      color: has ? const Color(0xFF16A34A) : const Color(0xFFB0B7C9)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
// PLACEHOLDER TAB
// ══════════════════════════════════════════════
class _PlaceholderTab extends StatelessWidget {
  final String title;
  const _PlaceholderTab({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('$title — Coming Soon'));
  }
}

// ══════════════════════════════════════════════
// SHARED LOOK (admin pages): same cream + navy + blue theme, just tidier
// ══════════════════════════════════════════════
const List<BoxShadow> _adminShadow = [
  BoxShadow(color: Color(0x120F1B4C), blurRadius: 18, offset: Offset(0, 6)),
];

class _AdminHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  final VoidCallback? onBack;

  const _AdminHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.color = Ym.amberDark,
    this.trailing,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack == null ? 20 : 8, 16, 20, 10),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: Color(0xFF0F1B4C)),
              onPressed: onBack,
            ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withOpacity(0.2), color.withOpacity(0.08)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F1B4C))),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF8892AA))),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = Ym.amberDark,
  });

  @override
  Widget build(BuildContext context) {
    return YmPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Ym.amber, color]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 14,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Ym.navy, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Ym.navy, fontWeight: FontWeight.w800, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _AdminEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _AdminEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color = Ym.amberDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withOpacity(0.18), color.withOpacity(0.06)],
                ),
              ),
              child: Icon(icon, color: color, size: 38),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F1B4C))),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF8892AA), height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _MiniStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: _adminShadow,
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF8892AA))),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;

  const _InfoChip(this.text, {this.icon, this.color = Ym.amberDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12.5, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _IconRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final dynamic value;

  const _IconRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final display =
        (value == null || value.toString().trim().isEmpty) ? '—' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF8892AA)),
          const SizedBox(width: 10),
          SizedBox(
              width: 86,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA)))),
          Expanded(
            child: Text(display,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF0F1B4C),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;

  const _Avatar({required this.name, required this.color, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withOpacity(0.7)],
        ),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Text(initial,
          style: TextStyle(
              color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w800)),
    );
  }
}

/// What an upload would do, worked out BEFORE anything is changed, so the admin
/// sees it first and the result matches exactly.
class _ImportPlan {
  final List<String> routesAdd = [];
  final List<String> routesSkip = [];
  final List<String> routesUpdate = [];
  final List<String> routesRemove = [];
  final List<String> routesKept = [];
  int stopsAdd = 0;
  int stopsUpdate = 0;
  int stopsRemove = 0;
  int stopsKept = 0;
}