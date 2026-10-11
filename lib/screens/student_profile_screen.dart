import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'change_password_screen.dart';
import 'package:iconsax/iconsax.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'bus_pass_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Same palette as student_dashboard_screen.dart / admin dashboard.
class _C {
  static const bg = Color(0xFFFFF8F1);
  static const navy = Color(0xFF0F1B4D);
  static const orange = Color(0xFFFF9800);
  static const orangeSoft = Color(0xFFFFEFD9);
  static const grey = Color(0xFF8E94A9);
  static const green = Color(0xFF0E9F6E);
  static const red = Color(0xFFE53935);
  static const border = Color(0xFFF6E3C6);
}

/// Profile + Bus Pass.
/// Never fetches or shows a password (Supabase never exposes it anyway).
class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _uploading = false;
  String? _error;

  Map<String, dynamic>? _student;
  Map<String, dynamic>? _bus;
  Map<String, dynamic>? _route;
  Map<String, dynamic>? _stop;
  Map<String, dynamic>? _fee; // live yearly fee status (student_fee_status view)
  String? _photoUrl;

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
      final authUser = _supabase.auth.currentUser;
      if (authUser?.email == null) throw Exception('Not logged in.');

      final studentRow = await _supabase
          .from('students')
          .select(
            '*, buses(bus_number,bus_name), '
            'routes(route_name), stops(stop_name,timing)',
          )
          .eq('student_email', authUser!.email as Object)
          .maybeSingle();

      final profileRow = await _supabase
          .from('profiles')
          .select('photo')
          .eq('user_id', authUser.id)
          .maybeSingle();

      // Fee status for the CURRENT academic year, worked out live by the database.
      Map<String, dynamic>? feeRow;
      if (studentRow != null) {
        feeRow = await _supabase
            .from('student_fee_status')
            .select()
            .eq('student_id', studentRow['id'])
            .maybeSingle();
      }

      if (!mounted) return;
      setState(() {
        _fee = feeRow;
        _student = studentRow;
        _bus = studentRow?['buses'] as Map<String, dynamic>?;
        _route = studentRow?['routes'] as Map<String, dynamic>?;
        _stop = studentRow?['stops'] as Map<String, dynamic>?;
        _photoUrl = profileRow?['photo'] as String?;
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

  Future<void> _pickAndUploadPhoto() async {
    final authUser = _supabase.auth.currentUser;
    if (authUser == null) return;

    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true, // needed on web
    );
    if (result == null || result.files.single.bytes == null) return;

    final Uint8List bytes = result.files.single.bytes!;
    final path = '${authUser.id}.jpg';

    setState(() => _uploading = true);
    try {
      await _supabase.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions:
                const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );

      final url =
          '${_supabase.storage.from('avatars').getPublicUrl(path)}?t=${DateTime.now().millisecondsSinceEpoch}';

      await _supabase
          .from('profiles')
          .upsert({'user_id': authUser.id, 'photo': url});

      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _snack('Photo upload failed: $e');
    }
  }

  Future<void> _changePassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _C.navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _C.orange))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _C.grey)),
                    ),
                  )
                : RefreshIndicator(
                    color: _C.orange,
                    onRefresh: _load,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTopBar(),
                          const SizedBox(height: 18),
                          Center(child: _buildAvatar()),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              _student?['student_name']?.toString() ?? '',
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: _C.navy),
                            ),
                          ),
                          if (_student?['enrollment_no'] != null)
                            Center(
                              child: Text(
                                'USN: ${_student!['enrollment_no']}',
                                style: const TextStyle(
                                    color: _C.grey, fontSize: 13),
                              ),
                            ),
                          const SizedBox(height: 24),
                          _sectionTitle('Student Details'),
                          const SizedBox(height: 12),
                          _infoCard(),
                          const SizedBox(height: 24),
                          _sectionTitle('Bus Pass'),
                          const SizedBox(height: 12),
                          _buildBusPass(),
                          const SizedBox(height: 24),
                          _actionTile(Iconsax.key, 'Change Password',
                              _changePassword),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: const Icon(Icons.arrow_back_ios_new,
                size: 18, color: _C.navy),
          ),
        ),
        const SizedBox(width: 14),
        const Text('My Profile',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: _C.navy)),
      ],
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: _C.navy));

  BoxDecoration _cardDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      );

  Widget _buildAvatar() {
    final name = _student?['student_name']?.toString() ?? '';
    return Stack(
      children: [
        CircleAvatar(
          radius: 52,
          backgroundColor: _C.orangeSoft,
          backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
          child: _photoUrl == null
              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: _C.orange))
              : null,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: _uploading ? null : _pickAndUploadPhoto,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                  color: _C.orange, shape: BoxShape.circle),
              child: _uploading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.camera_alt_outlined,
                      size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoCard() {
    final s = _student ?? {};
    final rows = <(String, dynamic)>[
      ('Department', s['department']),
      ('Year', s['year']),
      ('Email', s['student_email']),
      ('Phone', s['student_phone']),
      ('Admission Date', s['admission_date']),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      decoration: _cardDeco(),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++)
            _row(rows[i].$1, rows[i].$2, isLast: i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _row(String label, dynamic value, {bool isLast = false}) {
    final display = (value == null || value.toString().isEmpty)
        ? 'Not available'
        : value.toString();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                  width: 120,
                  child: Text(label,
                      style: const TextStyle(color: _C.grey, fontSize: 13))),
              Expanded(
                child: Text(display,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _C.navy)),
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, color: _C.border),
      ],
    );
  }

  // ── Bus pass with QR ──

  Widget _buildBusPass() {
    if (_bus == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _cardDeco(),
        child: const Text(
          'Bus pass will appear once a bus is assigned to you.',
          style: TextStyle(color: _C.grey),
        ),
      );
    }

    // The pass exists only while the full fee of the current academic year is paid.
    final feeStatus = _fee?['fee_status']?.toString() ?? 'unpaid';
    final passValid = feeStatus == 'paid';
    final expiry = _fee?['valid_till']?.toString();
    final notActiveReason = switch (feeStatus) {
      'no_year' => 'Not active. No academic year is active right now.',
      'fee_not_set' => 'Not active. The fee for your route has not been set yet.',
      'partial' => 'Not active. Part of the fee is paid, the full fee is needed.',
      _ => 'Not active. The fee for this year is not paid.',
    };

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BusPassScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _cardDeco(),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: (passValid ? _C.green : _C.grey).withOpacity(0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.qr_code_2_rounded,
                  color: passValid ? _C.green : _C.grey, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bus Pass',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _C.navy)),
                  const SizedBox(height: 4),
                  Text(
                    passValid
                        ? 'Active  \u2022  valid till ${expiry ?? '-'}'
                        : notActiveReason,
                    style: TextStyle(
                        color: passValid ? _C.green : _C.red,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _C.grey),
          ],
        ),
      ),
    );
  }

  Widget _passLine(String k, String? v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: const TextStyle(fontSize: 11, color: _C.grey)),
            Text((v == null || v.isEmpty) ? '-' : v,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: _C.navy)),
          ],
        ),
      );

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: _C.orangeSoft,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: _C.orange, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: _C.navy)),
            ),
            const Icon(Icons.chevron_right, color: _C.grey),
          ],
        ),
      ),
    );
  }
}