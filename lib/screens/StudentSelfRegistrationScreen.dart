import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'map_picker_screen.dart';

class StudentSelfRegistrationScreen extends StatefulWidget {
  final String? institutionId;
  const StudentSelfRegistrationScreen({super.key, this.institutionId});

  @override
  State<StudentSelfRegistrationScreen> createState() => _StudentSelfRegistrationScreenState();
}

class _StudentSelfRegistrationScreenState extends State<StudentSelfRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  String _role = 'student';
  String _studentName = '';
  String _studentEmail = '';
  String _admissionDate = '';
  String _department = '';
  String _employeeId = '';
  String _parentName = '';
  String _parentRelation = 'Father';
  String _parentEmail = '';
  String _parentPhone = '';

  LatLng? _homeLocation;
  List<Map<String, dynamic>> _allStops = [];
  List<Map<String, dynamic>> _nearbyStops = [];
  Map<String, dynamic>? _selectedStop;
  bool _wantsCustomStop = false;
  LatLng? _customStopLocation;
  String _customStopNote = '';

  bool _isLoadingStops = true;
  bool _isSubmitting = false;
  String? _institutionId;

  @override
  void initState() {
    super.initState();
    _loadStops();
  }

  Future<void> _loadStops() async {
    try {
      _institutionId = widget.institutionId;
      debugPrint('🔍 Institution ID: $_institutionId');

      if (_institutionId == null) {
        debugPrint('❌ NO INSTITUTION ID!');
        setState(() => _isLoadingStops = false);
        return;
      }

      debugPrint('�� Getting ALL stops...');
      final data = await _supabase
          .from('stops')
          .select('id, stop_name, timing, lat, lng, route_id')
          .not('lat', 'is', null)
          .not('lng', 'is', null);

      debugPrint('✅ Total stops: ${data.length}');

      debugPrint('🔄 Getting routes for this institution...');
      final routesData = await _supabase
          .from('routes')
          .select('id')
          .eq('institution_id', _institutionId!);

      debugPrint('✅ Routes found: ${routesData.length}');

      final routeIds = (routesData as List).map((r) => r['id']).toList();
      final filteredStops = (data as List)
          .where((stop) => routeIds.contains(stop['route_id']))
          .toList();

      debugPrint('✅ Filtered stops: ${filteredStops.length}');

      setState(() {
        _allStops = List<Map<String, dynamic>>.from(filteredStops);
        _isLoadingStops = false;
      });
    } catch (e, stack) {
      debugPrint('❌ ERROR: $e');
      debugPrint('Stack: $stack');
      setState(() => _isLoadingStops = false);
    }
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  void _computeNearbyStops() {
    debugPrint('🔍 Computing. Home: $_homeLocation, Stops: ${_allStops.length}');
    
    if (_homeLocation == null || _allStops.isEmpty) {
      debugPrint('❌ Cannot compute');
      return;
    }

    final withDistance = _allStops.map((stop) {
      final distance = _distanceKm(
        _homeLocation!.latitude,
        _homeLocation!.longitude,
        double.parse(stop['lat'].toString()),
        double.parse(stop['lng'].toString()),
      );
      return {...stop, 'distance': distance};
    }).toList();

    withDistance.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

    setState(() {
      _nearbyStops = withDistance.take(5).toList();
      _selectedStop = null;
      _wantsCustomStop = false;
    });
    
    debugPrint('✅ Nearby stops computed: ${_nearbyStops.length}');
  }

  Future<void> _pickHomeLocation() async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLocation: _homeLocation,
          title: 'Tap Your Home Location',
        ),
      ),
    );
    if (picked != null) {
      debugPrint('📍 Home location picked: ${picked.latitude}, ${picked.longitude}');
      setState(() => _homeLocation = picked);
      _computeNearbyStops();
    }
  }

  Future<void> _pickCustomStopLocation() async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLocation: _homeLocation,
          title: 'Tap Your Preferred Boarding Point',
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _customStopLocation = picked;
        _wantsCustomStop = true;
        _selectedStop = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    if (_homeLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please tap your home location on the map.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (_selectedStop == null && !_wantsCustomStop) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a boarding stop, or request a custom one.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (_wantsCustomStop && _customStopLocation != null) {
        try {
          await _supabase.from('route_requests').insert({
            'institution_id': _institutionId,
            'requested_boarding_point': _customStopNote.trim().isEmpty ? 
              'Custom location (${_customStopLocation!.latitude.toStringAsFixed(4)}, ${_customStopLocation!.longitude.toStringAsFixed(4)})' :
              _customStopNote.trim(),
            'status': 'pending',
          });

          await _supabase.from('notifications').insert({
            'institution_id': _institutionId,
            'title': 'New Custom Stop Request',
            'message': '$_studentName requested a custom boarding stop: ${_customStopNote.isNotEmpty ? _customStopNote : "Custom location"}',
            'is_read': false,
          });
        } catch (e) {
          debugPrint('Error creating route request: $e');
        }
      }

      await _supabase.from('pending_enrollments').insert({
        'institution_id': _institutionId,
        'role': _role,
        'student_name': _studentName,
        'student_email': _studentEmail.trim().isEmpty ? null : _studentEmail.trim(),
        'admission_date': _role == 'student' && _admissionDate.trim().isNotEmpty ? _admissionDate.trim() : null,
        'department': _department.trim().isEmpty ? null : _department.trim(),
        'employee_id': _role == 'faculty' ? _employeeId.trim() : null,
        'parent_name': _role == 'student' ? _parentName : null,
        'parent_relation': _role == 'student' ? _parentRelation.toLowerCase() : null,
        'parent_email': _role == 'student' ? _parentEmail.trim() : null,
        'parent_phone': _role == 'student' ? _parentPhone.trim() : null,
        'home_lat': _homeLocation!.latitude,
        'home_lng': _homeLocation!.longitude,
        'suggested_stop_id': _selectedStop?['id'],
        'suggested_route_id': _selectedStop?['route_id'],
        'wants_custom_stop': _wantsCustomStop,
        'custom_stop_lat': _customStopLocation?.latitude,
        'custom_stop_lng': _customStopLocation?.longitude,
        'custom_stop_note': _customStopNote.trim().isEmpty ? null : _customStopNote.trim(),
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 12),
                Text('Registration Submitted!'),
              ],
            ),
            content: const Text('Your registration has been submitted. Our help desk will review and contact you soon.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Text('New Registration', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),

                const Text('Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7A99))),
                TextFormField(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  onSaved: (v) => _studentName = v ?? '',
                ),
                const SizedBox(height: 14),

                const Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7A99))),
                TextFormField(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onSaved: (v) => _studentEmail = v ?? '',
                ),
                const SizedBox(height: 20),

                const Text('BOARDING LOCATION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF3B5BFF), letterSpacing: 0.5)),
                const SizedBox(height: 10),

                OutlinedButton.icon(
                  onPressed: _pickHomeLocation,
                  icon: Icon(_homeLocation == null ? Icons.location_searching : Icons.location_on, size: 18),
                  label: Text(_homeLocation == null ? 'Tap to Set Home Location' : 'Home Location Set — Tap to Change'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: const Color(0xFF3B5BFF),
                  ),
                ),

                if (_homeLocation != null && _isLoadingStops)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),

                if (_homeLocation != null && !_isLoadingStops && _nearbyStops.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Nearest available stops:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ..._nearbyStops.map((stop) {
                    final isSelected = _selectedStop != null && _selectedStop!['id'] == stop['id'];
                    final distance = (stop['distance'] as double).toStringAsFixed(2);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() {
                          _selectedStop = stop;
                          _wantsCustomStop = false;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isSelected ? const Color(0xFF3B5BFF) : const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: isSelected ? const Color(0xFF3B5BFF) : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(stop['stop_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text(
                                      '$distance km away',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF8892AA)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],

                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B5BFF),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Submit Registration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
