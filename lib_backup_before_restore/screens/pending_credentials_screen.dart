import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PendingCredentialsScreen extends StatefulWidget {
  const PendingCredentialsScreen({super.key});

  @override
  State<PendingCredentialsScreen> createState() => _PendingCredentialsScreenState();
}

class _PendingCredentialsScreenState extends State<PendingCredentialsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _pendingStudents = [];
  final Set<dynamic> _selectedIds = {};
  bool _isLoading = true;
  bool _isGenerating = false;
  String? _institutionId;
  RealtimeChannel? _channel;

  List<Map<String, dynamic>> _pendingFaculty = [];
  final Set<dynamic> _selectedFacultyIds = {};
  bool _isLoadingFaculty = true;
  bool _isGeneratingFaculty = false;
  RealtimeChannel? _facultyChannel;

  @override
  void initState() {
    super.initState();
    _loadPendingStudents();
    _loadPendingFaculty();
    _subscribeToRealtimeUpdates();
    _subscribeToFacultyRealtimeUpdates();
  }

  @override
  void dispose() {
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }
    if (_facultyChannel != null) {
      _supabase.removeChannel(_facultyChannel!);
    }
    super.dispose();
  }

  void _subscribeToRealtimeUpdates() {
    _channel = _supabase
        .channel('students_pending_credentials')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'students',
          callback: (payload) {
            if (mounted) _loadPendingStudents();
          },
        )
        .subscribe();
  }

  void _subscribeToFacultyRealtimeUpdates() {
    _facultyChannel = _supabase
        .channel('faculty_pending_credentials')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'faculty',
          callback: (payload) {
            if (mounted) _loadPendingFaculty();
          },
        )
        .subscribe();
  }

  Future<void> _loadPendingStudents() async {
    setState(() => _isLoading = true);
    try {
      final adminId = _supabase.auth.currentUser?.id;
      if (adminId == null) return;

      final institution = await _supabase
          .from('institutions')
          .select('id')
          .eq('admin_id', adminId)
          .maybeSingle();

      if (institution == null) {
        setState(() {
          _pendingStudents = [];
          _isLoading = false;
        });
        return;
      }

      _institutionId = institution['id'];

      final data = await _supabase
          .from('students')
          .select('''
            id, student_name, enrollment_no, department, year, student_email, parent_email,
            admission_date, credential_generated,
            buses(bus_name, bus_number), routes(route_name), stops(stop_name), boarding_point
          ''')
          .eq('institution_id', _institutionId!)
          .eq('credential_generated', false)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _pendingStudents = List<Map<String, dynamic>>.from(data);
          _selectedIds.removeWhere((id) => !_pendingStudents.any((s) => s['id'] == id));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load pending students: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPendingFaculty() async {
    setState(() => _isLoadingFaculty = true);
    try {
      final adminId = _supabase.auth.currentUser?.id;
      if (adminId == null) return;

      final institution = await _supabase
          .from('institutions')
          .select('id')
          .eq('admin_id', adminId)
          .maybeSingle();

      if (institution == null) {
        setState(() {
          _pendingFaculty = [];
          _isLoadingFaculty = false;
        });
        return;
      }

      final institutionId = institution['id'];

      final data = await _supabase
          .from('faculty')
          .select('''
            id, faculty_name, employee_id, department, faculty_email, faculty_phone,
            boarding_point, credential_generated, routes(route_name), stops(stop_name)
          ''')
          .eq('institution_id', institutionId)
          .eq('credential_generated', false)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _pendingFaculty = List<Map<String, dynamic>>.from(data);
          _selectedFacultyIds.removeWhere((id) => !_pendingFaculty.any((f) => f['id'] == id));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load pending faculty: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingFaculty = false);
    }
  }

  Future<void> _generateCredentials({bool allPending = false}) async {
    final targetIds = allPending
        ? _pendingStudents.map((s) => s['id']).toList()
        : _selectedIds.toList();

    if (targetIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one student first.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final adminId = _supabase.auth.currentUser!.id;

      final response = await _supabase.functions.invoke(
        'generate-student-credentials',
        body: {'studentIds': targetIds, 'adminId': adminId},
      );

      final results = (response.data?['results'] as List?) ?? [];
      final successCount = results.where((r) => r['success'] == true).length;
      final failCount = results.length - successCount;

      await _loadPendingStudents();
      _selectedIds.clear();

      if (mounted) {
        _showResultDialog(successCount: successCount, failCount: failCount, results: results);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate credentials: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateFacultyCredentials({bool allPending = false}) async {
    final targetIds = allPending
        ? _pendingFaculty.map((f) => f['id']).toList()
        : _selectedFacultyIds.toList();

    if (targetIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one faculty member first.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isGeneratingFaculty = true);
    try {
      final adminId = _supabase.auth.currentUser!.id;

      final response = await _supabase.functions.invoke(
        'generate-faculty-credentials',
        body: {'facultyIds': targetIds, 'adminId': adminId},
      );

      final results = (response.data?['results'] as List?) ?? [];
      final successCount = results.where((r) => r['success'] == true).length;
      final failCount = results.length - successCount;

      await _loadPendingFaculty();
      _selectedFacultyIds.clear();

      if (mounted) {
        _showResultDialog(successCount: successCount, failCount: failCount, results: results);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate credentials: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingFaculty = false);
    }
  }

  void _showResultDialog({
    required int successCount,
    required int failCount,
    required List results,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              failCount == 0 ? Icons.check_circle : Icons.warning_amber_rounded,
              color: failCount == 0 ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            const Text('Credential Generation Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$successCount processed successfully.'),
            if (failCount > 0) ...[
              const SizedBox(height: 8),
              Text('$failCount failed:', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
              ...results.where((r) => r['success'] != true).map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• ${r['error'] ?? 'Unknown error'}', style: const TextStyle(fontSize: 12)),
                    ),
                  ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text('Pending Credentials', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F1B4C))),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF3B5BFF)),
            onPressed: () {
              _loadPendingStudents();
              _loadPendingFaculty();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildStudentSection()),
          const Divider(height: 1),
          Expanded(child: _buildFacultySection()),
        ],
      ),
    );
  }

  Widget _buildStudentSection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pendingStudents.isEmpty) {
      return const Center(child: Text('No students awaiting credential generation.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                '${_pendingStudents.length} student(s) pending',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F1B4C)),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (_selectedIds.length == _pendingStudents.length) {
                      _selectedIds.clear();
                    } else {
                      _selectedIds
                        ..clear()
                        ..addAll(_pendingStudents.map((s) => s['id']));
                    }
                  });
                },
                icon: const Icon(Icons.check_box_outlined, size: 18),
                label: Text(_selectedIds.length == _pendingStudents.length ? 'Deselect All' : 'Select All'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('')),
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Enrollment No')),
                  DataColumn(label: Text('Dept')),
                  DataColumn(label: Text('Year')),
                  DataColumn(label: Text('Student Email')),
                  DataColumn(label: Text('Parent Email')),
                  DataColumn(label: Text('Bus')),
                  DataColumn(label: Text('Route')),
                  DataColumn(label: Text('Boarding Point')),
                  DataColumn(label: Text('Admission Date')),
                  DataColumn(label: Text('Status')),
                ],
                rows: _pendingStudents.map((student) {
                  final isSelected = _selectedIds.contains(student['id']);
                  final bus = student['buses'];
                  final route = student['routes'];
                  return DataRow(
                    selected: isSelected,
                    onSelectChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedIds.add(student['id']);
                        } else {
                          _selectedIds.remove(student['id']);
                        }
                      });
                    },
                    cells: [
                      DataCell(Checkbox(
                        value: isSelected,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedIds.add(student['id']);
                            } else {
                              _selectedIds.remove(student['id']);
                            }
                          });
                        },
                      )),
                      DataCell(Text(student['student_name'] ?? '')),
                      DataCell(Text(student['enrollment_no'] ?? '')),
                      DataCell(Text(student['department'] ?? '')),
                      DataCell(Text(student['year'] ?? '')),
                      DataCell(Text(student['student_email'] ?? '—')),
                      DataCell(Text(student['parent_email'] ?? '—')),
                      DataCell(Text(bus != null ? (bus['bus_name'] ?? bus['bus_number'] ?? '—') : '—')),
                      DataCell(Text(route != null ? (route['route_name'] ?? '—') : '—')),
                      DataCell(Text(student['boarding_point'] ?? '—')),
                      DataCell(Text(student['admission_date']?.toString() ?? '—')),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Pending', style: TextStyle(fontSize: 11, color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isGenerating ? null : () => _generateCredentials(allPending: true),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Generate for All Pending'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isGenerating ? null : () => _generateCredentials(allPending: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B5BFF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isGenerating
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Generate for Selected (${_selectedIds.length})', style: const TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFacultySection() {
    if (_isLoadingFaculty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pendingFaculty.isEmpty) {
      return const Center(child: Text('No faculty awaiting credential generation.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                '${_pendingFaculty.length} faculty pending',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F1B4C)),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (_selectedFacultyIds.length == _pendingFaculty.length) {
                      _selectedFacultyIds.clear();
                    } else {
                      _selectedFacultyIds
                        ..clear()
                        ..addAll(_pendingFaculty.map((f) => f['id']));
                    }
                  });
                },
                icon: const Icon(Icons.check_box_outlined, size: 18),
                label: Text(_selectedFacultyIds.length == _pendingFaculty.length ? 'Deselect All' : 'Select All'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('')),
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Employee ID')),
                  DataColumn(label: Text('Dept')),
                  DataColumn(label: Text('Faculty Email')),
                  DataColumn(label: Text('Phone')),
                  DataColumn(label: Text('Route')),
                  DataColumn(label: Text('Boarding Point')),
                  DataColumn(label: Text('Status')),
                ],
                rows: _pendingFaculty.map((fac) {
                  final isSelected = _selectedFacultyIds.contains(fac['id']);
                  final route = fac['routes'];
                  final stop = fac['stops'];
                  return DataRow(
                    selected: isSelected,
                    onSelectChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedFacultyIds.add(fac['id']);
                        } else {
                          _selectedFacultyIds.remove(fac['id']);
                        }
                      });
                    },
                    cells: [
                      DataCell(Checkbox(
                        value: isSelected,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedFacultyIds.add(fac['id']);
                            } else {
                              _selectedFacultyIds.remove(fac['id']);
                            }
                          });
                        },
                      )),
                      DataCell(Text(fac['faculty_name'] ?? '')),
                      DataCell(Text(fac['employee_id'] ?? '—')),
                      DataCell(Text(fac['department'] ?? '—')),
                      DataCell(Text(fac['faculty_email'] ?? '—')),
                      DataCell(Text(fac['faculty_phone'] ?? '—')),
                      DataCell(Text(route != null ? (route['route_name'] ?? '—') : '—')),
                      DataCell(Text(fac['boarding_point'] ?? (stop != null ? (stop['stop_name'] ?? '—') : '—'))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Pending', style: TextStyle(fontSize: 11, color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isGeneratingFaculty ? null : () => _generateFacultyCredentials(allPending: true),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Generate for All Pending'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isGeneratingFaculty ? null : () => _generateFacultyCredentials(allPending: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B5BFF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isGeneratingFaculty
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Generate for Selected (${_selectedFacultyIds.length})', style: const TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
