import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import 'dart:math';
import 'pending_credentials_screen.dart';

// Modern unified Web Compilation API
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

  String _institutionName = '';
  String _institutionCity = '';
  int _totalStudents = 0;
  int _totalBuses = 0;
  int _totalRoutes = 0;
  int _totalDrivers = 0;
  int _helpdeskCount = 0;
  int _pendingCredentials = 0;
  bool _isLoadingStats = true;

  List<Map<String, String>> _stagedExcelRoutes = [];
  bool _isProcessingExcel = false;
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _availableRoutes = [];

  // Track active routes and stops live for display panels
  List<Map<String, dynamic>> _liveDatabaseRoutesWithStops = [];
  bool _isLoadingLiveRoutes = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _fetchRouteRequests();
    _fetchLiveRoutesAndStops();
  }

  Future<void> _fetchRouteRequests() async {
    try {
      final adminId = _supabase.auth.currentUser?.id;
      if (adminId == null) {
        debugPrint('No authenticated admin found.');
        return;
      }

      final institution = await _supabase
          .from('institutions')
          .select('id')
          .eq('admin_id', adminId)
          .maybeSingle();

      if (institution == null) {
        debugPrint('No institution found for this admin.');
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
          .select('id, requested_boarding_point, created_at, status, requested_by, institution_id')
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
      debugPrint('Supabase error fetching route requests: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load route requests: ${e.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Unexpected error fetching route requests: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong loading route requests.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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
            .select('id, route_name, stops(id, stop_name, timing)')
            .eq('institution_id', institutionId)
            .order('route_name', ascending: true);

        setState(() {
          _liveDatabaseRoutesWithStops = List<Map<String, dynamic>>.from(routesResponse);
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
        final institutionId = institution['id'];

        final students = await _supabase.from('students').select('id').eq('institution_id', institutionId);
        final buses = await _supabase.from('buses').select('id').eq('institution_id', institutionId);
        final routes = await _supabase.from('routes').select('id').eq('institution_id', institutionId);
        final helpdesks = await _supabase.from('helpdesk_accounts').select('id').eq('institution_id', institutionId);
        final pending = await _supabase.from('students').select('id').eq('institution_id', institutionId).eq('credential_generated', false);

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

  // Native Web File Upload bypassing USB blocks using package:web
  Future<void> _importExcelFile() async {
    setState(() => _isProcessingExcel = true);
    try {
      final web.HTMLInputElement uploadInput = web.document.createElement('input') as web.HTMLInputElement;
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
              final List<List<dynamic>> csvTable = const CsvToListConverter().convert(csvString);
              List<Map<String, String>> temporarilyLoaded = [];

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
              setState(() {
                _stagedExcelRoutes = temporarilyLoaded;
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Master Sheet Read: ${_stagedExcelRoutes.length} entries queued.'),
                    backgroundColor: Colors.green,
                  ),
                );
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
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('File Import Failure'),
              ],
            ),
            content: Text('Error parsing CSV file: $e'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
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
      final institution = await _supabase.from('institutions').select('id').eq('admin_id', adminId).single();
      final institutionId = institution['id'];

      Map<String, List<Map<String, String>>> groupedExcelRoutes = {};
      for (var item in _stagedExcelRoutes) {
        final rName = item['route_name'].toString().trim();
        if (rName.isEmpty) continue;
        groupedExcelRoutes.putIfAbsent(rName, () => []).add(item);
      }

      final dbRoutes = await _supabase.from('routes').select('id, route_name').eq('institution_id', institutionId);
      List<Map<String, dynamic>> currentDbRoutes = List<Map<String, dynamic>>.from(dbRoutes);

      for (var dbRoute in currentDbRoutes) {
        final dbRouteName = dbRoute['route_name'];
        if (!groupedExcelRoutes.containsKey(dbRouteName)) {
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
          allStopsToInsert.add({
            'route_id': finalRouteId,
            'stop_name': sName,
            'timing': stop['timing'].toString().trim(),
          });
        }
      }

      if (allStopsToInsert.isNotEmpty) {
        await _supabase.from('stops').insert(allStopsToInsert);
      }

      setState(() {
        _stagedExcelRoutes.clear();
      });

      await _loadDashboardData();
      await _fetchRouteRequests();
      await _fetchLiveRoutesAndStops();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database mirrored successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Database Sync Failure'),
            content: Text(e.toString()),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
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
              const Text('Assign this approved point to a route:', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                hint: const Text('Select target route'),
                value: selectedRouteId,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFFAFBFF),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _availableRoutes.map((route) {
                  return DropdownMenuItem<String>(
                    value: route['id'].toString(),
                    child: Text(route['route_name'] ?? 'Route Option'),
                  );
                }).toList(),
                onChanged: (val) => setModalState(() => selectedRouteId = val),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: timingController,
                decoration: InputDecoration(
                  labelText: 'Morning Pickup Timing',
                  hintText: 'HH:MM:SS format',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B5BFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: selectedRouteId == null ? null : () async {
                try {
                  final dynamic finalRouteId = (int.tryParse(selectedRouteId!) != null)
                      ? int.parse(selectedRouteId!)
                      : selectedRouteId!;

                  await _supabase.from('stops').insert({
                    'route_id': finalRouteId,
                    'stop_name': request['requested_boarding_point'],
                    'timing': timingController.text.trim(),
                  });

                  await _supabase.from('route_requests').update({'status': 'approved'}).eq('id', request['id']);

                  if (request['requested_by'] != null) {
                    await _supabase.from('notifications').insert({
                      'institution_id': request['institution_id'],
                      'recipient_id': request['requested_by'],
                      'title': 'Request Approved',
                      'message': '"${request['requested_boarding_point']}" was approved and added to the route.',
                    });
                  }

                  if (context.mounted) Navigator.pop(context);
                  _fetchRouteRequests();
                  _fetchLiveRoutesAndStops();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to save stop: $e'), backgroundColor: Colors.redAccent),
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
      final request = _pendingRequests.firstWhere((r) => r['id'] == requestId, orElse: () => {});
      await _supabase.from('route_requests').update({'status': 'rejected'}).eq('id', requestId);

      if (request.isNotEmpty && request['requested_by'] != null) {
        await _supabase.from('notifications').insert({
          'institution_id': request['institution_id'],
          'recipient_id': request['requested_by'],
          'title': 'Request Declined',
          'message': '"${request['requested_boarding_point']}" was declined by admin.',
        });
      }

      _fetchRouteRequests();
    } catch (e) {
      debugPrint('Error rejecting request: $e');
    }
  }

  void _showPendingRequestsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SizedBox(
          height: 400,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Pending Route Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                            subtitle: Text('Submitted: ${request['created_at'].toString().substring(0, 10)}'),
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
        );
      },
    );
  }

  // --- Route & Stop editing ---

  Future<void> _updateRouteName(dynamic routeId, String newName) async {
    if (newName.trim().isEmpty) return;
    try {
      await _supabase.from('routes').update({'route_name': newName.trim()}).eq('id', routeId);
      await _fetchLiveRoutesAndStops();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route updated.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update route: $e'), backgroundColor: Colors.redAccent),
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
          SnackBar(content: Text('Failed to delete route: $e'), backgroundColor: Colors.redAccent),
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
          SnackBar(content: Text('Failed to update stop: $e'), backgroundColor: Colors.redAccent),
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
          SnackBar(content: Text('Failed to delete stop: $e'), backgroundColor: Colors.redAccent),
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
          SnackBar(content: Text('Failed to add stop: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _openEditRouteDialog(Map<String, dynamic> initialRoute) {
    final routeId = initialRoute['id'];
    final routeNameController = TextEditingController(text: initialRoute['route_name'] ?? '');
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
                    ...stops.map((stop) {
                      final nameController = TextEditingController(text: stop['stop_name'] ?? '');
                      final timingController = TextEditingController(text: stop['timing'] ?? '');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: nameController,
                                decoration: const InputDecoration(labelText: 'Stop', isDense: true),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: timingController,
                                decoration: const InputDecoration(labelText: 'Timing', isDense: true),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.save_outlined, color: Color(0xFF3B5BFF), size: 18),
                              tooltip: 'Save this stop',
                              onPressed: () async {
                                await _updateStop(stop['id'], nameController.text, timingController.text);
                                setModalState(() {});
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                              tooltip: 'Delete this stop',
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
                          tooltip: 'Add stop',
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
                    builder: (confirmContext) => AlertDialog(
                      title: const Text('Delete Route?'),
                      content: const Text('This will also delete all stops under this route. This cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(confirmContext, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                          onPressed: () => Navigator.pop(confirmContext, true),
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
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B5BFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  await _updateRouteName(routeId, routeNameController.text);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('Save Route Name', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
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
            stagedExcelRoutes: _stagedExcelRoutes,
            isProcessingExcel: _isProcessingExcel,
            onImportExcel: _importExcelFile,
            onSaveExcel: _saveExcelDataToDatabase,
            onRemoveStagedItem: (idx) {
              setState(() {
                _stagedExcelRoutes.removeAt(idx);
              });
            },
            onUpdateStagedItem: (idx, field, newVal) {
              setState(() {
                _stagedExcelRoutes[idx][field] = newVal.toString();
              });
            },
          ),
          const _PlaceholderTab(title: 'Help Desk'),
          const _PlaceholderTab(title: 'Commuters'),
          _BusDetailsTab(
            liveRoutes: _liveDatabaseRoutesWithStops,
            isLoading: _isLoadingLiveRoutes,
            onRefresh: _fetchLiveRoutesAndStops,
            onEditRoute: _openEditRouteDialog,
          ),
          const _PlaceholderTab(title: 'Settings'),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            )
          ],
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.home_rounded, label: 'Home', index: 0, currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
                _NavItem(icon: Icons.support_agent_rounded, label: 'Help Desk', index: 1, currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
                _NavItem(icon: Icons.people_rounded, label: 'Commuters', index: 2, currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
                _NavItem(icon: Icons.directions_bus_rounded, label: 'Bus Details', index: 3, currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
                _NavItem(icon: Icons.settings_rounded, label: 'Settings', index: 4, currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF3B5BFF).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? const Color(0xFF3B5BFF) : const Color(0xFF8892AA), size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? const Color(0xFF3B5BFF) : const Color(0xFF8892AA),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  final List<Map<String, String>> stagedExcelRoutes;
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.menu_rounded, color: Color(0xFF0F1B4C), size: 22),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: isProcessingExcel
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.note_add_rounded, color: Colors.green, size: 28),
                          onPressed: onImportExcel,
                          tooltip: "Upload Master CSV Sheet File",
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.badge_outlined, color: Color(0xFF3B5BFF), size: 26),
                              if (pendingCredentials > 0)
                                Positioned(
                                  right: -4,
                                  top: -4,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: const BoxDecoration(color: Color(0xFFE24B4A), shape: BoxShape.circle),
                                    child: Center(
                                      child: Text(
                                        '$pendingCredentials',
                                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const PendingCredentialsScreen()),
                          ),
                          tooltip: "Pending Student Credentials",
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onBellTap,
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                                child: const Icon(Icons.notifications_outlined, color: Color(0xFF0F1B4C), size: 22),
                              ),
                              if (pendingRequests.isNotEmpty)
                                Positioned(
                                  right: 6,
                                  top: 6,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: const BoxDecoration(color: Color(0xFFE24B4A), shape: BoxShape.circle),
                                    child: Center(
                                      child: Text(
                                        '${pendingRequests.length}',
                                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Welcome back,', style: TextStyle(fontSize: 16, color: Color(0xFF8892AA))),
                    Row(
                      children: [
                        const Text('Admin', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
                        const SizedBox(width: 8),
                        const Text(' 👋 ', style: TextStyle(fontSize: 24)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blueAccent, size: 18),
                          SizedBox(width: 6),
                          Text('CSV Formatting Requirements', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F1B4C), fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('Your file must be saved as a standard comma-separated .csv file with 3 columns:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Col A: Route Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            Text('Col B: Stop Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            Text('Col C: Timing (HH:MM:SS)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                            )
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
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: dataItem['route_name'].toString(),
                                        decoration: const InputDecoration(labelText: 'Route Name', border: InputBorder.none),
                                        onChanged: (val) => onUpdateStagedItem(idx, 'route_name', val),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: dataItem['stop_name'].toString(),
                                        decoration: const InputDecoration(labelText: 'Stop Name', border: InputBorder.none),
                                        onChanged: (val) => onUpdateStagedItem(idx, 'stop_name', val),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: TextFormField(
                                  initialValue: dataItem['timing'].toString(),
                                  decoration: const InputDecoration(labelText: 'Timing', border: InputBorder.none),
                                  onChanged: (val) => onUpdateStagedItem(idx, 'timing', val),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => onRemoveStagedItem(idx),
                                ),
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
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFD4DEFF), width: 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(color: Color(0xFF3B5BFF), shape: BoxShape.circle),
                        child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Institution', style: TextStyle(fontSize: 12, color: Color(0xFF8892AA))),
                            Text(institutionName.isEmpty ? 'Loading...' : institutionName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F1B4C))),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF8892AA)),
                                const SizedBox(width: 4),
                                Text(institutionCity, style: const TextStyle(fontSize: 13, color: Color(0xFF8892AA))),
                              ],
                            ),
                          ],
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
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8EAF0), width: 0.5)),
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
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No routes defined yet.')),
                    ],
                  )
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
                            tooltip: 'Edit route',
                            onPressed: () => onEditRoute(route),
                          ),
                          children: stops.map<Widget>((stop) {
                            String timeDisplay = '';
                            if (stop['timing'] != null) {
                              final rawTime = stop['timing'].toString();
                              timeDisplay = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
                            }
                            return ListTile(
                              leading: const Icon(Icons.location_on_rounded, color: Colors.blueAccent),
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

class _PlaceholderTab extends StatelessWidget {
  final String title;
  const _PlaceholderTab({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('$title Submenu Dashboard Panel Content Here'));
  }
}