import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'role_selection_screen.dart';
import 'record_payment_sheet.dart';
import 'payment_requests_screen.dart';
import '../widgets/account_sheet.dart';
import '../widgets/link_rfid_sheet.dart';
import '../theme/ym_ui.dart';

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
  int _paymentRequestCount = 0; // payments sent by parents, waiting to be checked
  RealtimeChannel? _pendingRegChannel;
  String? _reviewingRegistrationId;
  bool? _reviewingWantsCustomStop;
  String? _reviewingCustomStopNote;
  // a payment sent with the registration form (the help desk verifies it)
  double? _reviewingPaymentAmount;
  String? _reviewingPaymentRef;
  String? _reviewingPaymentMethod; // UPI or Cash
  String? _reviewingRegCode;
  double? _reviewingCustomStopLat;
  double? _reviewingCustomStopLng;
  String _reviewingRole = 'student';
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
    return 'https://yatra-mitra-form-7c192.web.app/?inst=$_currentInstitutionId';
  }

  void _showRegistrationLinkDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
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
              backgroundColor: Ym.amber,
              foregroundColor: Ym.navy,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
            label: const Text('Copy Link', style: TextStyle(color: Ym.navy, fontWeight: FontWeight.w800)),
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
            if (!mounted) return;
            if (payload.eventType == PostgresChangeEvent.insert) {
              _showNewRegistrationPopup(payload.newRecord);
            }
            _fetchPendingRegistrations();
          },
        )
        .subscribe();
  }

  void _showNewRegistrationPopup(Map<String, dynamic> reg) {
    if (!mounted) return;
    final name = reg['student_name'] ?? 'Someone';
    final roleLabel = (reg['role'] ?? 'student').toString() == 'faculty' ? 'Faculty' : 'Student';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('New $roleLabel registration from $name'),
        backgroundColor: const Color(0xFF3B5BFF),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Review',
          textColor: Colors.white,
          onPressed: () async {
            await _fetchPendingRegistrations();
            final match = _pendingRegistrations.firstWhere(
              (r) => r['id'] == reg['id'],
              orElse: () => reg,
            );
            if (mounted) _openFormModal(null, match);
          },
        ),
      ),
    );
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
          .select('*, stops(stop_name)')
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              _sheetHeader('Announcements', Icons.campaign_rounded),
              Expanded(
                child: _announcements.isEmpty
                    ? const YmEmpty(
                        icon: Icons.campaign_outlined,
                        title: 'No announcements',
                        subtitle: 'Announcements from the admin appear here.')
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
                            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: Ym.shadow(),
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
                                        color: Ym.amber.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            targetRole == 'help_desk'
                                                ? Icons.support_agent_rounded
                                                : Icons.campaign_rounded,
                                            size: 12,
                                            color: Ym.amberDark,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            targetRole == 'all' ? 'Everyone' : 'Help Desk',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Ym.amberDark,
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  _sheetHeader('Pending Registrations', Icons.how_to_reg_rounded),
                  Expanded(
                    child: _pendingRegistrations.isEmpty
                        ? const YmEmpty(
                            icon: Icons.how_to_reg_outlined,
                            title: 'No pending registrations',
                            subtitle: 'New registrations from the form appear here.')
                        : ListView.builder(
                            itemCount: _pendingRegistrations.length,
                            itemBuilder: (context, index) {
                              final reg = _pendingRegistrations[index];
                              final regRole = (reg['role'] ?? 'student').toString();
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                                child: YmCard(
                                  padding: const EdgeInsets.all(14),
                                  radius: 20,
                                  onTap: () {
                                    Navigator.pop(context);
                                    _openFormModal(null, reg);
                                  },
                                  child: Row(
                                    children: [
                                      YmIconBadge(
                                        icon: regRole == 'faculty'
                                            ? Icons.badge_outlined
                                            : Icons.school_outlined,
                                        size: 44,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(reg['student_name'] ?? '', style: Ym.h(14.5)),
                                            const SizedBox(height: 3),
                                            Text(
                                              '${regRole == 'faculty' ? 'Faculty' : 'Student'} • ${reg['department'] ?? '—'}',
                                              style: Ym.t(12, color: Ym.grey),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if ((reg['payment_method'] ?? '').toString().toLowerCase() == 'cash') ...[
                                        const YmChip('Will pay cash',
                                            color: Ym.amberDark, icon: Icons.payments_outlined),
                                        const SizedBox(width: 6),
                                      ] else if ((reg['payment_reference'] ?? '').toString().isNotEmpty) ...[
                                        const YmChip('Payment sent',
                                            color: Ym.green, icon: Icons.payments_rounded),
                                        const SizedBox(width: 6),
                                      ],
                                      reg['wants_custom_stop'] == true
                                          ? const YmChip('Custom stop',
                                              color: Ym.amberDark,
                                              icon: Icons.location_off_outlined)
                                          : const Icon(Icons.chevron_right_rounded, color: Ym.grey),
                                    ],
                                  ),
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
      },
    );
  }

  /// how many payments parents have sent that still need checking
  Future<void> _fetchPaymentRequestCount() async {
    try {
      final n = await _supabase.rpc('pending_payment_request_count');
      if (mounted) setState(() => _paymentRequestCount = (n as num?)?.toInt() ?? 0);
    } catch (_) {
      // the button still works; it just shows no number
    }
  }

  Future<void> _openPaymentRequests() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PaymentRequestsScreen()),
    );
    if (mounted) _fetchPaymentRequestCount();
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
        await _fetchPaymentRequestCount();
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) {
        return SizedBox(
          height: 460,
          child: Column(
            children: [
              _sheetHeader('Notifications', Icons.notifications_active_outlined),
              Expanded(
                child: _notifications.isEmpty
                    ? const YmEmpty(
                        icon: Icons.notifications_none_rounded,
                        title: 'No notifications yet',
                        subtitle: 'Updates about your requests appear here.')
                    : ListView.builder(
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final n = _notifications[index];
                          final approved =
                              n['title'].toString().toLowerCase().contains('approved');
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: Ym.shadow(),
                                border: Border(
                                    left: BorderSide(
                                        color: approved ? Ym.green : Ym.red, width: 5)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(approved ? Icons.check_circle : Icons.cancel,
                                      color: approved ? Ym.green : Ym.red, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(n['title'] ?? '', style: Ym.h(14)),
                                        const SizedBox(height: 3),
                                        Text(n['message'] ?? '',
                                            style: Ym.t(12.5, color: Ym.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
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

  String _generateEnrollmentNo() {
    final now = DateTime.now();
    final rand = (1000 + Random().nextInt(9000)).toString();
    return 'STU${now.year}${now.month.toString().padLeft(2, '0')}$rand';
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

  /// the registration came with a UPI payment (with a reference) or a promise to pay cash
  bool get _hasRegPayment =>
      _reviewingPaymentAmount != null &&
      (_reviewingPaymentRef != null || (_reviewingPaymentMethod ?? '').toLowerCase() == 'cash');

  void _openFormModal([Map<String, dynamic>? student, Map<String, dynamic>? prefillFromRegistration]) {
    _editingStudent = student;
    _reviewingRegistrationId = prefillFromRegistration?['id'];
    _reviewingWantsCustomStop = prefillFromRegistration?['wants_custom_stop'];
    _reviewingCustomStopNote = prefillFromRegistration?['custom_stop_note'];
    _reviewingCustomStopLat = prefillFromRegistration?['custom_stop_lat'] != null
        ? double.tryParse(prefillFromRegistration!['custom_stop_lat'].toString())
        : null;
    _reviewingCustomStopLng = prefillFromRegistration?['custom_stop_lng'] != null
        ? double.tryParse(prefillFromRegistration!['custom_stop_lng'].toString())
        : null;
    _reviewingRole = prefillFromRegistration?['role'] ?? 'student';
    _reviewingPaymentAmount = prefillFromRegistration?['payment_amount'] != null
        ? double.tryParse(prefillFromRegistration!['payment_amount'].toString())
        : null;
    _reviewingPaymentRef = (prefillFromRegistration?['payment_reference'] ?? '').toString().trim().isEmpty
        ? null
        : prefillFromRegistration!['payment_reference'].toString().trim();
    _reviewingPaymentMethod = (prefillFromRegistration?['payment_method'] ?? '').toString().trim().isEmpty
        ? null
        : prefillFromRegistration!['payment_method'].toString().trim();
    _reviewingRegCode = (prefillFromRegistration?['registration_code'] ?? '').toString().trim().isEmpty
        ? null
        : prefillFromRegistration!['registration_code'].toString().trim();
    final reg = prefillFromRegistration;
    String rawFee = student?['fee_status'] ?? 'unpaid';
    String rawRelation = student?['parent_relation'] ?? reg?['parent_relation'] ?? 'father';

    _studentName = student?['student_name'] ?? reg?['student_name'] ?? '';
    _usnCollegeId = student?['enrollment_no'] ?? _generateEnrollmentNo();
    _studentEmail = student?['student_email'] ?? reg?['student_email'] ?? '';
    _studentPhone = student?['student_phone'] ?? reg?['student_phone'] ?? '';
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
    _boardingPoint = student?['boarding_point'] ??
        reg?['stops']?['stop_name'] ??
        (reg?['wants_custom_stop'] == true ? (reg?['custom_stop_note'] ?? 'Custom stop requested') : '') ??
        '';

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              title: Text(
                _reviewingRole == 'faculty'
                    ? (_editingStudent != null ? 'Edit Faculty' : 'New Faculty')
                    : (_editingStudent != null ? 'Edit Profile' : 'New Enrollment'),
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
                        if (_reviewingRegistrationId != null && _reviewingRegCode != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text('Registration number: $_reviewingRegCode',
                                style: Ym.t(12.5, color: Ym.grey, w: FontWeight.w700)),
                          ),
                        if (_reviewingRegistrationId != null && _hasRegPayment)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Ym.amber.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Ym.amber.withOpacity(0.6)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(Icons.payments_rounded, color: Ym.amberDark, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                      (_reviewingPaymentMethod ?? '').toLowerCase() == 'cash'
                                          ? 'Will pay cash at the help desk'
                                          : 'Payment sent with this registration',
                                      style: Ym.h(13.5)),
                                ]),
                                const SizedBox(height: 8),
                                Text(
                                  (_reviewingPaymentMethod ?? '').toLowerCase() == 'cash'
                                      ? '\u20B9${(_reviewingPaymentAmount ?? 0).round()}   \u2022   Cash'
                                      : '\u20B9${(_reviewingPaymentAmount ?? 0).round()}   \u2022   Ref $_reviewingPaymentRef',
                                  style: Ym.h(16),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  (_reviewingPaymentMethod ?? '').toLowerCase() == 'cash'
                                      ? 'When you save this student, a CASH request goes to Payment requests. '
                                          'Approve it there when the cash is handed over.'
                                      : 'When you save this student, the payment goes to Payment requests. '
                                          'Check it against the UPI / bank statement there, then approve it.',
                                  style: Ym.t(12, color: Ym.grey).copyWith(height: 1.45),
                                ),
                              ],
                            ),
                          ),
                        _sectionHeader('Core Info'),
                        if (_reviewingRole != 'faculty')
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
                        _buildInputField(_reviewingRole == 'faculty' ? 'Employee ID' : 'USN / ID Card', _usnCollegeId, (v) => _usnCollegeId = v!, required: true),
                        _buildInputField(
                          _reviewingRole == 'faculty' ? 'Email' : 'Email (optional if student has none)',
                          _studentEmail,
                          (v) => _studentEmail = v!,
                          required: _reviewingRole == 'faculty',
                          isEmail: true,
                        ),
                        _buildInputField('Phone Number (optional)', _studentPhone, (v) => _studentPhone = v!, required: false),
                        if (_reviewingRole == 'faculty') ...[
                          _buildInputField('Department', _studentDepartment, (v) => _studentDepartment = v!, required: true),
                        ] else ...[
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
                        ],
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
                                  icon: const Icon(Icons.send_rounded, size: 12, color: Ym.navy),
                                  label: const Text(
                                    'Request Stop Mapping Approval',
                                    style: TextStyle(fontSize: 11, color: Ym.navy, fontWeight: FontWeight.w800),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Ym.amber,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    minimumSize: const Size(double.infinity, 36),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_reviewingRole != 'faculty')
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Fee status is automatic. Use the payment button on the student card to record a payment.',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
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
                    backgroundColor: Ym.amber,
                    foregroundColor: Ym.navy,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      _formKey.currentState!.save();

                      try {
                        if (_reviewingRole == 'faculty') {
                          final facultyPayload = {
                            'institution_id': _currentInstitutionId,
                            'faculty_name': _studentName,
                            'employee_id': _usnCollegeId.trim().isEmpty ? null : _usnCollegeId.trim(),
                            'faculty_email': _studentEmail.trim(),
                            'faculty_phone': _studentPhone,
                            'department': _studentDepartment,
                            'boarding_point': _boardingPoint.isEmpty ? null : _boardingPoint,
                            // the stop and route chosen in the registration (as for students)
                            'route_id': reg?['suggested_route_id'] ?? _editingStudent?['route_id'],
                            'stop_id': reg?['suggested_stop_id'] ?? _editingStudent?['stop_id'],
                          };
                          if (_editingStudent != null) {
                            await _supabase.from('faculty').update(facultyPayload).eq('id', _editingStudent!['id']);
                            _showSnack('Faculty profile updated successfully', isError: false);
                          } else {
                            await _supabase.from('faculty').insert([facultyPayload]);
                            _showSnack('Faculty profile created successfully', isError: false);
                          }
                        } else {
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
                            'route_id': reg?['suggested_route_id'] ?? _editingStudent?['route_id'],
                            'stop_id': reg?['suggested_stop_id'] ?? _editingStudent?['stop_id'],
                          };
                          if (_editingStudent != null) {
                            await _supabase.from('students').update(payload).eq('id', _editingStudent!['id']);
                            _showSnack('Profile updated successfully', isError: false);
                          } else {
                            final created =
                                await _supabase.from('students').insert([payload]).select('id').single();
                            _showSnack('Profile created successfully', isError: false);

                            // a payment sent with the registration goes to Payment requests,
                            // to be verified and approved like any other payment
                            if (_hasRegPayment) {
                              try {
                                await _supabase.rpc('queue_registration_payment', params: {
                                  'p_student': created['id'],
                                  'p_amount': _reviewingPaymentAmount,
                                  'p_reference': _reviewingPaymentRef,
                                  'p_method': (_reviewingPaymentMethod ?? '').toLowerCase() == 'cash'
                                      ? 'Cash'
                                      : 'UPI',
                                });
                                _showSnack(
                                    (_reviewingPaymentMethod ?? '').toLowerCase() == 'cash'
                                        ? 'The cash payment is waiting in Payment requests. Approve it when the cash arrives.'
                                        : 'The payment sent with the registration is waiting in Payment requests.',
                                    isError: false);
                              } on PostgrestException catch (e) {
                                _showSnack('Student saved, but the payment was not queued: ${e.message}');
                              } catch (e) {
                                _showSnack('Student saved, but the payment was not queued: $e');
                              }
                            }
                          }
                        }

                        if (_reviewingRegistrationId != null) {
                          // NOTE: no route_requests insert here anymore. When
                          // the student originally submitted this form with
                          // "wants_custom_stop" set, the self-registration
                          // screen already created the pending route_requests
                          // row (with the custom lat/lng) at submission time —
                          // it's already sitting in the admin's Pending Route
                          // Requests list. Re-inserting it here on approval
                          // was creating a second, duplicate request for the
                          // same stop.
                          await _supabase.from('pending_enrollments').delete().eq('id', _reviewingRegistrationId!);
                          _reviewingRegistrationId = null;
                          _reviewingWantsCustomStop = null;
                          _reviewingCustomStopNote = null;
                          _reviewingCustomStopLat = null;
                          _reviewingCustomStopLng = null;
                          _reviewingRole = 'student';
                          _reviewingPaymentAmount = null;
                          _reviewingPaymentRef = null;
                          _reviewingPaymentMethod = null;
                          _reviewingRegCode = null;
                        }

                        if (context.mounted) Navigator.pop(context);
                        _loadDashboardData();
                      } catch (e) {
                        _showSnack('Error saving profile: $e');
                      }
                    }
                  },
                  child: const Text('Save Changes', style: TextStyle(color: Ym.navy, fontWeight: FontWeight.w800)),
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
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Ym.amberDark, letterSpacing: 0.6),
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
          labelStyle: const TextStyle(fontSize: 12, color: Ym.grey),
          filled: true,
          fillColor: const Color(0xFFF8F9FB),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Ym.amber, width: 1.6)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          labelStyle: const TextStyle(fontSize: 12, color: Ym.grey),
          filled: true,
          fillColor: const Color(0xFFF8F9FB),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Ym.amber, width: 1.6)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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

  // ───────────────────────── UI (Yatra Mitra theme) ─────────────────────────

  /// Handle + title used at the top of every pop-up sheet.
  Widget _sheetHeader(String title, IconData icon) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4.5,
              decoration: BoxDecoration(
                  color: Ym.line, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                YmIconBadge(icon: icon, size: 42),
                const SizedBox(width: 12),
                Text(title, style: Ym.h(20)),
              ],
            ),
          ],
        ),
      );

  Widget _hdCount(int n, Color c) => Container(
        constraints: const BoxConstraints(minWidth: 18),
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(9)),
        child: Text(n > 99 ? '99+' : '$n',
            style: Ym.t(10, color: Colors.white, w: FontWeight.w800)),
      );

  Widget _hdPill(String label, IconData icon, VoidCallback onTap, {int badge = 0}) =>
      YmPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Ym.amber.withOpacity(0.45)),
            boxShadow: Ym.shadow(Ym.amberDark, 0.1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Ym.amberDark),
              const SizedBox(width: 7),
              Text(label, style: Ym.t(12.5, w: FontWeight.w700)),
              if (badge > 0) ...[
                const SizedBox(width: 7),
                _hdCount(badge, Ym.amberDark),
              ],
            ],
          ),
        ),
      );

  Widget _hdHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        children: [
          Row(
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
                      roleLabel: 'Help Desk', onLogout: _handleLogout),
                  child: const CircleAvatar(
                    radius: 21,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.support_agent_rounded,
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
                    Text('Help Desk', style: Ym.t(11.5, color: Ym.grey, w: FontWeight.w600)),
                  ],
                ),
              ),
              YmRoundButton(
                  icon: Iconsax.notification,
                  badge: _unreadCount,
                  onTap: _showNotificationsSheet),
              const SizedBox(width: 10),
              YmRoundButton(icon: Iconsax.logout, color: Ym.red, onTap: _handleLogout),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _hdPill('Registrations', Icons.how_to_reg_outlined,
                    _showPendingRegistrationsSheet,
                    badge: _pendingRegistrations.length),
                const SizedBox(width: 8),
                _hdPill('Payment requests', Icons.payments_outlined,
                    _openPaymentRequests,
                    badge: _paymentRequestCount),
                const SizedBox(width: 8),
                _hdPill('Announcements', Icons.campaign_outlined, _showAnnouncementsSheet,
                    badge: _announcements.length),
                const SizedBox(width: 8),
                _hdPill('Share link', Icons.share_outlined, _showRegistrationLinkDialog),
                const SizedBox(width: 8),
                _hdPill('Refresh', Icons.refresh_rounded, _loadDashboardData),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hdTabs() => Container(
        margin: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: Ym.shadow(Ym.navy, 0.06),
        ),
        child: TabBar(
          controller: _tabController,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(colors: [Ym.amber, Ym.amberDark]),
          ),
          labelColor: Ym.navy,
          unselectedLabelColor: Ym.grey,
          labelStyle: Ym.h(13, w: FontWeight.w800),
          unselectedLabelStyle: Ym.t(13, w: FontWeight.w600),
          tabs: [
            Tab(text: 'Students (${_students.length})'),
            Tab(text: 'System Routes (${_routesWithStops.length})'),
          ],
        ),
      );

  Widget _hdStat(String value, String label, IconData icon, Color color) => Expanded(
        child: YmCard(
          padding: const EdgeInsets.symmetric(vertical: 12),
          radius: 20,
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 6),
              Text(value, style: Ym.h(19)),
              Text(label, style: Ym.t(11, color: Ym.grey)),
            ],
          ),
        ),
      );

  Widget _hdAction(String label, IconData icon, Color color, VoidCallback onTap) =>
      Expanded(
        child: YmPressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            // icon above the word, so four buttons always fit side by side
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, style: Ym.t(11.5, color: color, w: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _hdStudentCard(Map<String, dynamic> student, int index) {
    final fee = (student['fee_status'] ?? 'unpaid').toString().toLowerCase();
    final feeColor = fee == 'paid' ? Ym.green : (fee == 'partial' ? Ym.amberDark : Ym.red);
    final name = (student['student_name'] ?? '').toString();
    final stop = student['boarding_point']?.toString();
    final hasStop = stop != null && stop.isNotEmpty;

    return YmFadeSlide(
      index: index > 6 ? 6 : index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: YmCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Ym.amber, Ym.amberDark],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                        style: Ym.h(19, color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: Ym.h(15.5)),
                        const SizedBox(height: 3),
                        Text('USN: ${student['enrollment_no'] ?? ''}',
                            style: Ym.t(12, color: Ym.grey, w: FontWeight.w600)),
                      ],
                    ),
                  ),
                  YmChip(_capitalize(student['fee_status']), color: feeColor),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if ((student['department'] ?? '').toString().isNotEmpty)
                    YmChip(student['department'].toString(),
                        color: Ym.blue, icon: Icons.apartment_rounded),
                  if ((student['year'] ?? '').toString().isNotEmpty)
                    YmChip(student['year'].toString(),
                        color: Ym.purple, icon: Icons.school_outlined),
                  YmChip(hasStop ? stop : 'Stop pending assignment',
                      color: hasStop ? Ym.green : Ym.amberDark,
                      icon: Icons.location_on_outlined),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _hdAction('Payment', Icons.payments_outlined, Ym.green,
                      () => showRecordPaymentSheet(context, student, onDone: _loadDashboardData)),
                  const SizedBox(width: 6),
                  _hdAction('Edit', Icons.edit_outlined, Ym.blue, () => _openFormModal(student)),
                  const SizedBox(width: 6),
                  _hdAction('Card', Icons.contactless_outlined, Ym.purple,
                      () => showLinkRfidSheet(context, student, onDone: _loadDashboardData)),
                  const SizedBox(width: 6),
                  _hdAction('Delete', Icons.delete_outline_rounded, Ym.red,
                      () => _handleDelete(student['id'])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hdStudentsTab() {
    final paid = _students.where((s) => (s['fee_status'] ?? '').toString().toLowerCase() == 'paid').length;
    return RefreshIndicator(
      color: Ym.amber,
      onRefresh: _loadDashboardData,
      child: _students.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 60),
                YmEmpty(
                  icon: Icons.people_alt_outlined,
                  title: 'No profiles registered',
                  subtitle:
                      'Add a student with the button below, or share the registration link.',
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
              itemCount: _students.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        _hdStat('${_students.length}', 'Students', Icons.groups_rounded, Ym.blue),
                        const SizedBox(width: 10),
                        _hdStat('$paid', 'Fee paid', Icons.check_circle_rounded, Ym.green),
                        const SizedBox(width: 10),
                        _hdStat('${_students.length - paid}', 'Fee pending',
                            Icons.hourglass_bottom_rounded, Ym.amberDark),
                      ],
                    ),
                  );
                }
                return _hdStudentCard(_students[index - 1], index - 1);
              },
            ),
    );
  }

  Widget _hdRoutesTab() {
    if (_routesWithStops.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 60),
          YmEmpty(
            icon: Icons.route_rounded,
            title: 'No routes defined',
            subtitle: 'The admin adds routes and stops. They appear here.',
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
      itemCount: _routesWithStops.length,
      itemBuilder: (context, index) {
        final route = _routesWithStops[index];
        final stops = route['stops'] as List? ?? [];
        return YmFadeSlide(
          index: index > 6 ? 6 : index,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: Ym.shadow(),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                iconColor: Ym.grey,
                leading: const YmIconBadge(icon: Iconsax.bus, size: 44),
                title: Text(route['route_name'] ?? 'Unnamed Route', style: Ym.h(15)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: YmChip('${stops.length} stops',
                        color: Ym.blue, icon: Icons.pin_drop_outlined),
                  ),
                ),
                children: stops.map<Widget>((stop) {
                  String timeDisplay = '';
                  if (stop['timing'] != null) {
                    final rawTime = stop['timing'].toString();
                    timeDisplay = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 17, color: Ym.amberDark),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(stop['stop_name'] ?? '',
                              style: Ym.t(13, w: FontWeight.w600)),
                        ),
                        if (timeDisplay.isNotEmpty)
                          YmChip(timeDisplay, color: Ym.navy, icon: Icons.access_time_rounded),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
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
        backgroundColor: Ym.creamTop,
        body: YmBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _hdHeader(),
                _hdTabs(),
                Expanded(
                  child: _isLoading
                      ? const YmSkeletonList(count: 4, height: 110)
                      : TabBarView(
                          controller: _tabController,
                          children: [_hdStudentsTab(), _hdRoutesTab()],
                        ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: YmPressable(
          onTap: () => _openFormModal(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Ym.amber, Ym.amberDark]),
              borderRadius: BorderRadius.circular(24),
              boxShadow: Ym.shadow(Ym.amberDark, 0.4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_add_alt_1, color: Ym.navy, size: 21),
                const SizedBox(width: 9),
                Text('Add student', style: Ym.h(14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}