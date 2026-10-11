import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_dashboard_screen.dart';

class InstitutionSetupScreen extends StatefulWidget {
  const InstitutionSetupScreen({super.key});

  @override
  State<InstitutionSetupScreen> createState() => _InstitutionSetupScreenState();
}

class _InstitutionSetupScreenState extends State<InstitutionSetupScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _bgController;
  final _nameController = TextEditingController();
  final _cityController = TextEditingController();
  bool _isLoading = false;

  final supabase = Supabase.instance.client;

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
    _nameController.dispose();
    _cityController.dispose();
    super.dispose();
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

  Future<void> _saveInstitution() async {
    final name = _nameController.text.trim();
    final city = _cityController.text.trim();

    if (name.isEmpty || city.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      await supabase.from('institutions').insert({
        'admin_id': user.id,
        'name': name,
        'city': city,
      });

      _showSnack('Institution setup complete!', isError: false);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const AdminDashboardScreen(),
          ),
        );
      }
    } catch (e) {
      _showSnack('Something went wrong. Try again.');
    } finally {
      setState(() => _isLoading = false);
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
                  Color.lerp(const Color(0xFFC7D7FF), const Color(0xFFD4C7FF), _bgController.value) ?? const Color(0xFFC7D7FF),
                  const Color(0xFFF0F4FF),
                  Color.lerp(const Color(0xFFD4C7FF), const Color(0xFFC7E8FF), _bgController.value) ?? const Color(0xFFD4C7FF),
                ],
              ),
            ),
            child: child,
          );
        },
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.88),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.95), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B5BFF).withOpacity(0.08),
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
                          width: 9, height: 9,
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

                    // Step indicator
                    Row(
                      children: [
                        _stepCircle('1', true),
                        Expanded(child: Container(height: 1, color: const Color(0xFF3B5BFF).withOpacity(0.3))),
                        _stepCircle('2', false),
                      ],
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      'Set up your institution',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F1B4C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'This is a one-time setup. Your institution details will be used across the app.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF8892AA), height: 1.5),
                    ),
                    const SizedBox(height: 24),

                    _label('Institution name'),
                    _inputField(_nameController, 'e.g. Sai Vidya Institute of Technology'),
                    const SizedBox(height: 14),

                    _label('City'),
                    _inputField(_cityController, 'e.g. Bangalore'),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveInstitution,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B5BFF),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Continue →',
                                style: TextStyle(
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

  Widget _stepCircle(String number, bool active) {
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF3B5BFF) : const Color(0xFFF0F4FF),
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? const Color(0xFF3B5BFF) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Center(
        child: Text(
          number,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : const Color(0xFF8892AA),
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

  Widget _inputField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 14, color: Color(0xFF0F1B4C)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFB0BAD0), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFFAFBFF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3B5BFF), width: 1.5),
        ),
      ),
    );
  }
}