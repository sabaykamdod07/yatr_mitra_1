import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'role_selection_screen.dart';

class HelpDeskDashboard extends StatefulWidget {
  const HelpDeskDashboard({super.key});

  @override
  State<HelpDeskDashboard> createState() => HelpDeskDashboardState();
}

class HelpDeskDashboardState extends State<HelpDeskDashboard> with SingleTickerProviderStateMixin {
  final List<Map<String, dynamic>> _students = [];
  final List<Map<String, dynamic>> _routesWithStops = [];
  bool _isLoading = true;
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;
  DateTime? _lastBackPress;

  String _studentName = '';
  String _usnCollegeId = '';
  String _studentEmail = '';
  String _studentPhone = '';
  String _studentDepartment = '';
  String _studentYear = '1st Year';
  String _studentType = 'College'; // 'College' or 'School' - toggles which fields show
  String _dateOfAdmission = '';
  String _parentName = '';
  String _parentRelation = 'Father';
  String _parentEmail = '';
  String _parentPhone = '';
  String _boardingPoint = '';
  String _feeStatus = 'Unpaid';
  Map<String, dynamic>? _editingStudent;
  String? _currentInstitutionId;

  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;

  // ===== NEW: Pending Registrations State =====
  List<Map<String, dynamic>> _pendingRegistrations = [];
  RealtimeChannel? _pendingRegChannel;
  String? _reviewingRegistrationId;
  bool? _reviewingWantsCustomStop;
  String? _reviewingCustomStopNote;
  // =============================================

  // ===== NEW: Announcements State =====
  List<Map<String, dynamic>> _announcements = [];
  RealtimeChannel? _announcementsChannel;
  // ====================================

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDashboardData();
    _subscribeToPendingRegistrations(); // ← NEW
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (_pendingRegChannel != null) _supabase.removeChannel(_pendingRegChannel!); // ← NEW
    if (_announcementsChannel != null) _supabase.removeChannel(_announcementsChannel!); // ← NEW
    super.dispose();
  }

  // ===== NEW: Registration Form URL Getter =====
  String get _registrationFormUrl {
    if (_currentInstitutionId == null) return '';
    return 'https://your-project-id.web.app/?inst=$_currentInstitutionId';
  }

  void _showRegistrationLinkDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Student Registration Link',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F1B4C)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this link with students to fill the registration form:',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7A99)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: SelectableText(
                _registrationFormUrl,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '📌 Students will fill the form, and their data will automatically appear in "Pending Registrations".',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7A99), fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF6B7A99))),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B5BFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              // Copy to clipboard
              Clipboard.setData(ClipboardData(text: _registrationFormUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copied to clipboard!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
              Navigator.pop(context);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Link', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ===== NEW: Pending Registrations Subscription =====
  void _subscribeToPendingRegistrations() {
    _pendingRegChannel = _supabase
        .channel('pending_enrollments_helpdesk')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pending_enrollments',
          callback: (payload) {
            if (mounted) _fetchPendingRegistrations();
          },
        )
        .subscribe();
  }

  // ===== NEW: Announcements Subscription =====
  void _subscribeToAnnouncements() {
    _announcementsChannel = _supabase
        .channel('announcements_helpdesk')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'announcements',
          callback: (payload) {
            if (mounted) _fetchAnnouncements();
          },
        )
        .subscribe();
  }

  Future<void> _fetchAnnouncements() async {
    if (_currentInstitutionId == null) return;
    try {
      final data = await _supabase
          .from('announcements')
          .select('*')
          .eq('institution_id', _currentInstitutionId!)
          .inFilter('target_role', ['all', 'help_desk'])
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _announcements = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Error fetching announcements: $e');
    }
  }

  Future<void> _fetchPendingRegistrations() async {
    if (_currentInstitutionId == null) return;
    try {
      final data = await _supabase
          .from('pending_enrollments')
          .select('*')
          .eq('institution_id', _currentInstitutionId!)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _pendingRegistrations = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Error fetching pending registrations: $e');
    }
  }

  Future<void> _dismissPendingRegistration(String id) async {
    try {
      await _supabase.from('pending_enrollments').delete().eq('id', id);
      _fetchPendingRegistrations();
    } catch (e) {
      _showSnack('Failed to dismiss: $e');
    }
  }

  // ===== NEW: Show Announcements Sheet =====
  void _showAnnouncementsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Announcements', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Expanded(
                child: _announcements.isEmpty
                    ? const Center(child: Text('No announcements.'))
                    : ListView.builder(
                        itemCount: _announcements.length,
                        itemBuilder: (context, index) {
                          final announcement = _announcements[index];
                          final targetRole = (announcement['target_role'] ?? 'all').toString();
                          final createdAtRaw = announcement['created_at']?.toString() ?? '';
                          final createdAt = createdAtRaw.length >= 16
                              ? createdAtRaw.substring(0, 16).replaceFirst('T', ' ')
                              : createdAtRaw;
                          
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3B5BFF).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            targetRole == 'help_desk'
                                                ? Icons.support_agent_rounded
                                                : Icons.campaign_rounded,
                                            size: 12,
                                            color: const Color(0xFF3B5BFF),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            targetRole == 'all' ? 'Everyone' : 'Help Desk',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF3B5BFF),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      createdAt,
                                      style: const TextStyle(fontSize: 10, color: Color(0xFF8892AA)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  announcement['title'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xFF0F1B4C),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  announcement['body'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF3E4759),
                                    height: 1.4,
                                  ),
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
  // ==========================================

  void _showPendingRegistrationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Pending Registrations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Expanded(
                    child: _pendingRegistrations.isEmpty
                        ? const Center(child: Text('No pending registrations.'))
                        : ListView.builder(
                            itemCount: _pendingRegistrations.length,
                            itemBuilder: (context, index) {
                              final reg = _pendingRegistrations[index];
                              return ListTile(
                                leading: Icon(
                                  Icons.school_outlined,
                                  color: const Color(0xFF3B5BFF),
                                ),
                                title: Text(reg['student_name'] ?? ''),
                                subtitle: Text(
                                  'Student • ${reg['department'] ?? '—'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: reg['wants_custom_stop'] == true
                                    ? const Icon(Icons.location_off_outlined, color: Colors.amber, size: 18)
                                    : const Icon(Icons.chevron_right, size: 18),
                                onTap: () {
                                  Navigator.pop(context);
                                  _openFormModal(null, reg);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('helpdesk_accounts')
          .select('institution_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (profile != null) {
        _currentInstitutionId = profile['institution_id'];

        await _fetchNotifications();
        await _fetchPendingRegistrations(); // ← NEW
        await _fetchAnnouncements(); // ← NEW
        _subscribeToAnnouncements(); // ← NEW

        final studentData = await _supabase
            .from('students')
            .select('*')
            .eq('institution_id', _currentInstitutionId!)
            .order('created_at', ascending: false);

        final routeData = await _supabase
            .from('routes')
            .select('id, route_name, bus_id, stops(stop_name, timing)')
            .eq('institution_id', _currentInstitutionId!)
            .order('route_name', ascending: true);

        setState(() {
          _students.clear();
          _students.addAll(List<Map<String, dynamic>>.from(studentData));
          _routesWithStops.clear();
          _routesWithStops.addAll(List<Map<String, dynamic>>.from(routeData));
        });
      }
    } catch (e) {
      _showSnack('Error synchronizing dashboard data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchNotifications() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final data = await _supabase
          .from('notifications')
          .select('id, title, message, is_read, created_at')
          .eq('recipient_id', user.id)
          .order('created_at', ascending: false)
          .limit(20);

      setState(() {
        _notifications = List<Map<String, dynamic>>.from(data);
        _unreadCount = _notifications.where((n) => n['is_read'] == false).length;
      });
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    }
  }

  Future<void> _markAllNotificationsRead() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('recipient_id', user.id)
          .eq('is_read', false);
      setState(() => _unreadCount = 0);
    } catch (e) {
      debugPrint('Error marking notifications read: $e');
    }
  }

  void _showNotificationsSheet() {
    _markAllNotificationsRead();
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
                child: Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Expanded(
                child: _notifications.isEmpty
                    ? const Center(child: Text('No notifications yet.'))
                    : ListView.builder(
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final n = _notifications[index];
                          return ListTile(
                            leading: Icon(
                              n['title'].toString().toLowerCase().contains('approved')
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: n['title'].toString().toLowerCase().contains('approved')
                                  ? Colors.green
                                  : Colors.redAccent,
                            ),
                            title: Text(n['title'] ?? ''),
                            subtitle: Text(n['message'] ?? ''),
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

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out?'),
        content: const Text('You will need to sign in again to access this dashboard.'),
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

  void _showSnack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _capitalize(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    return value.trim().split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  Future<void> _submitRouteRequest(String targetStop, String? targetStudentId) async {
    if (targetStop.trim().isEmpty) {
      _showSnack('Please enter a valid stop name first.');
      return;
    }
    try {
      final user = _supabase.auth.currentUser;

      await _supabase.from('route_requests').insert({
        'student_id': targetStudentId,
        'institution_id': _currentInstitutionId,
        'requested_boarding_point': targetStop.trim(),
        'status': 'pending',
        'requested_by': user?.id,
      });

      _showSnack('Addition request for "$targetStop" forwarded to admin panel!', isError: false);
    } catch (e) {
      _showSnack('Failed to forward request: $e');
    }
  }

  void _openFormModal([Map<String, dynamic>? student, Map<String, dynamic>? prefillFromRegistration]) {
    _editingStudent = student;
    _reviewingRegistrationId = prefillFromRegistration?['id'];
    _reviewingWantsCustomStop = prefillFromRegistration?['wants_custom_stop'];
    _reviewingCustomStopNote = prefillFromRegistration?['custom_stop_note'];
    final reg = prefillFromRegistration;
    String rawFee = student?['fee_status'] ?? 'unpaid';
    String rawRelation = student?['parent_relation'] ?? reg?['parent_relation'] ?? 'father';

    _studentName = student?['student_name'] ?? reg?['student_name'] ?? '';
    _usnCollegeId = student?['enrollment_no'] ?? '';
    _studentEmail = student?['student_email'] ?? reg?['student_email'] ?? '';
    _studentPhone = student?['student_phone'] ?? '';
    _studentDepartment = student?['department'] ?? reg?['department'] ?? '';
    _studentYear = student?['year'] ?? '1st Year';
    _studentType = 'College';
    _dateOfAdmission = student?['admission_date'] ?? reg?['admission_date'] ?? '';
    _parentName = student?['parent_name'] ?? reg?['parent_name'] ?? '';

    _parentRelation = ['Father', 'Mother', 'Guardian'].contains(_capitalize(rawRelation))
        ? _capitalize(rawRelation)
        : 'Father';

    _parentEmail = student?['parent_email'] ?? reg?['parent_email'] ?? '';
    _parentPhone = student?['parent_phone'] ?? reg?['parent_phone'] ?? '';
    _boardingPoint = student?['boarding_point'] ?? '';

    _feeStatus = ['Unpaid', 'Partial', 'Paid'].contains(_capitalize(rawFee))
        ? _capitalize(rawFee)
        : 'Unpaid';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            bool doesStopExist = _routesWithStops.any((route) {
              final stops = route['stops'] as List?;
              if (stops == null) return false;
              return stops.any((s) =>
                  s['stop_name'].toString().toLowerCase().trim() ==
                  _boardingPoint.toLowerCase().trim());
            });

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                _editingStudent != null ? 'Edit Profile' : 'New Enrollment',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F1B4C)),
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.95,
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader('Core Info'),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('College'),
                                  selected: _studentType == 'College',
                                  onSelected: (_) => setModalState(() => _studentType = 'College'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('School'),
                                  selected: _studentType == 'School',
                                  onSelected: (_) => setModalState(() => _studentType = 'School'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildInputField('Full Name', _studentName, (v) => _studentName = v!, required: true),
                        _buildInputField('USN / ID Card', _usnCollegeId, (v) => _usnCollegeId = v!, required: true),
                        _buildInputField('Email (optional if student has none)', _studentEmail, (v) => _studentEmail = v!, required: false, isEmail: true),
                        _buildInputField('Phone Number', _studentPhone, (v) => _studentPhone = v!, required: true),
                        if (_studentType == 'College') ...[
                          _buildInputField('Department', _studentDepartment, (v) => _studentDepartment = v!, required: true),
                          _buildDropdownField('Class Year', _studentYear, ['1st Year', '2nd Year', '3rd Year', '4th Year'],
                              (val) => setModalState(() => _studentYear = val!)),
                        ] else ...[
                          _buildDropdownField(
                            'Class',
                            [
                              'Nursery', 'LKG', 'UKG', 'Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5', 'Class 6',
                              'Class 7', 'Class 8', 'Class 9', 'Class 10', 'Class 11', 'Class 12',
                            ].contains(_studentYear) ? _studentYear : 'Nursery',
                            [
                              'Nursery', 'LKG', 'UKG', 'Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5', 'Class 6',
                              'Class 7', 'Class 8', 'Class 9', 'Class 10', 'Class 11', 'Class 12',
                            ],
                            (val) => setModalState(() => _studentYear = val!),
                          ),
                          _buildInputField('Section (optional, e.g. A, B, C)', _studentDepartment, (v) => _studentDepartment = v!, required: false),
                        ],
                        _buildInputField('Admission Date (YYYY-MM-DD)', _dateOfAdmission, (v) => _dateOfAdmission = v!, required: true),
                        const SizedBox(height: 8),
                        _sectionHeader('Guardian Reference'),
                        _buildInputField('Guardian Name', _parentName, (v) => _parentName = v!, required: true),
                        _buildDropdownField('Relation', _parentRelation, ['Father', 'Mother', 'Guardian'],
                            (val) => setModalState(() => _parentRelation = val!)),
                        _buildInputField('Guardian Email (for credentials)', _parentEmail, (v) => _parentEmail = v!, required: true, isEmail: true),
                        _buildInputField('Guardian Phone', _parentPhone, (v) => _parentPhone = v!, required: true),
                        const SizedBox(height: 8),
                        _sectionHeader('Logistics'),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: TextFormField(
                            initialValue: _boardingPoint,
                            decoration: InputDecoration(
                              labelText: 'Boarding Stop',
                              labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6B7A99)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            onChanged: (val) => setModalState(() => _boardingPoint = val),
                            onSaved: (v) => _boardingPoint = v ?? '',
                          ),
                        ),
                        if (_boardingPoint.isNotEmpty && !doesStopExist)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 18),
                                    const SizedBox(width: 6),
                                    const Expanded(
                                      child: Text(
                                        'Stop not found in database routes.',
                                        style: TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _submitRouteRequest(_boardingPoint, _editingStudent?['id']),
                                  icon: const Icon(Icons.send_rounded, size: 12, color: Colors.white),
                                  label: const Text(
                                    'Request Stop Mapping Approval',
                                    style: TextStyle(fontSize: 11, color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B5BFF),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    minimumSize: const Size(double.infinity, 36),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        _buildDropdownField('Fee Status', _feeStatus, ['Unpaid', 'Partial', 'Paid'],
                            (val) => setModalState(() => _feeStatus = val!)),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7A99))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B5BFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      _formKey.currentState!.save();
                      final payload = {
                        'institution_id': _currentInstitutionId,
                        'student_name': _studentName,
                        'enrollment_no': _usnCollegeId,
                        'student_email': _studentEmail.trim().isEmpty ? null : _studentEmail.trim(),
                        'student_phone': _studentPhone,
                        'department': _studentDepartment,
                        'year': _studentYear,
                        'admission_date': _dateOfAdmission,
                        'parent_name': _parentName,
                        'parent_relation': _parentRelation.toLowerCase(),
                        'parent_email': _parentEmail.trim(),
                        'parent_phone': _parentPhone,
                        'boarding_point': _boardingPoint.isEmpty ? null : _boardingPoint,
                        'fee_status': _feeStatus.toLowerCase(),
                      };
                      try {
                        if (_editingStudent != null) {
                          await _supabase.from('students').update(payload).eq('id', _editingStudent!['id']);
                          _showSnack('Profile updated successfully', isError: false);
                        } else {
                          await _supabase.from('students').insert([payload]);
                          _showSnack('Profile created successfully', isError: false);
                        }

                        if (_reviewingRegistrationId != null) {
                          if (_reviewingWantsCustomStop == true) {
                            await _supabase.from('route_requests').insert({
                              'institution_id': _currentInstitutionId,
                              'requested_boarding_point': _reviewingCustomStopNote ?? 'Custom stop requested by student',
                              'status': 'pending',
                            });
                          }
                          await _supabase.from('pending_enrollments').delete().eq('id', _reviewingRegistrationId!);
                          _reviewingRegistrationId = null;
                          _reviewingWantsCustomStop = null;
                          _reviewingCustomStopNote = null;
                        }

                        if (context.mounted) Navigator.pop(context);
                        _loadDashboardData();
                      } catch (e) {
                        _showSnack('Error saving profile: $e');
                      }
                    }
                  },
                  child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleDelete(dynamic id) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('This will permanently delete the student and their login account.'),
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
        final response = await _supabase.functions.invoke(
          'delete-student',
          body: {'student_id': id},
        );

        if (response.status == 200) {
          _showSnack('Student deleted successfully', isError: false);
          _loadDashboardData();
        } else {
          final error = response.data?['error'] ?? 'Unknown error';
          _showSnack('Failed to delete student: $error');
        }
      } catch (e) {
        _showSnack('Failed to complete operation: $e');
      }
    }
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF3B5BFF), letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildInputField(String label, String initialValue, FormFieldSetter<String> onSaved, {bool required = false, bool isEmail = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: TextFormField(
        initialValue: initialValue,
        keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7A99)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) return 'Cannot be empty';
          if (isEmail && v != null && v.trim().isNotEmpty) {
            final emailPattern = RegExp(r'^[\w.\-]+@[\w\-]+(\.[\w\-]+)+$');
            if (!emailPattern.hasMatch(v.trim())) return 'Enter a valid email';
          }
          return null;
        },
        onSaved: onSaved,
      ),
    );
  }

  Widget _buildDropdownField(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7A99)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        ),
        items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Color _getBadgeBgColor(String status) {
    final s = status.toLowerCase();
    if (s == 'paid') return const Color(0xFFDCFCE7);
    if (s == 'partial') return const Color(0xFFFEF9C3);
    return const Color(0xFFFEE2E2);
  }

  Color _getBadgeTextColor(String status) {
    final s = status.toLowerCase();
    if (s == 'paid') return const Color(0xFF166534);
    if (s == 'partial') return const Color(0xFF854D0E);
    return const Color(0xFF991B1B);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
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
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: AppBar(
          title: const Text('Help Desk Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF0F1B4C))),
          backgroundColor: Colors.white,
          elevation: 0.5,
          actions: [
            // ===== NEW: Announcements Button =====
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.campaign_outlined, color: Color(0xFF3B5BFF)),
                  onPressed: _showAnnouncementsSheet,
                  tooltip: 'Announcements',
                ),
                if (_announcements.isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                      child: Center(
                        child: Text('${_announcements.length}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              ],
            ),
            // ====================================
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined, color: Color(0xFF3B5BFF)),
                  onPressed: _showNotificationsSheet,
                ),
                if (_unreadCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                      child: Center(
                        child: Text('$_unreadCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              ],
            ),
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.how_to_reg_outlined, color: Color(0xFF3B5BFF)),
                  tooltip: 'Pending Registrations',
                  onPressed: _showPendingRegistrationsSheet,
                ),
                if (_pendingRegistrations.isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                      child: Center(
                        child: Text('${_pendingRegistrations.length}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined, color: Color(0xFF3B5BFF)),
              tooltip: 'Share Registration Link',
              onPressed: _showRegistrationLinkDialog,
            ),
            IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF3B5BFF)), onPressed: _loadDashboardData),
            IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.redAccent), onPressed: _handleLogout, tooltip: 'Log out'),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF3B5BFF),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF3B5BFF),
            tabs: const [
              Tab(icon: Icon(Icons.people_alt_outlined), text: "Students"),
              Tab(icon: Icon(Icons.map_outlined), text: "System Routes")
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B5BFF)))
            : TabBarView(
                controller: _tabController,
                children: [
                  RefreshIndicator(
                    onRefresh: _loadDashboardData,
                    child: _students.isEmpty
                        ? const Center(child: Text('No Profiles Registered.'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _students.length,
                            itemBuilder: (context, index) {
                              final student = _students[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: Padding(
                                  padding: const EdgeInsets.all(14.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            student['student_name'] ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F1B4C)),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: _getBadgeBgColor(student['fee_status'] ?? 'unpaid'),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _capitalize(student['fee_status']),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: _getBadgeTextColor(student['fee_status'] ?? 'unpaid'),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'USN: ${student['enrollment_no'] ?? ''}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontFamily: 'monospace'),
                                      ),
                                      Text(
                                        'Dept: ${student['department'] ?? ''} (${student['year'] ?? ''})',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const Divider(height: 16),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Stop: ${student['boarding_point'] ?? 'Pending Assignment'}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: student['boarding_point'] == null ? Colors.amber.shade800 : Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Color(0xFF3B5BFF), size: 20),
                                            onPressed: () => _openFormModal(student),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                            onPressed: () => _handleDelete(student['id']),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  _routesWithStops.isEmpty
                      ? const Center(child: Text('No routes defined.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _routesWithStops.length,
                          itemBuilder: (context, index) {
                            final route = _routesWithStops[index];
                            final stops = route['stops'] as List? ?? [];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: ExpansionTile(
                                title: Text(
                                  route['route_name'] ?? 'Unnamed Route',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F1B4C)),
                                ),
                                leading: const Icon(Icons.directions_bus_filled_outlined, color: Color(0xFF3B5BFF), size: 22),
                                children: stops.map<Widget>((stop) {
                                  String timeDisplay = '';
                                  if (stop['timing'] != null) {
                                    final rawTime = stop['timing'].toString();
                                    timeDisplay = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
                                  }
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(Icons.location_on, size: 14, color: Colors.grey[400]),
                                    title: Text(stop['stop_name'] ?? '', style: const TextStyle(fontSize: 12)),
                                    trailing: Text(
                                      timeDisplay,
                                      style: const TextStyle(
                                        color: Color(0xFF475569),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF3B5BFF),
          onPressed: () => _openFormModal(),
          child: const Icon(Icons.person_add_alt_1, color: Colors.white),
        ),
      ),
    );
  }
}