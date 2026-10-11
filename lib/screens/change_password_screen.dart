import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/ym_ui.dart';

/// null when the password is acceptable, otherwise what is wrong.
/// The same rule is used when changing and when resetting a password.
String? passwordProblem(String pw) {
  if (pw.length < 8) return 'Use at least 8 characters.';
  if (!RegExp(r'[A-Za-z]').hasMatch(pw)) return 'Include at least one letter.';
  if (!RegExp(r'[0-9]').hasMatch(pw)) return 'Include at least one number.';
  return null;
}

/// Change the password while logged in. Used by every role (student, parent,
/// driver, help desk, admin).
///
/// The current password is asked for first. That proves it is really the owner
/// at the keyboard, not someone who picked up an unlocked phone.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _sb = Supabase.instance.client;
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// 0 = empty, 1 = weak, 2 = fair, 3 = strong
  int get _strength {
    final p = _new.text;
    if (p.isEmpty) return 0;
    var score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    if (score <= 1) return 1;
    if (score == 2) return 2;
    return 3;
  }

  Future<void> _save() async {
    final email = _sb.auth.currentUser?.email;
    final cur = _current.text;
    final pw = _new.text;

    if (email == null) {
      setState(() => _error = 'You are not logged in.');
      return;
    }
    if (cur.isEmpty) {
      setState(() => _error = 'Please enter your current password.');
      return;
    }
    final bad = passwordProblem(pw);
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    if (pw == cur) {
      setState(() => _error = 'The new password must be different from the current one.');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'The two new passwords do not match.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // prove the current password first
      try {
        await _sb.auth.signInWithPassword(email: email, password: cur);
      } on AuthException {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = 'Your current password is not correct.';
        });
        return;
      }
      await _sb.auth.updateUser(UserAttributes(password: pw));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Ym.green),
            const SizedBox(width: 10),
            Text('Password changed', style: Ym.h(18)),
          ]),
          content: Text('Use your new password the next time you log in.',
              style: Ym.t(13.5, color: Ym.grey)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('OK')),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is AuthException ? e.message : 'Could not change the password. $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _strength;
    final sColor = s == 3 ? Ym.green : (s == 2 ? Ym.amberDark : Ym.red);
    final sLabel = s == 3 ? 'Strong' : (s == 2 ? 'Fair' : (s == 1 ? 'Weak' : ''));

    return YmPage(
      title: 'Change password',
      subtitle: _sb.auth.currentUser?.email,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          YmCard(
            padding: const EdgeInsets.all(18),
            radius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field('Current password', _current, _showCurrent,
                    () => setState(() => _showCurrent = !_showCurrent)),
                const SizedBox(height: 16),
                _field('New password', _new, _showNew,
                    () => setState(() => _showNew = !_showNew),
                    onChanged: (_) => setState(() => _error = null)),
                if (_new.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var i = 1; i <= 3; i++)
                        Expanded(
                          child: Container(
                            height: 5,
                            margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                            decoration: BoxDecoration(
                              color: i <= s ? sColor : Ym.line,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      const SizedBox(width: 10),
                      Text(sLabel,
                          style: Ym.t(12, color: sColor, w: FontWeight.w800)),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Text('At least 8 characters, with a letter and a number.',
                    style: Ym.t(11.5, color: Ym.grey)),
                const SizedBox(height: 16),
                _field('Confirm new password', _confirm, _showNew,
                    () => setState(() => _showNew = !_showNew)),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: Ym.t(12.5, color: Ym.red)),
                ],
                const SizedBox(height: 18),
                YmButton(
                  label: 'Change password',
                  icon: Icons.lock_reset_rounded,
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, bool visible, VoidCallback toggle,
      {ValueChanged<String>? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Ym.t(12, color: Ym.grey, w: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          obscureText: !visible,
          onChanged: onChanged,
          style: Ym.t(14.5, w: FontWeight.w600),
          decoration: InputDecoration(
            filled: true,
            fillColor: Ym.creamTop,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                  visible ? Icons.visibility_rounded : Icons.visibility_off_outlined,
                  color: Ym.grey,
                  size: 20),
              onPressed: toggle,
            ),
          ),
        ),
      ],
    );
  }
}