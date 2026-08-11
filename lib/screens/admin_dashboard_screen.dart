import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csv/csv.dart';
import 'package:latlong2/latlong.dart';
import 'pending_credentials_screen.dart';
import 'role_selection_screen.dart';
import 'map_picker_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web/web.dart' as web;

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
          .select('id, bus_number, route_id')
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

        setState(() {
          _totalStudents = (students as List).length;
          _totalBuses = (buses as List).length;
          _totalRoutes = (routes as List).length;
          _helpdeskCount = (helpdesks as List).length;
          _pendingCredentials = (pending as List).length;
        });
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
      final web.HTMLInputElement uploadInput =
          web.document.createElement('input') as web.HTMLInputElement;
      uploadInput.type = 'file';
      uploadInput.accept = '.csv';
      uploadInput.click();

      uploadInput.onChange.listen((web.Event e) {
        final files = uploadInput.files;
        if (files != null && files.length > 0) {
          final file = files.item(0);
          if (file != null) {
            final web.FileReader reader = web.FileReader();
            reader.readAsText(file);
            reader.onLoadEnd.listen((web.Event loadEvent) {
              final csvString = reader.result as String;
              final List<List<dynamic>> csvTable =
                  const CsvToListConverter().convert(csvString);
              List<Map<String, dynamic>> temporarilyLoaded = [];
              for (int i = 1; i < csvTable.length; i++) {
                final row = csvTable[i];
                if (row.length >= 2) {
                  final routeVal =
                      row[0] != null ? row[0].toString().trim() : '';
                  final stopVal =
                      row[1] != null ? row[1].toString().trim() : '';
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
              setState(() => _stagedExcelRoutes = temporarilyLoaded);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      'Read: ${_stagedExcelRoutes.length} entries queued.'),
                  backgroundColor: Colors.green,
                ));
              }
            });
          }
        }
      });
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
      setState(() => _isProcessingExcel = false);
    }
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

      Map<String, List<Map<String, dynamic>>> groupedExcelRoutes = {};
      for (var item in _stagedExcelRoutes) {
        final rName = item['route_name'].toString().trim();
        if (rName.isEmpty) continue;
        groupedExcelRoutes.putIfAbsent(rName, () => []).add(item);
      }

      final dbRoutes = await _supabase
          .from('routes')
          .select('id, route_name')
          .eq('institution_id', institutionId);
      List<Map<String, dynamic>> currentDbRoutes =
          List<Map<String, dynamic>>.from(dbRoutes);

      for (var dbRoute in currentDbRoutes) {
        if (!groupedExcelRoutes.containsKey(dbRoute['route_name'])) {
          await _supabase.from('routes').delete().eq('id', dbRoute['id']);
        }
      }

      List<Map<String, dynamic>> allStopsToInsert = [];
      for (var entry in groupedExcelRoutes.entries) {
        final routeName = entry.key;
        final matchingStops = entry.value;
        var existingRoute = await _supabase
            .from('routes')
            .select('id')
            .eq('institution_id', institutionId)
            .eq('route_name', routeName)
            .maybeSingle();

        dynamic targetRouteId;
        if (existingRoute != null) {
          targetRouteId = existingRoute['id'];
          await _supabase.from('stops').delete().eq('route_id', targetRouteId);
        } else {
          final newRoute = await _supabase.from('routes').insert({
            'institution_id': institutionId,
            'route_name': routeName,
          }).select('id').single();
          targetRouteId = newRoute['id'];
        }

        final finalRouteId = (int.tryParse(targetRouteId.toString()) != null)
            ? int.parse(targetRouteId.toString())
            : targetRouteId;

        for (var stop in matchingStops) {
          final sName = stop['stop_name'].toString().trim();
          if (sName.isEmpty) continue;
          double? latVal;
          double? lngVal;
          if ((stop['lat'] ?? '').toString().isNotEmpty) {
            latVal = double.tryParse(stop['lat'].toString());
          }
          if ((stop['lng'] ?? '').toString().isNotEmpty) {
            lngVal = double.tryParse(stop['lng'].toString());
          }
          allStopsToInsert.add({
            'route_id': finalRouteId,
            'stop_name': sName,
            'timing': stop['timing'].toString().trim(),
            'lat': latVal,
            'lng': lngVal,
          });
        }
      }

      if (allStopsToInsert.isNotEmpty) {
        await _supabase.from('stops').insert(allStopsToInsert);
      }

      setState(() => _stagedExcelRoutes.clear());
      await _loadDashboardData();
      await _fetchRouteRequests();
      await _fetchLiveRoutesAndStops();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Database mirrored successfully!'),
              backgroundColor: Colors.green),
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
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'))
            ],
          ),
        );
      }
    } finally {
      setState(() => _isLoadingStats = false);
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B5BFF)),
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
              child: const Text('Confirm', style: TextStyle(color: Colors.white)),
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B5BFF)),
                onPressed: () async {
                  await _updateRouteName(routeId, routeNameController.text);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('Save', style: TextStyle(color: Colors.white)),
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
        backgroundColor: const Color(0xFFFFFBF0),
        body: IndexedStack(
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
            const _PlaceholderTab(title: 'Drivers'),
            _AnnouncementsTab(
              supabase: _supabase,
              institutionId: _institutionId,
              buses: _buses,
              routes: _availableRoutes,
            ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, -4))],
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
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
                backgroundColor: const Color(0xFF3B5BFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Create Account', style: TextStyle(color: Colors.white)),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B5BFF)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!', style: TextStyle(color: Colors.white)),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B5BFF)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset & Email', style: TextStyle(color: Colors.white)),
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
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Help Desk',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
                      Text('Manage help desk accounts',
                          style: TextStyle(fontSize: 13, color: Color(0xFF8892AA))),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _showAddDialog,
                    icon: const Icon(Icons.add, size: 16, color: Colors.white),
                    label: const Text('Add', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B5BFF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _helpdesks.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.support_agent_rounded, size: 48, color: Color(0xFF8892AA)),
                              SizedBox(height: 12),
                              Text('No help desk accounts yet',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F1B4C))),
                              SizedBox(height: 4),
                              Text('Tap Add to create one', style: TextStyle(color: Color(0xFF8892AA))),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchHelpdesks,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _helpdesks.length,
                            itemBuilder: (context, index) {
                              final hd = _helpdesks[index];
                              final isActive = hd['is_active'] ?? true;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42, height: 42,
                                      decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(10)),
                                      child: const Icon(Icons.support_agent_rounded, color: Color(0xFF3B5BFF), size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(hd['name'] ?? 'Unknown',
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F1B4C))),
                                          Text(hd['email'] ?? '',
                                              style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA))),
                                          if (hd['phone'] != null && hd['phone'].toString().isNotEmpty)
                                            Text(hd['phone'], style: const TextStyle(fontSize: 11, color: Color(0xFF8892AA))),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        isActive ? 'Active' : 'Inactive',
                                        style: TextStyle(
                                          fontSize: 10, fontWeight: FontWeight.w700,
                                          color: isActive ? const Color(0xFF16A34A) : Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF8892AA), size: 20),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                                isActive ? Icons.block_rounded : Icons.check_circle_rounded,
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
                                              Icon(Icons.lock_reset_rounded, color: Color(0xFF3B5BFF), size: 18),
                                              SizedBox(width: 10),
                                              Text('Reset & Email Password'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_rounded, color: Colors.redAccent, size: 18),
                                              SizedBox(width: 10),
                                              Text('Delete', style: TextStyle(color: Colors.redAccent)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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
              'department, boarding_point, route_id, routes(route_name)')
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Commuters',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
            const SizedBox(height: 4),
            const Text('View students and faculty grouped by route',
                style: TextStyle(fontSize: 13, color: Color(0xFF8892AA))),
            const SizedBox(height: 24),
            _CommuterOptionCard(
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
            const SizedBox(height: 14),
            _CommuterOptionCard(
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
          ],
        ),
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

    return SafeArea(
      child: Column(
        children: [
          _CommutersHeader(
            title: isStudent ? 'Students by Route' : 'Faculty by Route',
            onBack: () => setState(() => _view = _CommutersView.menu),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : routeNames.isEmpty
                    ? Center(
                        child: Text(
                          isStudent ? 'No students with credentials yet.' : 'No faculty with credentials yet.',
                          style: const TextStyle(color: Color(0xFF8892AA)),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: isStudent ? _fetchStudents : _fetchFaculty,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                          itemCount: routeNames.length,
                          itemBuilder: (context, index) {
                            final routeName = routeNames[index];
                            final list = grouped[routeName]!;
                            final isUnassigned = routeName == 'Unassigned';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE8EAF0), width: 0.5),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                leading: Container(
                                  width: 42, height: 42,
                                  decoration: BoxDecoration(
                                    color: isUnassigned ? const Color(0xFFFEE2E2) : const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.route_rounded,
                                    color: isUnassigned ? Colors.redAccent : const Color(0xFF3B5BFF),
                                    size: 20,
                                  ),
                                ),
                                title: Text(routeName,
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F1B4C))),
                                subtitle: Text('${list.length} ${isStudent ? "student(s)" : "faculty member(s)"}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA))),
                                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF8892AA)),
                                onTap: () {
                                  setState(() {
                                    _selectedRouteName = routeName;
                                    _view = isStudent ? _CommutersView.studentList : _CommutersView.facultyList;
                                  });
                                },
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

  Widget _buildPersonList({required bool isStudent}) {
    final items = isStudent ? _students : _faculty;
    final grouped = _groupByRoute(items);
    final routeName = _selectedRouteName ?? 'Unassigned';
    final list = grouped[routeName] ?? [];

    return SafeArea(
      child: Column(
        children: [
          _CommutersHeader(
            title: routeName,
            onBack: () => setState(
                () => _view = isStudent ? _CommutersView.studentRoutes : _CommutersView.facultyRoutes),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('No records found.', style: TextStyle(color: Color(0xFF8892AA))))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final person = list[index];
                      return isStudent
                          ? _StudentDetailCard(student: person)
                          : _FacultyDetailCard(faculty: person);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CommutersHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _CommutersHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF0F1B4C)),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C)),
              overflow: TextOverflow.ellipsis,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EAF0), width: 0.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF8892AA)),
          ],
        ),
      ),
    );
  }
}

class _StudentDetailCard extends StatelessWidget {
  final Map<String, dynamic> student;
  const _StudentDetailCard({required this.student});

  @override
  Widget build(BuildContext context) {
    final feeStatus = (student['fee_status'] ?? 'unpaid').toString();
    final feeColor = feeStatus == 'paid'
        ? const Color(0xFF16A34A)
        : feeStatus == 'partial'
            ? const Color(0xFFD97706)
            : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EAF0), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.person_rounded, color: Color(0xFF7C3AED), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(student['student_name'] ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF0F1B4C))),
                    Text(student['enrollment_no'] ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: feeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(feeStatus.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: feeColor)),
              ),
            ],
          ),
          const Divider(height: 24),
          _InfoRow(label: 'Department', value: student['department']),
          _InfoRow(label: 'Year', value: student['year']),
          _InfoRow(label: 'Email', value: student['student_email']),
          _InfoRow(label: 'Phone', value: student['student_phone']),
          _InfoRow(label: 'Boarding Point', value: student['boarding_point']),
          _InfoRow(label: 'Admission Date', value: student['admission_date']),
          _InfoRow(label: 'Pass Expiry', value: student['pass_expiry']),
          const SizedBox(height: 8),
          const Text('Parent / Guardian',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF8892AA), letterSpacing: 0.4)),
          const SizedBox(height: 6),
          _InfoRow(label: 'Name', value: student['parent_name']),
          _InfoRow(label: 'Relation', value: student['parent_relation']),
          _InfoRow(label: 'Email', value: student['parent_email']),
          _InfoRow(label: 'Phone', value: student['parent_phone']),
        ],
      ),
    );
  }
}

class _FacultyDetailCard extends StatelessWidget {
  final Map<String, dynamic> faculty;
  const _FacultyDetailCard({required this.faculty});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EAF0), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.badge_rounded, color: Color(0xFF2563EB), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(faculty['faculty_name'] ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF0F1B4C))),
                    Text(faculty['employee_id'] ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA))),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _InfoRow(label: 'Department', value: faculty['department']),
          _InfoRow(label: 'Email', value: faculty['faculty_email']),
          _InfoRow(label: 'Phone', value: faculty['faculty_phone']),
          _InfoRow(label: 'Boarding Point', value: faculty['boarding_point']),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final dynamic value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final display = (value == null || value.toString().trim().isEmpty) ? '—' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 112, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA)))),
          Expanded(child: Text(display, style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F1B4C), fontWeight: FontWeight.w500))),
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

  static const List<Map<String, dynamic>> _audiences = [
    {'value': 'all', 'label': 'Everyone', 'icon': Icons.campaign_rounded},
    {'value': 'student', 'label': 'Students', 'icon': Icons.school_rounded},
    {'value': 'faculty', 'label': 'Faculty', 'icon': Icons.badge_rounded},
    {'value': 'driver', 'label': 'Drivers', 'icon': Icons.directions_bus_rounded},
    {'value': 'help_desk', 'label': 'Help Desk', 'icon': Icons.support_agent_rounded},
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
      prefixIcon: Icon(icon, size: 18, color: const Color(0xFF8892AA)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6B7A99)),
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE8EAF0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF3B5BFF), width: 1.5),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFFBF0),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Announcements',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
            const SizedBox(height: 4),
            const Text('Broadcast updates to everyone on campus transport',
                style: TextStyle(fontSize: 13, color: Color(0xFF8892AA))),
            const SizedBox(height: 20),

            // ===== COMPOSE SECTION =====
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE8EAF0), width: 0.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _iconBadge(Icons.campaign_rounded, const Color(0xFFFEF3C7), const Color(0xFFD97706)),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Create Announcement',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
                            SizedBox(height: 2),
                            Text('Compose a broadcast and choose who sees it',
                                style: TextStyle(fontSize: 12, color: Color(0xFF8892AA))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _titleCtrl,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF0F1B4C), fontWeight: FontWeight.w600),
                    decoration: _composerFieldDecoration(
                      label: 'Title',
                      hint: 'e.g. Route 4 delayed by 15 minutes',
                      icon: Icons.title_rounded,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _bodyCtrl,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF0F1B4C)),
                    maxLines: 4,
                    decoration: _composerFieldDecoration(
                      label: 'Message',
                      hint: 'Write the announcement details...',
                      icon: Icons.notes_rounded,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('SEND TO', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF8892AA), letterSpacing: 0.6)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE8EAF0)),
                    ),
                    child: Row(
                      children: [
                        _buildTargetTypeButton('role', 'Role', Icons.groups_rounded),
                        _buildTargetTypeButton('bus', 'Bus', Icons.directions_bus_rounded),
                        _buildTargetTypeButton('route', 'Route', Icons.alt_route_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_targetType == 'role') ...[
                    _buildRoleSelector(),
                  ] else if (_targetType == 'bus') ...[
                    _buildBusSelector(),
                  ] else if (_targetType == 'route') ...[
                    _buildRouteSelector(),
                  ],
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0xFF3B5BFF), Color(0xFF6B8CFF)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3B5BFF).withOpacity(0.28),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _isSending ? null : _sendAnnouncement,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: _isSending
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.send_rounded, size: 18, color: Colors.white),
                                      SizedBox(width: 10),
                                      Text(
                                        'Send Announcement',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
            Row(
              children: [
                const Expanded(
                  child: Text('Recent Announcements',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
                ),
                if (_announcements.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${_announcements.length}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3B5BFF))),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_announcements.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE8EAF0), width: 0.5),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.campaign_outlined, size: 44, color: Color(0xFF8892AA)),
                    SizedBox(height: 12),
                    Text('No announcements yet',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F1B4C))),
                    SizedBox(height: 4),
                    Text('Sent announcements will show up here', style: TextStyle(color: Color(0xFF8892AA), fontSize: 12)),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _announcements.length,
                itemBuilder: (context, index) {
                  final ann = _announcements[index];
                  final targetRole = (ann['target_role'] ?? 'all').toString();
                  final isBusTarget = targetRole.startsWith('bus_');
                  final isRouteTarget = targetRole.startsWith('route_');
                  final chipColor = isBusTarget
                      ? const Color(0xFF2563EB)
                      : isRouteTarget
                          ? const Color(0xFF7C3AED)
                          : _audienceColor(targetRole);
                  final chipIcon = isBusTarget
                      ? Icons.directions_bus_rounded
                      : isRouteTarget
                          ? Icons.alt_route_rounded
                          : _audienceIcon(targetRole);
                  final chipLabel = isBusTarget
                      ? 'Bus'
                      : isRouteTarget
                          ? 'Route'
                          : _audienceLabel(targetRole);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE8EAF0), width: 0.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _iconBadge(chipIcon, chipColor.withOpacity(0.12), chipColor, size: 38, iconSize: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ann['title'] ?? 'Announcement',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Color(0xFF0F1B4C)),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: chipColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      chipLabel,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: chipColor),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _deleteAnnouncement(ann['id']),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 19),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          ann['body'] ?? '',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded, size: 12, color: Colors.grey[400]),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(ann['created_at']),
                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetTypeButton(String type, String label, IconData icon) {
    final isActive = _targetType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _targetType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isActive
                ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: isActive ? const Color(0xFF3B5BFF) : const Color(0xFF8892AA)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isActive ? const Color(0xFF3B5BFF) : const Color(0xFF8892AA),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    final roles = [
      ('all', 'Everyone', Icons.public_rounded, const Color(0xFF3B5BFF)),
      ('student', 'Students', Icons.school_rounded, const Color(0xFF7C3AED)),
      ('faculty', 'Faculty', Icons.badge_rounded, const Color(0xFF2563EB)),
      ('driver', 'Drivers', Icons.directions_car_rounded, const Color(0xFFD97706)),
      ('help_desk', 'Help Desk', Icons.support_agent_rounded, const Color(0xFF059669)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select audience', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF0F1B4C))),
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
            final (roleValue, roleLabel, roleIcon, roleColor) = roles[index];
            final isSelected = _targetRole == roleValue;
            return GestureDetector(
              onTap: () => setState(() => _targetRole = roleValue),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isSelected ? roleColor.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: isSelected ? roleColor : const Color(0xFFE8EAF0),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(roleIcon, size: 16, color: isSelected ? roleColor : const Color(0xFF8892AA)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        roleLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isSelected ? roleColor : const Color(0xFF4A5468),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (isSelected) Icon(Icons.check_circle_rounded, size: 15, color: roleColor),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBusSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select bus', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF0F1B4C))),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EAF0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
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
                      const Icon(Icons.directions_bus_rounded, size: 16, color: Color(0xFF2563EB)),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF3B5BFF).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: const [
                Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF3B5BFF)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Message will go to all students and faculty on this bus route',
                    style: TextStyle(fontSize: 12, color: Color(0xFF3B5BFF)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRouteSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select route', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF0F1B4C))),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EAF0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
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
                      const Icon(Icons.alt_route_rounded, size: 16, color: Color(0xFF7C3AED)),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF3B5BFF).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: const [
                Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF3B5BFF)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Message will go to all students and faculty assigned to this route',
                    style: TextStyle(fontSize: 12, color: Color(0xFF3B5BFF)),
                  ),
                ),
              ],
            ),
          ),
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
    return GestureDetector(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF3B5BFF).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? const Color(0xFF3B5BFF) : const Color(0xFF8892AA), size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? const Color(0xFF3B5BFF) : const Color(0xFF8892AA)),
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _TopIconButton(
                      icon: Icons.mail_outline_rounded,
                      label: 'Complaints',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Complaints screen — Coming Soon')),
                        );
                      },
                    ),
                    _TopIconButton(
                      icon: Icons.note_add_rounded,
                      label: 'CSV Upload',
                      isLoading: isProcessingExcel,
                      onTap: () {
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
                      },
                    ),
                    _TopIconButton(
                      icon: Icons.badge_outlined,
                      label: 'Pending\nCredentials',
                      badgeCount: pendingCredentials,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PendingCredentialsScreen())),
                    ),
                    _TopIconButton(
                      icon: Icons.notifications_outlined,
                      label: 'Notifications',
                      badgeCount: pendingRequests.length,
                      onTap: onBellTap,
                    ),
                    _TopIconButton(
                      icon: Icons.logout_rounded,
                      label: 'Logout',
                      iconColor: Colors.redAccent,
                      onTap: onLogout,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Welcome to', style: TextStyle(fontSize: 16, color: Color(0xFF8892AA))),
                    Text('Admin Dashboard 👋', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(height: 16),
              if (stagedExcelRoutes.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  // CHANGED: added bottom padding (was 0) so the image panel
                  // below no longer sits flush against the card's bottom edge.
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF3DC),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFF5E6BF), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10, height: 10,
                            decoration: const BoxDecoration(color: Color(0xFF3B5BFF), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                              children: [
                                TextSpan(text: 'YATRA ', style: TextStyle(color: Color(0xFF0F1B4C))),
                                TextSpan(text: 'MITRA', style: TextStyle(color: Color(0xFF16A34A))),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        institutionName.isEmpty ? 'Loading...' : institutionName,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C)),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF8892AA)),
                          const SizedBox(width: 4),
                          Text(institutionCity, style: const TextStyle(fontSize: 13, color: Color(0xFF8892AA))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Smart college transport management system for a safer journey.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF6B7A99), height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      // Cropped to the top portion of the illustration (through
                      // the chair) rather than the full image, so the bottom
                      // "ADMIN DASHBOARD" text/dots from the source art don't show.
                      // CHANGED: rounded on all sides (was bottom-only) and given
                      // a small top margin now that it's not flush to the card
                      // bottom; height reduced from 380 -> 200 so the panel reads
                      // as a compact rectangle instead of a tall, elongated strip.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          margin: const EdgeInsets.only(top: 12),
                          width: double.infinity,
                          height: 200,
                          child: Image.asset(
                            'assets/images/admin_dashboard_illustration.png',
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.1,
                        children: [
                          _StatCard(icon: Icons.people_rounded, iconBg: const Color(0xFFEDE9FE), iconColor: const Color(0xFF7C3AED), title: 'Total Commuters', value: '$totalStudents', subtitle: 'Students & Faculties', badge: 'Active', badgeColor: const Color(0xFF059669)),
                          _StatCard(icon: Icons.support_agent_rounded, iconBg: const Color(0xFFD1FAE5), iconColor: const Color(0xFF059669), title: 'Help Desk Accounts', value: '$helpdeskCount', subtitle: 'Active Help Desk', badge: 'Active', badgeColor: const Color(0xFF059669)),
                          _StatCard(icon: Icons.directions_bus_rounded, iconBg: const Color(0xFFDBEAFE), iconColor: const Color(0xFF2563EB), title: 'Total Buses', value: '$totalBuses', subtitle: 'Active Buses', badge: 'On Route', badgeColor: const Color(0xFF2563EB)),
                          _StatCard(icon: Icons.person_rounded, iconBg: const Color(0xFFFEF3C7), iconColor: const Color(0xFFD97706), title: 'Total Drivers', value: '$totalDrivers', subtitle: 'Active Drivers', badge: 'Active', badgeColor: const Color(0xFFD97706)),
                          _StatCard(icon: Icons.route_rounded, iconBg: const Color(0xFFEDE9FE), iconColor: const Color(0xFF7C3AED), title: 'Total Routes', value: '$totalRoutes', subtitle: 'Active Routes', badge: 'Synced', badgeColor: const Color(0xFF7C3AED)),
                          _StatCard(icon: Icons.bar_chart_rounded, iconBg: const Color(0xFFD1FAE5), iconColor: const Color(0xFF059669), title: 'Trips Today', value: '0', subtitle: 'Completed Trips', badge: 'Active', badgeColor: const Color(0xFF059669)),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE8EAF0), width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.insights_rounded, color: Color(0xFFD97706), size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bus Insights & Health', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
                            SizedBox(height: 2),
                            Text('Live tracking, performance & health updates', style: TextStyle(fontSize: 11, color: Color(0xFF8892AA))),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFEDD5),
                          foregroundColor: const Color(0xFFD97706),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Bus Insights & Health — Coming Soon')),
                          );
                        },
                        child: const Text('View Dashboard →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('System Status', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE8EAF0), width: 0.5),
                  ),
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
              const SizedBox(height: 32),
            ],
          ),
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
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: const Color(0xFFD1FAE5), shape: BoxShape.circle),
          child: Icon(icon, color: const Color(0xFF059669), size: 18),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF8892AA))),
        const SizedBox(height: 2),
        Text(status, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
      ],
    );
  }
}

// ══════════════════════════════════════════════
// STAT CARD
// ══════════════════════════════════════════════
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String value;
  final String subtitle;
  final String badge;
  final Color badgeColor;

  const _StatCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EAF0), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle), child: Icon(icon, color: iconColor, size: 22)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF8892AA), fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF8892AA)), overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: badgeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(badge, style: TextStyle(fontSize: 10, color: badgeColor, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : liveRoutes.isEmpty
                ? ListView(children: const [SizedBox(height: 120), Center(child: Text('No routes defined yet.'))])
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: liveRoutes.length,
                    itemBuilder: (context, index) {
                      final route = liveRoutes[index];
                      final stops = route['stops'] as List? ?? [];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ExpansionTile(
                          title: Text(route['route_name'] ?? 'Unnamed Route', style: const TextStyle(fontWeight: FontWeight.bold)),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Color(0xFF3B5BFF), size: 20),
                            onPressed: () => onEditRoute(route),
                          ),
                          children: stops.map<Widget>((stop) {
                            String timeDisplay = '';
                            if (stop['timing'] != null) {
                              final rawTime = stop['timing'].toString();
                              timeDisplay = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
                            }
                            final hasLocation = stop['lat'] != null && stop['lng'] != null;
                            return ListTile(
                              leading: Icon(
                                Icons.location_on_rounded,
                                color: hasLocation ? Colors.green : Colors.blueAccent,
                              ),
                              title: Text(stop['stop_name'] ?? ''),
                              trailing: Text(timeDisplay, style: const TextStyle(fontFamily: 'monospace')),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
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