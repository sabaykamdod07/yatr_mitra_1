import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/ym_ui.dart';
import 'change_password_screen.dart';

/// Forgot password, for everyone who is not logged in.
///
///   1. enter your email           -> a code is emailed (6 to 10 digits, as set in Supabase)
///   2. enter the code + a new password
///   3. done, go back and log in
///
/// The same message is shown whether or not the email has an account, so nobody
/// can use this screen to find out who is registered. The code is checked by
/// Supabase and expires.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _sb = Supabase.instance.client;
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  int _step = 0; // 0 email, 1 code + password, 2 done
  bool _busy = false;
  bool _show = false;
  String? _error;

  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) t.cancel();
    });
  }

  bool _validEmail(String e) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e);

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!_validEmail(email)) {
      setState(() => _error = 'Please enter the email address of your account.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _sb.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = 1;
      });
      _startCooldown();
    } on AuthException catch (e) {
      if (!mounted) return;
      final wait = e.message.toLowerCase().contains('seconds') ||
          e.message.toLowerCase().contains('rate');
      setState(() {
        _busy = false;
        _error = wait
            ? 'Please wait a minute before asking for another code.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not send the code. Please try again.';
      });
    }
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    final code = _code.text.trim();
    final pw = _new.text;

    if (code.length < 6) {
      setState(() => _error = 'Enter the full code from the email.');
      return;
    }
    final bad = passwordProblem(pw);
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _sb.auth.verifyOTP(email: email, token: code, type: OtpType.recovery);
      await _sb.auth.updateUser(UserAttributes(password: pw));
      await _sb.auth.signOut(); // log in again with the new password
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = 2;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      setState(() {
        _busy = false;
        _error = (m.contains('expired') || m.contains('invalid'))
            ? 'That code is wrong or has expired. Check the latest email, or ask for a new code.'
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reset the password. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return YmPage(
      title: 'Forgot password',
      subtitle: _step == 0
          ? 'We will email you a code'
          : _step == 1
              ? 'Enter the code and a new password'
              : 'All done',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          YmCard(
            padding: const EdgeInsets.all(20),
            radius: 26,
            child: _step == 0 ? _emailStep() : (_step == 1 ? _codeStep() : _doneStep()),
          ),
        ],
      ),
    );
  }

  // ── step 0 ──
  Widget _emailStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const YmIconBadge(icon: Icons.mail_lock_rounded, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Enter the email address you use to log in. We will send a code to it.',
                style: Ym.t(13, color: Ym.grey).copyWith(height: 1.45),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          _label('Email address'),
          _box(_email,
              hint: 'you@example.com',
              keyboard: TextInputType.emailAddress,
              onChanged: (_) => setState(() => _error = null)),
          _errorText(),
          const SizedBox(height: 16),
          YmButton(
            label: 'Send code',
            icon: Icons.send_rounded,
            loading: _busy,
            onPressed: _sendCode,
          ),
        ],
      );

  // ── step 1 ──
  Widget _codeStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Ym.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.mark_email_read_rounded, color: Ym.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'If ${_email.text.trim()} has an account, a code is on its way. It can take a minute. Check spam too.',
                  style: Ym.t(12.5).copyWith(height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          _label('Code from the email'),
          _box(_code,
              hint: '12345678',
              keyboard: TextInputType.number,
              maxLength: 10,
              formatters: [FilteringTextInputFormatter.digitsOnly],
              big: true,
              onChanged: (_) => setState(() => _error = null)),
          const SizedBox(height: 4),
          _label('New password'),
          _box(_new,
              hint: 'At least 8 characters, with a letter and a number',
              obscure: !_show,
              onChanged: (_) => setState(() => _error = null),
              suffix: IconButton(
                icon: Icon(
                    _show ? Icons.visibility_rounded : Icons.visibility_off_outlined,
                    color: Ym.grey,
                    size: 20),
                onPressed: () => setState(() => _show = !_show),
              )),
          const SizedBox(height: 14),
          _label('Confirm new password'),
          _box(_confirm, hint: 'Type it again', obscure: !_show),
          _errorText(),
          const SizedBox(height: 16),
          YmButton(
            label: 'Reset password',
            icon: Icons.lock_reset_rounded,
            loading: _busy,
            onPressed: _reset,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: (_cooldown > 0 || _busy) ? null : _sendCode,
              child: Text(
                _cooldown > 0 ? 'Send a new code in ${_cooldown}s' : 'Send a new code',
                style: Ym.t(13,
                    color: _cooldown > 0 ? Ym.grey : Ym.amberDark, w: FontWeight.w800),
              ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => setState(() => _step = 0),
              child: Text('Use a different email',
                  style: Ym.t(12.5, color: Ym.grey, w: FontWeight.w700)),
            ),
          ),
        ],
      );

  // ── step 2 ──
  Widget _doneStep() => Column(
        children: [
          const SizedBox(height: 6),
          const YmIconBadge(icon: Icons.check_circle_rounded, color: Ym.green, size: 64),
          const SizedBox(height: 14),
          Text('Password changed', style: Ym.h(21)),
          const SizedBox(height: 6),
          Text('You can now log in with your new password.',
              textAlign: TextAlign.center, style: Ym.t(13.5, color: Ym.grey)),
          const SizedBox(height: 20),
          YmButton(
            label: 'Back to login',
            icon: Icons.login_rounded,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );

  // ── small pieces ──
  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: Ym.t(12, color: Ym.grey, w: FontWeight.w700)),
      );

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: Ym.t(12.5, color: Ym.red)),
        );

  Widget _box(
    TextEditingController c, {
    String? hint,
    bool obscure = false,
    TextInputType? keyboard,
    int? maxLength,
    List<TextInputFormatter>? formatters,
    bool big = false,
    Widget? suffix,
    ValueChanged<String>? onChanged,
  }) =>
      TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        maxLength: maxLength,
        inputFormatters: formatters,
        onChanged: onChanged,
        textAlign: big ? TextAlign.center : TextAlign.start,
        style: big
            ? Ym.h(22).copyWith(letterSpacing: 6)
            : Ym.t(14.5, w: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: Ym.t(13, color: Ym.grey).copyWith(letterSpacing: 0),
          counterText: '',
          filled: true,
          fillColor: Ym.creamTop,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          suffixIcon: suffix,
        ),
      );
}