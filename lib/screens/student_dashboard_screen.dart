import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../config/app_theme.dart';
import 'role_selection_screen.dart';
import 'student_profile_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() =>
      _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _student;
  Map<String, dynamic>? _bus;
  Map<String, dynamic>? _route;
  Map<String, dynamic>? _stop;
  Map<String, dynamic>? _driverProfile;
  String? _ownPhotoUrl;
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _announcements = [];

  int _currentTab = 0;
  late final VideoPlayerController _videoController;
  bool _videoReady = false;

  int get _unreadCount =>
      _notifications.where((n) => n['is_read'] == false).length;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _videoController =
        VideoPlayerController.asset('assets/images/student_dashboard_video.mp4')
          ..setLooping(true)
          ..setVolume(0)
          ..initialize().then((_) {
            if (!mounted) return;
            setState(() => _videoReady = true);
            _videoController.play();
          });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final authUser = _supabase.auth.currentUser;
      if (authUser?.email == null) {
        throw Exception('Not logged in.');
      }

      final studentRow = await _supabase
          .from('students')
          .select(
            '*, buses(bus_number,bus_name,status,driver_id), '
            'routes(route_name,start_point,end_point,timings), '
            'stops(stop_name,timing)',
          )
          .eq('student_email', authUser!.email as Object)
          .maybeSingle();

      if (studentRow == null) {
        throw Exception(
          'No student record found for ${authUser.email}. '
          'Check that student_email matches exactly.',
        );
      }

      // buses.driver_id and profiles.user_id both reference auth.users
      // independently, so there's no direct FK PostgREST can embed
      // through — fetch the driver's profile as a separate query.
      Map<String, dynamic>? driverProfile;
      final driverId = (studentRow['buses'] as Map<String, dynamic>?)?['driver_id'];
      if (driverId != null) {
        driverProfile = await _supabase
            .from('profiles')
            .select('full_name, photo')
            .eq('user_id', driverId)
            .maybeSingle();
      }

      final ownProfile = await _supabase
          .from('profiles')
          .select('photo')
          .eq('user_id', authUser.id)
          .maybeSingle();

      final notifRows = await _supabase
          .from('notifications')
          .select()
          .eq('recipient_id', authUser.id)
          .order('created_at', ascending: false)
          .limit(5);

      // Real data — announcements backend already exists from the
      // admin dashboard work, so this isn't a placeholder.
      final annRows = await _supabase
          .from('announcements')
          .select()
          .inFilter('target_role', ['all', 'student'])
          .order('created_at', ascending: false)
          .limit(3);

      if (!mounted) return;
      setState(() {
        _student = studentRow;
        _bus = studentRow['buses'] as Map<String, dynamic>?;
        _route = studentRow['routes'] as Map<String, dynamic>?;
        _stop = studentRow['stops'] as Map<String, dynamic>?;
        _driverProfile = driverProfile;
        _ownPhotoUrl = ownProfile?['photo'] as String?;
        _notifications = List<Map<String, dynamic>>.from(notifRows);
        _announcements = List<Map<String, dynamic>>.from(annRows);
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

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming soon — backend not built yet.'),
        backgroundColor: AppTheme.textPrimary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You\'ll need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StudentProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: _buildDrawer(),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : RefreshIndicator(
                    onRefresh: _loadDashboard,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTopBar(),
                          const SizedBox(height: 16),
                          _buildGreeting(),
                          const SizedBox(height: 18),
                          _buildBusStatusCard(),
                          const SizedBox(height: 18),
                          _buildQuickActionsRow(),
                          const SizedBox(height: 18),
                          _buildTodaysJourneyCard(),
                          const SizedBox(height: 18),
                          _buildGeofenceAlertsSection(),
                          const SizedBox(height: 18),
                          _buildAnnouncementsSection(),
                        ],
                      ),
                    ),
                  ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.warning_2, size: 40, color: AppTheme.statusRed),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDashboard,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryYellow,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppTheme.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Yatra Mitra', style: AppTheme.heading(18)),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Iconsax.user, color: AppTheme.textPrimary),
              title: const Text('My Profile'),
              onTap: () {
                Navigator.pop(context);
                _openProfile();
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.statusRed),
              title: const Text('Log out',
                  style: TextStyle(color: AppTheme.statusRed)),
              onTap: () {
                Navigator.pop(context);
                _handleLogout();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Builder(
      builder: (context) => Row(
        children: [
          IconButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Iconsax.menu, color: AppTheme.textPrimary),
          ),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: () {
                  setState(() => _currentTab = 2);
                  _comingSoon('Notifications');
                },
                icon: const Icon(Iconsax.notification, color: AppTheme.textPrimary),
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.sosRed,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _openProfile,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.primaryYellow.withOpacity(0.2),
              backgroundImage:
                  _ownPhotoUrl != null ? NetworkImage(_ownPhotoUrl!) : null,
              child: _ownPhotoUrl == null
                  ? Text(
                      (_student?['student_name']?.toString().isNotEmpty ?? false)
                          ? _student!['student_name'][0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: AppTheme.primaryYellowDark,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting() {
    final name = _student?['student_name']?.toString() ?? 'Student';
    final firstName = name.split(' ').first;
    final dept = _student?['department'];
    final year = _student?['year'];
    final usn = _student?['enrollment_no'];
    final infoLine = [
      if (dept != null) dept.toString(),
      if (year != null) year.toString(),
    ].join(' — ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hello, $firstName 👋', style: AppTheme.heading(24)),
        if (infoLine.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(infoLine,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
        if (usn != null)
          Text('USN: $usn',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      ],
    );
  }

  // Status label is a real mapping of buses.status — not a fabricated
  // live ETA. "On Time" only shows when the bus's stored status is
  // actually 'active'.
  Widget _buildBusStatusCard() {
    final busStatus = _bus?['status'];
    final routeName = _route?['route_name'];

    String title;
    String subtitle;
    Color titleColor;

    if (_bus == null && routeName != null) {
      title = 'Bus not assigned';
      subtitle = 'Route: $routeName';
      titleColor = AppTheme.textMuted;
    } else if (_bus == null) {
      title = 'No route assigned';
      subtitle = 'Contact your institution to get assigned';
      titleColor = AppTheme.textMuted;
    } else if (busStatus == 'active') {
      title = 'On Time';
      subtitle = 'Bus is running as per schedule';
      titleColor = AppTheme.statusGreen;
    } else if (busStatus == 'maintenance') {
      title = 'Under Maintenance';
      subtitle = 'This bus is temporarily out of service';
      titleColor = AppTheme.statusRed;
    } else {
      title = 'Inactive';
      subtitle = 'This bus is not currently running';
      titleColor = AppTheme.textMuted;
    }

    return Container(
      width: double.infinity,
      height: 190,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryYellow.withOpacity(0.30),
            AppTheme.primaryYellow.withOpacity(0.08),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_videoReady)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoController.value.size.width,
                height: _videoController.value.size.height,
                child: VideoPlayer(_videoController),
              ),
            )
          else
            Center(
              child: Icon(
                Icons.videocam_outlined,
                size: 34,
                color: AppTheme.primaryYellowDark.withOpacity(0.35),
              ),
            ),
          // Scrim behind the text so it stays readable over whatever
          // the video shows at that moment.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.35),
                  Colors.black.withOpacity(0.55),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 18,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Your Bus Status',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: titleColor == AppTheme.textMuted
                        ? Colors.white.withOpacity(0.9)
                        : titleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    final actions = <_QuickAction>[
      _QuickAction(Iconsax.tick_circle, 'Mark Absent',
          const Color(0xFF6C5CE7), const Color(0xFFEDE9FE)),
      _QuickAction(Iconsax.document_text, 'Complaints',
          AppTheme.accentOrange, const Color(0xFFFFF0DC)),
      _QuickAction(null, 'Emergency SOS', Colors.white, AppTheme.sosRed,
          textIcon: 'SOS'),
      _QuickAction(null, 'Bus Pass', AppTheme.statusBlue,
          const Color(0xFFE1ECFF), materialIcon: Icons.badge_outlined),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: AppTheme.cardDecoration(),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (int i = 0; i < actions.length; i++) ...[
              if (i != 0)
                const VerticalDivider(width: 1, color: AppTheme.border),
              Expanded(child: _quickActionTile(actions[i])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _quickActionTile(_QuickAction a) {
    return InkWell(
      onTap: () => _comingSoon(a.label),
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: a.bgColor, shape: BoxShape.circle),
            child: Center(
              child: a.textIcon != null
                  ? Text(
                      a.textIcon!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : a.materialIcon != null
                      ? Icon(a.materialIcon, color: a.color, size: 22)
                      : Icon(a.icon, color: a.color, size: 22),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            a.label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTodaysJourneyCard() {
    final stopName = _stop?['stop_name'];
    final stopTiming = _stop?['timing'];
    final endPoint = _route?['end_point'];
    final driverName = _driverProfile?['full_name'];
    final driverPhoto = _driverProfile?['photo'] as String?;
    final hasDriver = _bus?['driver_id'] != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's Journey", style: AppTheme.heading(16)),
          const SizedBox(height: 14),

          // Driver row
          if (!hasDriver)
            const Text('No driver assigned yet',
                style: TextStyle(color: AppTheme.textMuted))
          else
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryYellow.withOpacity(0.15),
                  backgroundImage:
                      driverPhoto != null ? NetworkImage(driverPhoto) : null,
                  child: driverPhoto == null
                      ? const Icon(Iconsax.user,
                          color: AppTheme.primaryYellowDark, size: 20)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Driver',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textMuted)),
                      Text(
                        driverName ?? 'Name not available yet',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                _circleIconButton(Icons.call, () => _comingSoon('Calling driver')),
                const SizedBox(width: 8),
                _circleIconButton(Icons.chat_bubble_outline, () => _comingSoon('Messaging driver')),
              ],
            ),

          const Divider(height: 28, color: AppTheme.border),

          // Timeline
          if (stopName != null)
            _timelineRow(
              color: AppTheme.statusGreen,
              label: 'Boarding Stop',
              value: stopName,
              trailing: stopTiming?.toString(),
            ),
          _timelineRow(
            color: AppTheme.statusBlue,
            label: 'Current Stop',
            value: 'Live tracking coming soon',
            trailing: null,
            muted: true,
          ),
          if (endPoint != null)
            _timelineRow(
              color: AppTheme.textMuted,
              label: 'Drop Stop',
              value: endPoint,
              trailing: null,
              isLast: true,
            ),

          const SizedBox(height: 16),

          // Map placeholder — real stop coordinates exist in the schema
          // (stops.lat/lng), so a real mini-map is a reasonable next
          // step once live bus position is available too.
          Container(
            width: double.infinity,
            height: 130,
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined, color: AppTheme.textMuted, size: 26),
                  SizedBox(height: 6),
                  Text('Live map coming soon',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _comingSoon('Full route view'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryYellowDark,
                side: const BorderSide(color: AppTheme.primaryYellow),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('View Full Route'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppTheme.statusBlue.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: AppTheme.statusBlue),
      ),
    );
  }

  Widget _timelineRow({
    required Color color,
    required String label,
    required String value,
    String? trailing,
    bool muted = false,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(Iconsax.location, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: muted ? AppTheme.textMuted : color,
                    )),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: muted ? FontWeight.normal : FontWeight.w600,
                    color: muted ? AppTheme.textMuted : AppTheme.textPrimary,
                    fontStyle: muted ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Text(trailing, style: const TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildGeofenceAlertsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryYellow.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.notification, size: 18, color: AppTheme.primaryYellowDark),
              const SizedBox(width: 6),
              Text('Geofence Alerts', style: AppTheme.heading(14)),
              const Spacer(),
              GestureDetector(
                onTap: () => _comingSoon('Geofence alerts'),
                child: const Text('View All',
                    style: TextStyle(color: AppTheme.primaryYellowDark, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Alerts will appear here once live bus tracking is enabled.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.statusBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_outlined, size: 18, color: AppTheme.statusBlue),
              const SizedBox(width: 6),
              Text('Announcements', style: AppTheme.heading(14)),
              const Spacer(),
              GestureDetector(
                onTap: () => _comingSoon('Full announcements list'),
                child: const Text('View All',
                    style: TextStyle(color: AppTheme.statusBlue, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_announcements.isEmpty)
            const Text('No announcements yet',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5))
          else
            ..._announcements.map((a) => _announcementTile(a)),
        ],
      ),
    );
  }

  Widget _announcementTile(Map<String, dynamic> a) {
    final createdAt = DateTime.tryParse(a['created_at']?.toString() ?? '');
    final dateLabel = createdAt != null
        ? '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/bus.png',
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a['title'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(
                  a['body'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                if (dateLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(dateLabel,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentTab,
      selectedItemColor: AppTheme.primaryYellowDark,
      unselectedItemColor: AppTheme.textMuted,
      type: BottomNavigationBarType.fixed,
      onTap: (i) {
        setState(() => _currentTab = i);
        if (i != 0) {
          const labels = ['Dashboard', 'Live Bus', 'Notifications', 'History'];
          _comingSoon(labels[i]);
        }
      },
      items: [
        const BottomNavigationBarItem(icon: Icon(Iconsax.home), label: 'Dashboard'),
        const BottomNavigationBarItem(icon: Icon(Iconsax.bus), label: 'Live Bus'),
        BottomNavigationBarItem(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Iconsax.notification),
              if (_unreadCount > 0)
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: AppTheme.sosRed,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          label: 'Notifications',
        ),
        const BottomNavigationBarItem(icon: Icon(Iconsax.clock), label: 'History'),
      ],
    );
  }
}

/// Plain data holder for a quick-action tile. Either `icon` (Iconsax),
/// `materialIcon` (Icons.*), or `textIcon` (a short string like "SOS")
/// is provided — never more than one.
class _QuickAction {
  final IconData? icon;
  final IconData? materialIcon;
  final String? textIcon;
  final String label;
  final Color color;
  final Color bgColor;
  const _QuickAction(this.icon, this.label, this.color, this.bgColor,
      {this.materialIcon, this.textIcon});
}