import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';

/// Read-only credential display + photo upload.
/// Deliberately never fetches or displays a password field — Supabase
/// Auth never exposes the plaintext password to the client anyway, so
/// there's nothing to accidentally leak here.
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
          .select()
          .eq('student_email', authUser!.email as Object)
          .maybeSingle();

      final profileRow = await _supabase
          .from('profiles')
          .select('photo')
          .eq('user_id', authUser.id)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _student = studentRow;
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
      withData: true, // required for web — need raw bytes, not just a path
    );
    if (result == null || result.files.single.bytes == null) return;

    final Uint8List bytes = result.files.single.bytes!;
    final path = '${authUser.id}.jpg';

    setState(() => _uploading = true);
    try {
      await _supabase.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      // Cache-bust so the new photo shows immediately instead of the
      // browser serving a cached copy of the old one at the same URL.
      final url =
          '${_supabase.storage.from('avatars').getPublicUrl(path)}?t=${DateTime.now().millisecondsSinceEpoch}';

      await _supabase.from('profiles').upsert({
        'user_id': authUser.id,
        'photo': url,
      });

      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo upload failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Text('My Profile', style: AppTheme.heading(18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: AppTheme.textSecondary)),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildAvatar(),
                      const SizedBox(height: 24),
                      _infoCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildAvatar() {
    final name = _student?['student_name']?.toString() ?? '';
    return Stack(
      children: [
        CircleAvatar(
          radius: 48,
          backgroundColor: AppTheme.primaryYellow.withOpacity(0.15),
          backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
          child: _photoUrl == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryYellowDark,
                  ),
                )
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
                color: AppTheme.primaryYellow,
                shape: BoxShape.circle,
              ),
              child: _uploading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.camera_alt_outlined, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoCard() {
    final s = _student ?? {};
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Full Name', s['student_name']),
          _row('Email', s['student_email']),
          _row('Phone', s['student_phone']),
          _row('Department', s['department']),
          _row('Year', s['year']),
          _row('Enrollment No', s['enrollment_no']),
          _row('Admission Date', s['admission_date']),
        ],
      ),
    );
  }

  Widget _row(String label, dynamic value) {
    final display = (value == null || value.toString().isEmpty)
        ? 'Not available'
        : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5, color: AppTheme.textMuted)),
          const SizedBox(height: 2),
          Text(display,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              )),
          const Divider(height: 18, color: AppTheme.border),
        ],
      ),
    );
  }
}