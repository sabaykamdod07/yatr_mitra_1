import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  final String selectedRole;
  const LoginScreen({super.key, required this.selectedRole});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  late AnimationController _bgController;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  final supabase = Supabase.instance.client;

  bool get _isAdmin => widget.selectedRole == 'Admin';

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      duration: const Duration(seconds: 9),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String get _roleEmoji {
    switch (widget.selectedRole) {
      case 'Student': return '🎓';
      case 'Parent': return '👨‍👩‍👧';
      case 'Faculty': return '🧑‍🏫';
      case 'Admin': return '🛡️';
      case 'Helpdesk': return '🎧';
      case 'Driver': return '🚌';
      default: return '👤';
    }
  }

  String get _roleValue {
    switch (widget.selectedRole) {
      case 'Student': return 'student';
      case 'Parent': return 'parent';
      case 'Faculty': return 'faculty';
      case 'Admin': return 'admin';
      case 'Helpdesk': return 'helpdesk';
      case 'Driver': return 'driver';
      default: return 'student';
    }
  }

  void _showSnack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Sign Up — only for Admin
  // Trigger automatically creates users + profiles rows
  Future<void> _handleSignUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || name.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': name,
          'role': _roleValue,
        },
        emailRedirectTo: null,
      );

      if (response.user != null) {
        _showSnack('Account created! Please sign in.', isError: false);
        setState(() => _isSignUp = false);
      } else {
        _showSnack('Registration failed. Try again.');
      }
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Sign In — for all roles
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
      if (user == null) {
        _showSnack('Invalid email or password');
        return;
      }

      // Check role in users table
      final userData = await supabase
          .from('users')
          .select('role, is_active')
          .eq('id', user.id)
          .maybeSingle();

      if (userData == null) {
        await supabase.auth.signOut();
        _showSnack('Account not found. Contact admin.');
        return;
      }

      if (userData['is_active'] == false) {
        await supabase.auth.signOut();
        _showSnack('Your account has been deactivated.');
        return;
      }

      final String dbRole = userData['role'] ?? '';
      if (dbRole != _roleValue) {
        await supabase.auth.signOut();
        _showSnack(
            'Role mismatch! Your account is not a ${widget.selectedRole} account.');
        return;
      }

      _showSnack('Welcome back!', isError: false);

      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      // Navigate to correct dashboard
      switch (dbRole) {
        case 'admin':
          Navigator.pushReplacementNamed(context, '/admin_dashboard');
          break;
        case 'student':
          Navigator.pushReplacementNamed(context, '/student_dashboard');
          break;
        case 'parent':
          Navigator.pushReplacementNamed(context, '/parent_dashboard');
          break;
        case 'driver':
          Navigator.pushReplacementNamed(context, '/driver_dashboard');
          break;
        case 'faculty':
          Navigator.pushReplacementNamed(context, '/faculty_dashboard');
          break;
        case 'helpdesk':
          Navigator.pushReplacementNamed(context, '/helpdesk_dashboard');
          break;
        default:
          _showSnack('Dashboard coming soon!');
      }
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _bgController,
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color.lerp(
                          const Color(0xFFC7D7FF),
                          const Color(0xFFD4C7FF),
                          _bgController.value) ??
                      const Color(0xFFC7D7FF),
                  const Color(0xFFF0F4FF),
                  Color.lerp(
                          const Color(0xFFD4C7FF),
                          const Color(0xFFC7E8FF),
                          _bgController.value) ??
                      const Color(0xFFD4C7FF),
                ],
              ),
            ),
            child: child,
          );
        },
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 32),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.88),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.95),
                      width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFF3B5BFF).withOpacity(0.08),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: Color(0xFF3B5BFF),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'YATRA MITRA',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3B5BFF),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Role Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_roleEmoji ${widget.selectedRole}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B5BFF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text(
                      _isSignUp ? 'Create account' : 'Welcome back',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F1B4C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isSignUp
                          ? 'Register as ${widget.selectedRole}'
                          : 'Sign in to your ${widget.selectedRole.toLowerCase()} account',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF8892AA)),
                    ),
                    const SizedBox(height: 22),

                    // Toggle — Admin only
                    if (_isAdmin) ...[
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _toggleBtn('Sign in', !_isSignUp,
                                () => setState(() => _isSignUp = false)),
                            _toggleBtn('Sign up', _isSignUp,
                                () => setState(() => _isSignUp = true)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],

                    // Name field — Admin sign up only
                    if (_isAdmin && _isSignUp) ...[
                      _label('Full name'),
                      _inputField(
                          _nameController, 'Your full name', false),
                      const SizedBox(height: 14),
                    ],

                    // Email
                    _label('Email address'),
                    _inputField(
                        _emailController, 'you@college.edu', false),
                    const SizedBox(height: 14),

                    // Password
                    _label('Password'),
                    _passwordField(),

                    if (!_isSignUp) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () {},
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF3B5BFF),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Main Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : () => _isSignUp
                                ? _handleSignUp()
                                : _handleSignIn(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B5BFF),
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _isSignUp
                                    ? 'Create account'
                                    : 'Sign in',
                                style: const TextStyle(
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
      ),
    );
  }

  Widget _toggleBtn(
      String label, bool active, VoidCallback onTap) {
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
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8)
                  ]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active
                  ? const Color(0xFF0F1B4C)
                  : const Color(0xFF8892AA),
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
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7A99),
        ),
      ),
    );
  }

  Widget _inputField(TextEditingController controller,
      String hint, bool obscure) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(
          fontSize: 14, color: Color(0xFF0F1B4C)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: Color(0xFFB0BAD0), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFFAFBFF),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: Color(0xFFE2E8F0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: Color(0xFF3B5BFF), width: 1.5),
        ),
      ),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: const TextStyle(
          fontSize: 14, color: Color(0xFF0F1B4C)),
      decoration: InputDecoration(
        hintText: 'Enter your password',
        hintStyle: const TextStyle(
            color: Color(0xFFB0BAD0), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFFAFBFF),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 13),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: const Color(0xFFB0BAD0),
            size: 20,
          ),
          onPressed: () => setState(
              () => _obscurePassword = !_obscurePassword),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: Color(0xFFE2E8F0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: Color(0xFF3B5BFF), width: 1.5),
        ),
      ),
    );
  }
}