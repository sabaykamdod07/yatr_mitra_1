import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'institution_setup_screen.dart';
import 'admin_dashboard_screen.dart';
import 'helpdesk_management_screen.dart'; // MATCHED: Your exact file name

class LoginScreen extends StatefulWidget {
  final String selectedRole;
  const LoginScreen({super.key, required this.selectedRole});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _isLoading = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  final supabase = Supabase.instance.client;

  bool get _isAdmin => widget.selectedRole == 'Admin';

  // ── Warm cream / gold palette (replaces the old blue theme) ──────────
  static const Color _accent = Color(0xFFC9820A);
  static const Color _accentDeep = Color(0xFF8A5A00);
  static const Color _textDark = Color(0xFF3E2C13);
  static const Color _textMuted = Color(0xFF8A7860);
  static const Color _cardBg = Color(0xFFFFFDF6);
  static const Color _inputBg = Color(0xFFFFFBF2);
  static const Color _inputBorder = Color(0xFFEBD9AE);
  static const Color _hintColor = Color(0xFFC2AF88);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String get _roleEmoji {
    switch (widget.selectedRole) {
      case 'Student': return '🎓';
      case 'Faculty': return '🧑‍🏫';
      case 'Admin': return '🛡️';
      case 'Help Desk': return '🎧';
      case 'Driver': return '🚌';
      default: return '👤';
    }
  }

  String get _roleValue {
    switch (widget.selectedRole) {
      case 'Student': return 'student';
      case 'Faculty': return 'faculty';
      case 'Admin': return 'admin';
      case 'Help Desk': return 'help_desk';
      case 'Driver': return 'driver';
      default: return 'student';
    }
  }

  void _showSnack(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _handleSignUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user != null) {
        await supabase.from('users').insert({
          'id': user.id,
          'email': email,
          'role': _roleValue,
          'is_active': true,
        });
        _showSnack('Account created successfully!', isError: false);
      }
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Something went wrong. Try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user != null) {
        final userData = await supabase
            .from('users')
            .select('role')
            .eq('id', user.id)
            .single();

        final role = userData['role'];
        _showSnack('Welcome back!', isError: false);

        if (mounted) {
          if (role == 'admin') {
            final institution = await supabase
                .from('institutions')
                .select()
                .eq('admin_id', user.id)
                .maybeSingle();

            if (mounted) {
              if (institution == null) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InstitutionSetupScreen(),
                  ),
                );
              } else {
                // pushAndRemoveUntil wipes Role Selection + Login off the
                // stack so the back button on the dashboard has nowhere
                // to fall through to. Staying signed in means staying on
                // this screen until _handleLogout() explicitly navigates.
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const AdminDashboardScreen(),
                  ),
                  (route) => false,
                );
              }
            }
          } else if (role == 'help_desk') {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => const HelpDeskDashboard(), // Connected to your widget view
              ),
              (route) => false,
            );
          } else {
            _showSnack('Dashboard for role "$role" is under development.', isError: false);
          }
        }
      }
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Something went wrong. Try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full-bleed background illustration — BoxFit.cover so it fills
          // the entire phone screen edge-to-edge, same as the role
          // selection background.
          Positioned.fill(
            child: Image.asset(
              'assets/images/login_bg.png',
              fit: BoxFit.cover,
            ),
          ),

          // Very light warm wash so the illustration stays visible but
          // the floating card still pops with good contrast.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.10),
                    Colors.white.withOpacity(0.05),
                    Colors.white.withOpacity(0.18),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: _cardBg.withOpacity(0.93),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: _accentDeep.withOpacity(0.18),
                        blurRadius: 36,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 9, height: 9,
                            decoration: const BoxDecoration(
                              color: _accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'YATRA MITRA',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _accentDeep,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3D6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$_roleEmoji ${widget.selectedRole}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _accentDeep,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        _isSignUp ? 'Create account' : 'Welcome back',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: _textDark,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isSignUp
                            ? 'Register as ${widget.selectedRole}'
                            : 'Sign in to your ${widget.selectedRole.toLowerCase()} account',
                        style: GoogleFonts.inter(fontSize: 13, color: _textMuted),
                      ),
                      const SizedBox(height: 22),

                      if (_isAdmin) ...[
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3D6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              _toggleBtn('Sign in', !_isSignUp, () => setState(() => _isSignUp = false)),
                              _toggleBtn('Sign up', _isSignUp, () => setState(() => _isSignUp = true)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],

                      if (_isAdmin && _isSignUp) ...[
                        _label('Full name'),
                        _inputField(_nameController, 'Your full name', false),
                        const SizedBox(height: 14),
                      ],

                      _label('Email address'),
                      _inputField(_emailController, 'you@svit.edu.in', false),
                      const SizedBox(height: 14),

                      _label('Password'),
                      _passwordField(),

                      if (!_isSignUp) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () {},
                            child: Text(
                              'Forgot password?',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: _accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : () => _isSignUp ? _handleSignUp() : _handleSignIn(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                            shadowColor: _accentDeep.withOpacity(0.4),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20, width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isSignUp ? 'Create account' : 'Sign in',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? [BoxShadow(color: _accentDeep.withOpacity(0.12), blurRadius: 8)]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? _textDark : _textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _textMuted,
        ),
      ),
    );
  }

  Widget _inputField(TextEditingController controller, String hint, bool obscure) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: GoogleFonts.inter(fontSize: 14, color: _textDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: _hintColor, fontSize: 14),
        filled: true,
        fillColor: _inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _inputBorder, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: GoogleFonts.inter(fontSize: 14, color: _textDark),
      decoration: InputDecoration(
        hintText: 'Enter your password',
        hintStyle: GoogleFonts.inter(color: _hintColor, fontSize: 14),
        filled: true,
        fillColor: _inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: _hintColor,
            size: 20,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _inputBorder, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
      ),
    );
  }
}