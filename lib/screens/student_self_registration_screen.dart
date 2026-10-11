import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/money.dart';
import '../services/payment_info.dart';
import '../widgets/pay_panel.dart';
import 'map_picker_screen.dart';

/// The public registration form (opened from the link the help desk shares).
///
///  * a student or a faculty member fills in their details and picks a boarding stop
///  * a STUDENT can also pay the bus fee right here (optional): they see the fee of the
///    route, pay by UPI, and type the reference number. The help desk verifies it when
///    it reviews the registration. Nothing is marked paid by this form.
///  * everything goes to the help desk as a pending registration
class StudentSelfRegistrationScreen extends StatefulWidget {
  final String? institutionId;
  const StudentSelfRegistrationScreen({super.key, this.institutionId});

  @override
  State<StudentSelfRegistrationScreen> createState() => _StudentSelfRegistrationScreenState();
}

class _StudentSelfRegistrationScreenState extends State<StudentSelfRegistrationScreen> {
  // the cream look, the same as the welcome page
  static const _cream = Color(0xFFFDF3E3);
  static const _card = Color(0xFFFFFBF3);
  static const _line = Color(0xFFEADFC8);
  static const _navy = Color(0xFF14284B);
  static const _amber = Color(0xFFFFA826);
  static const _amberSoft = Color(0xFFFFF1D4);
  static const _muted = Color(0xFF6B7385);
  static const _red = Color(0xFFD64545);
  static const _green = Color(0xFF2F9E6B);

  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  String _role = 'student';
  String _studentName = '';
  String _studentEmail = '';
  String _admissionDate = ''; // YYYY-MM-DD
  String _department = '';
  String _employeeId = '';
  String _studentPhone = '';
  String _parentName = '';
  String _parentRelation = 'Father';
  String _parentEmail = '';
  String _parentPhone = '';

  final _admissionCtrl = TextEditingController();

  LatLng? _homeLocation;
  List<Map<String, dynamic>> _allStops = [];
  List<Map<String, dynamic>> _nearbyStops = [];
  Map<String, dynamic>? _selectedStop;
  bool _wantsCustomStop = false;
  LatLng? _customStopLocation;
  String _customStopNote = '';
  final TextEditingController _customStopNoteController = TextEditingController();

  // paying the bus fee (students, optional)
  Map<String, dynamic>? _fee; // {route_name, fee, year}
  bool _feeLoading = false;
  final _payAmountCtrl = TextEditingController();
  final _payRefCtrl = TextEditingController();
  String? _payError;
  PayMode _payMode = PayMode.upi;
  PaymentInfo _payInfo = PaymentInfo.demo; // the admin's UPI ID, once loaded
  String _regCode = ''; // quoted at the help desk
  bool _submittedCash = false;

  bool _isLoadingStops = true;
  bool _isSubmitting = false;
  bool _submitted = false;
  bool _submittedWithPayment = false;
  String? _institutionId;

  @override
  void initState() {
    super.initState();
    _regCode = _newCode();
    _loadStops();
    PaymentInfo.load(widget.institutionId).then((v) {
      if (mounted) setState(() => _payInfo = v);
    });
  }

  /// a short registration number, for example K7M2QX (no look-alike letters)
  String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    _customStopNoteController.dispose();
    _admissionCtrl.dispose();
    _payAmountCtrl.dispose();
    _payRefCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────── data ─────────────────────────

  Future<void> _loadStops() async {
    try {
      _institutionId = widget.institutionId;
      if (_institutionId == null) {
        setState(() => _isLoadingStops = false);
        return;
      }

      final data = await _supabase
          .from('stops')
          .select('id, stop_name, timing, lat, lng, route_id')
          .not('lat', 'is', null)
          .not('lng', 'is', null);

      final routesData = await _supabase
          .from('routes')
          .select('id')
          .eq('institution_id', _institutionId!);

      final routeIds = (routesData as List).map((r) => r['id']).toList();
      final filteredStops =
          (data as List).where((stop) => routeIds.contains(stop['route_id'])).toList();

      setState(() {
        _allStops = List<Map<String, dynamic>>.from(filteredStops);
        _isLoadingStops = false;
      });
    } catch (e) {
      debugPrint('Error loading stops: $e');
      setState(() => _isLoadingStops = false);
    }
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  void _computeNearbyStops() {
    if (_homeLocation == null || _allStops.isEmpty) return;

    final withDistance = _allStops.map((stop) {
      final distance = _distanceKm(
        _homeLocation!.latitude,
        _homeLocation!.longitude,
        double.parse(stop['lat'].toString()),
        double.parse(stop['lng'].toString()),
      );
      return {...stop, 'distance': distance};
    }).toList();

    withDistance.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

    setState(() {
      // every predefined stop of this institution, nearest first
      _nearbyStops = withDistance;
      _selectedStop = null;
      _wantsCustomStop = false;
      _fee = null;
      _payAmountCtrl.clear();
      _payRefCtrl.clear();
      _payError = null;
    });
  }

  /// the bus fee of the route of the chosen stop (shown so the student can pay)
  Future<void> _loadFee(dynamic routeId) async {
    if (routeId == null) return;
    setState(() {
      _feeLoading = true;
      _fee = null;
      _payError = null;
    });
    try {
      final res = await _supabase.rpc('public_route_fee', params: {'p_route': routeId});
      if (!mounted) return;
      final m = res is Map ? Map<String, dynamic>.from(res) : null;
      setState(() {
        _fee = m;
        _feeLoading = false;
        final fee = num.tryParse('${m?['fee']}');
        _payAmountCtrl.text = fee == null ? '' : fee.round().toString();
      });
    } catch (_) {
      if (mounted) setState(() => _feeLoading = false);
    }
  }

  void _selectStop(Map<String, dynamic> stop) {
    setState(() {
      _selectedStop = stop;
      _wantsCustomStop = false;
    });
    _loadFee(stop['route_id']);
  }

  Future<void> _pickHomeLocation() async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLocation: _homeLocation,
          title: 'Tap Your Home Location',
        ),
      ),
    );
    if (picked != null) {
      setState(() => _homeLocation = picked);
      _computeNearbyStops();
    }
  }

  Future<void> _pickCustomStopLocation() async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLocation: _customStopLocation ?? _homeLocation,
          title: 'Tap Your Preferred Boarding Point',
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _customStopLocation = picked;
        _wantsCustomStop = true;
        _selectedStop = null;
        _fee = null;
        _payAmountCtrl.clear();
        _payRefCtrl.clear();
      });
    }
  }

  void _cancelCustomStopRequest() {
    setState(() {
      _wantsCustomStop = false;
      _customStopLocation = null;
      _customStopNote = '';
      _customStopNoteController.clear();
    });
  }

  Future<void> _pickAdmissionDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Date of admission',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _navy, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (d != null) {
      const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      setState(() {
        _admissionDate =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        _admissionCtrl.text = '${d.day} ${m[d.month - 1]} ${d.year}';
      });
    }
  }

  // ───────────────────────── submit ─────────────────────────

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// What is being paid with this registration, or null if nothing.
  /// Sets [_payError] when something is wrong.
  ({double amount, String? ref, String method})? _checkedPayment() {
    _payError = null;
    if (_role != 'student') return null;
    final fee = num.tryParse('${_fee?['fee']}');
    final amount = parseMoney(_payAmountCtrl.text)?.toDouble();

    if (_payMode == PayMode.cash) {
      if (amount == null || amount <= 0) {
        _payError = 'Please enter the amount you will pay in cash.';
        return null;
      }
      if (fee != null && amount > fee) {
        _payError = 'The amount is more than the fee (\u20B9${fee.round()}).';
        return null;
      }
      return (amount: amount, ref: null, method: 'Cash');
    }

    if (_payMode == PayMode.upi) {
      final ref = _payRefCtrl.text.trim();
      if (ref.isEmpty) return null; // nothing typed: they will pay later
      if (ref.length < 4) {
        _payError = 'Please enter the full UPI / transaction reference number.';
        return null;
      }
      if (amount == null || amount <= 0) {
        _payError = 'Please enter the amount you paid.';
        return null;
      }
      if (fee != null && amount > fee) {
        _payError = 'The amount is more than the fee (\u20B9${fee.round()}).';
        return null;
      }
      return (amount: amount, ref: ref, method: 'UPI');
    }
    return null; // pay later
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    if (_homeLocation == null) {
      _snack('Please tap your home location on the map.');
      return;
    }
    if (_selectedStop == null && !_wantsCustomStop) {
      _snack('Please choose a boarding stop, or request a custom one.');
      return;
    }
    if (_wantsCustomStop && _customStopLocation == null) {
      _snack('Please tap a location on the map for your requested stop.');
      return;
    }

    // the optional payment (UPI with a reference, or cash)
    final pay = _checkedPayment();
    final wantsPayment = _role == 'student' &&
        ((_payMode == PayMode.upi && _payRefCtrl.text.trim().isNotEmpty) ||
            _payMode == PayMode.cash);
    if (wantsPayment && pay == null) {
      setState(() {}); // shows the problem under the payment box
      _snack(_payError ?? 'Please check the payment details.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (_wantsCustomStop && _customStopLocation != null) {
        try {
          // the request the ADMIN sees in "Pending Route Requests"
          await _supabase.from('route_requests').insert({
            'institution_id': _institutionId,
            'requested_boarding_point': _customStopNote.trim().isEmpty
                ? 'Custom location (${_customStopLocation!.latitude.toStringAsFixed(4)}, ${_customStopLocation!.longitude.toStringAsFixed(4)})'
                : _customStopNote.trim(),
            'status': 'pending',
            'custom_stop_lat': _customStopLocation!.latitude,
            'custom_stop_lng': _customStopLocation!.longitude,
          });

          await _supabase.from('notifications').insert({
            'institution_id': _institutionId,
            'title': 'New Custom Stop Request',
            'message':
                '$_studentName requested a custom boarding stop: ${_customStopNote.isNotEmpty ? _customStopNote : "Custom location"}',
            'is_read': false,
          });
        } catch (e) {
          debugPrint('Error creating route request: $e');
        }
      }

      await _supabase.from('pending_enrollments').insert({
        'institution_id': _institutionId,
        'role': _role,
        'student_name': _studentName,
        'student_email': _studentEmail.trim().isEmpty ? null : _studentEmail.trim(),
        'student_phone': _studentPhone.trim().isEmpty ? null : _studentPhone.trim(),
        'admission_date':
            _role == 'student' && _admissionDate.trim().isNotEmpty ? _admissionDate.trim() : null,
        'department': _department.trim().isEmpty ? null : _department.trim(),
        'employee_id': _role == 'faculty' ? _employeeId.trim() : null,
        'parent_name': _role == 'student' ? _parentName : null,
        'parent_relation': _role == 'student' ? _parentRelation.toLowerCase() : null,
        'parent_email': _role == 'student' ? _parentEmail.trim() : null,
        'parent_phone': _role == 'student' ? _parentPhone.trim() : null,
        'home_lat': _homeLocation!.latitude,
        'home_lng': _homeLocation!.longitude,
        'suggested_stop_id': _selectedStop?['id'],
        'suggested_route_id': _selectedStop?['route_id'],
        'wants_custom_stop': _wantsCustomStop,
        'custom_stop_lat': _customStopLocation?.latitude,
        'custom_stop_lng': _customStopLocation?.longitude,
        'custom_stop_note': _customStopNote.trim().isEmpty ? null : _customStopNote.trim(),
        'registration_code': _regCode,
        // the optional payment: the help desk verifies it (UPI) or receives it (cash)
        // before anything is marked paid
        if (pay != null) ...{
          'payment_amount': pay.amount,
          'payment_reference': pay.ref,
          'payment_method': pay.method,
          'payment_note': pay.method == 'Cash'
              ? 'Will pay cash at the help desk'
              : 'Sent with the registration form',
        },
      });

      if (mounted) {
        setState(() {
          _submitted = true;
          _submittedWithPayment = pay != null;
          _submittedCash = pay?.method == 'Cash';
        });
      }
    } catch (e) {
      if (mounted) _snack('Could not submit: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _registerAnother() {
    setState(() {
      _submitted = false;
      _submittedWithPayment = false;
      _submittedCash = false;
      _payMode = PayMode.upi;
      _regCode = _newCode();
      _formKey.currentState?.reset();
      _role = 'student';
      _admissionDate = '';
      _admissionCtrl.clear();
      _homeLocation = null;
      _nearbyStops = [];
      _selectedStop = null;
      _wantsCustomStop = false;
      _customStopLocation = null;
      _customStopNote = '';
      _customStopNoteController.clear();
      _fee = null;
      _payAmountCtrl.clear();
      _payRefCtrl.clear();
      _payError = null;
    });
  }

  // ───────────────────────── small building blocks ─────────────────────────

  TextStyle _label() => GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _muted);

  InputDecoration _dec({String? hint, Widget? suffix, String? helper}) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFFA3A9B8)),
        helperText: helper,
        helperStyle: GoogleFonts.inter(fontSize: 11.5, color: _muted),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _amber, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _red, width: 1.6),
        ),
      );

  Widget _section(String title, {String? sub}) => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 18,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(color: _amber, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14.5, fontWeight: FontWeight.w800, color: _navy)),
                  if (sub != null)
                    Text(sub, style: GoogleFonts.inter(fontSize: 12, color: _muted)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _panel({required Widget child, Color? color, Color? border}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color ?? _card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: border ?? _line),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE9C98A).withOpacity(0.14),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      );

  Widget _roleToggleButton(String label, String value, IconData icon) {
    final on = _role == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _role = value;
          if (value == 'faculty') {
            _fee = null;
            _payRefCtrl.clear();
            _payError = null;
          }
        });
        // a student who already picked a stop sees the fee again
        if (value != 'faculty' && _selectedStop != null && _fee == null) {
          _loadFee(_selectedStop!['route_id']);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: on ? _navy : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: on ? _navy : _line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: on ? Colors.white : _muted),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: on ? Colors.white : _navy)),
          ],
        ),
      ),
    );
  }

  Widget _labeledField(
    String label, {
    required FormFieldSetter<String> onSaved,
    bool required = false,
    bool isEmail = false,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _label()),
        const SizedBox(height: 6),
        TextFormField(
          decoration: _dec(hint: hint),
          style: GoogleFonts.inter(fontSize: 14.5, color: _navy, fontWeight: FontWeight.w500),
          keyboardType: keyboardType,
          validator: (v) {
            if (required && (v == null || v.trim().isEmpty)) return 'Required';
            if (isEmail && v != null && v.trim().isNotEmpty) {
              final emailPattern = RegExp(r'^[\w.\-]+@[\w\-]+(\.[\w\-]+)+$');
              if (!emailPattern.hasMatch(v.trim())) return 'Enter a valid email';
            }
            return null;
          },
          onSaved: onSaved,
        ),
      ],
    );
  }

  /// a phone number: digits only, exactly 10
  Widget _phoneField(
    String label, {
    required FormFieldSetter<String> onSaved,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _label()),
        const SizedBox(height: 6),
        TextFormField(
          decoration: _dec(hint: '10-digit mobile number'),
          style: GoogleFonts.inter(fontSize: 14.5, color: _navy, fontWeight: FontWeight.w500),
          keyboardType: TextInputType.phone,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty) return required ? 'Required' : null;
            if (t.length != 10) return 'Phone number must be 10 digits';
            return null;
          },
          onSaved: onSaved,
        ),
      ],
    );
  }

  Widget _admissionField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Admission Date (optional)', style: _label()),
          const SizedBox(height: 6),
          TextFormField(
            controller: _admissionCtrl,
            readOnly: true,
            onTap: _pickAdmissionDate,
            style: GoogleFonts.inter(fontSize: 14.5, color: _navy, fontWeight: FontWeight.w500),
            decoration: _dec(
              hint: 'Tap to pick the date',
              suffix: _admissionCtrl.text.isEmpty
                  ? const Icon(Icons.event_rounded, color: _muted)
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, color: _muted, size: 20),
                      onPressed: () => setState(() {
                        _admissionCtrl.clear();
                        _admissionDate = '';
                      }),
                    ),
            ),
          ),
        ],
      );

  Widget _outlineAction(
      {required IconData icon, required String label, required VoidCallback onTap, Color? color}) {
    final c = color ?? _navy;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.withOpacity(0.35), width: 1.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: c),
            const SizedBox(width: 10),
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5, fontWeight: FontWeight.w800, color: c)),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── page ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
              child: _submitted ? _successView() : _formView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandHeader() => Row(
        children: [
          // the Yatra Mitra logo
          Image.asset(
            'assets/images/yatra_logo.png',
            height: 62,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                  children: const [
                    TextSpan(text: 'YATRA ', style: TextStyle(color: _navy)),
                    TextSpan(text: 'MITRA', style: TextStyle(color: _amber)),
                  ],
                ),
              ),
              Text('Safe Journeys  \u2022  Smarter Campus',
                  style: GoogleFonts.inter(fontSize: 11.5, color: _muted)),
            ],
          ),
        ],
      );

  Widget _formView() {
    final isFaculty = _role == 'faculty';
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _brandHeader(),
          const SizedBox(height: 26),
          Text('New Registration',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 28, fontWeight: FontWeight.w800, color: _navy, letterSpacing: -0.4)),
          const SizedBox(height: 6),
          Text('Fill this form and our help desk will contact you to complete the enrollment.',
              style: GoogleFonts.inter(fontSize: 13.5, height: 1.5, color: _muted)),
          const SizedBox(height: 22),

          _section('I am registering as'),
          Row(
            children: [
              Expanded(child: _roleToggleButton('Student', 'student', Icons.school_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _roleToggleButton('Faculty', 'faculty', Icons.badge_outlined)),
            ],
          ),
          const SizedBox(height: 22),

          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _section(isFaculty ? 'Your details' : 'Student details'),
                _labeledField(
                  isFaculty ? 'Full Name' : 'Student Full Name',
                  required: true,
                  onSaved: (v) => _studentName = v ?? '',
                ),
                const SizedBox(height: 14),
                _labeledField(
                  isFaculty ? 'Email (optional)' : 'Student Email (optional)',
                  keyboardType: TextInputType.emailAddress,
                  isEmail: true,
                  onSaved: (v) => _studentEmail = v ?? '',
                ),
                const SizedBox(height: 14),
                _phoneField('Phone Number (optional)', onSaved: (v) => _studentPhone = v ?? ''),
                const SizedBox(height: 14),
                _labeledField('Section / Department (optional)',
                    onSaved: (v) => _department = v ?? ''),
                const SizedBox(height: 14),
                if (isFaculty)
                  _labeledField('Employee ID', onSaved: (v) => _employeeId = v ?? '')
                else
                  _admissionField(),
              ],
            ),
          ),

          if (!isFaculty) ...[
            const SizedBox(height: 18),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('Parent / Guardian', sub: 'Their login is sent to the email below'),
                  _labeledField('Parent / Guardian Name',
                      required: true, onSaved: (v) => _parentName = v ?? ''),
                  const SizedBox(height: 14),
                  Text('Relation', style: _label()),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _parentRelation,
                    decoration: _dec(),
                    style: GoogleFonts.inter(
                        fontSize: 14.5, color: _navy, fontWeight: FontWeight.w500),
                    items: ['Father', 'Mother', 'Guardian']
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setState(() => _parentRelation = v ?? 'Father'),
                  ),
                  const SizedBox(height: 14),
                  _labeledField(
                    'Parent Email (credentials will be sent here)',
                    required: true,
                    isEmail: true,
                    keyboardType: TextInputType.emailAddress,
                    onSaved: (v) => _parentEmail = v ?? '',
                  ),
                  const SizedBox(height: 14),
                  _phoneField('Parent Phone Number',
                      required: true, onSaved: (v) => _parentPhone = v ?? ''),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),
          _panel(child: _locationBlock()),

          if (!isFaculty && _selectedStop != null && !_wantsCustomStop) ...[
            const SizedBox(height: 18),
            _paymentBlock(),
          ],

          const SizedBox(height: 26),
          GestureDetector(
            onTap: _isSubmitting ? null : _submit,
            child: Container(
              width: double.infinity,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _navy,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: _navy.withOpacity(0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Submit Registration',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(width: 10),
                        const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 21),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── boarding location ──

  Widget _locationBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Boarding location', sub: 'Set your home, then choose the nearest stop'),
        _outlineAction(
          icon: _homeLocation == null ? Icons.my_location_rounded : Icons.location_on_rounded,
          label: _homeLocation == null
              ? 'Tap to Set Home Location'
              : 'Home Location Set \u2014 Tap to Change',
          onTap: _pickHomeLocation,
          color: _homeLocation == null ? _navy : _green,
        ),
        if (_homeLocation != null && _isLoadingStops)
          const Padding(
            padding: EdgeInsets.only(top: 18),
            child: Center(child: CircularProgressIndicator(color: _amber)),
          ),
        if (_homeLocation != null && !_isLoadingStops) ...[
          const SizedBox(height: 18),
          if (_nearbyStops.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Nearest available stops',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5, fontWeight: FontWeight.w800, color: _navy)),
                Text('${_nearbyStops.length} found', style: GoogleFonts.inter(fontSize: 11.5, color: _muted)),
              ],
            ),
            const SizedBox(height: 10),
            ..._nearbyStops.map(_stopTile),
          ] else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _amberSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFB7791F), size: 19),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('No predefined stops found yet. You can request a new stop below.',
                        style: GoogleFonts.inter(fontSize: 12.5, color: _navy)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          const Divider(color: _line, height: 1),
          const SizedBox(height: 16),
          _customStopBlock(),
        ],
      ],
    );
  }

  Widget _stopTile(Map<String, dynamic> stop) {
    final on = _selectedStop != null && _selectedStop!['id'] == stop['id'];
    final distance = (stop['distance'] as double).toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _selectStop(stop),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: on ? _amberSoft : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? _amber : _line, width: on ? 1.8 : 1),
          ),
          child: Row(
            children: [
              Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: on ? _amber : const Color(0xFFB9BFCC), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((stop['stop_name'] ?? '').toString(),
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800, fontSize: 14, color: _navy)),
                    Text('$distance km away',
                        style: GoogleFonts.inter(fontSize: 11.5, color: _muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customStopBlock() {
    if (!_wantsCustomStop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Don't see your stop nearby?",
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5, fontWeight: FontWeight.w800, color: _navy)),
          const SizedBox(height: 10),
          _outlineAction(
            icon: Icons.add_location_alt_outlined,
            label: 'Request a Different Stop',
            onTap: _pickCustomStopLocation,
            color: const Color(0xFFD97706),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _amberSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded, color: _amber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Custom stop location selected',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800, fontSize: 13.5, color: _navy)),
              ),
              TextButton(
                onPressed: _pickCustomStopLocation,
                child: Text('Change',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: _navy)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _customStopNoteController,
            decoration: _dec(hint: 'Describe the location, e.g. near the bus stand (optional)'),
            style: GoogleFonts.inter(fontSize: 14, color: _navy),
            onChanged: (val) => _customStopNote = val,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _cancelCustomStopRequest,
              child: Text('Cancel \u2014 choose from the list instead',
                  style: GoogleFonts.inter(fontSize: 12.5, color: _red, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // ── pay the bus fee (students, optional) ──

  Widget _paymentBlock() {
    final fee = num.tryParse('${_fee?['fee']}');
    final year = (_fee?['year'] ?? '').toString();
    final route = (_fee?['route_name'] ?? _selectedStop?['stop_name'] ?? '').toString();
    final amount = parseMoney(_payAmountCtrl.text) ?? (fee ?? 0);

    return _panel(
      color: const Color(0xFFFFF8EA),
      border: const Color(0xFFF2D9A6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('Pay the bus fee now (optional)',
              sub: 'Pay by UPI, or choose cash at the help desk. You can also pay later'),
          if (_feeLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(child: CircularProgressIndicator(color: _amber)),
            )
          else if (fee == null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: _muted, size: 19),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The fee for this route is not set yet. Please pay at the help desk, '
                      'or in the parent app after your login is created.',
                      style: GoogleFonts.inter(fontSize: 12.5, height: 1.45, color: _navy),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_rounded, color: _amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(route.isEmpty ? 'Bus fee' : 'Bus fee, $route',
                            style: GoogleFonts.inter(fontSize: 12, color: _muted)),
                        Text('\u20B9${fee.round()}${year.isEmpty ? '' : '  \u2022  $year'}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 19, fontWeight: FontWeight.w800, color: _navy)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Amount you are paying', style: _label()),
            const SizedBox(height: 6),
            TextField(
              controller: _payAmountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\s]'))],
              onChanged: (_) => setState(() => _payError = null),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 19, fontWeight: FontWeight.w800, color: _navy),
              decoration: _dec(hint: 'Amount').copyWith(
                prefixText: '\u20B9 ',
                prefixStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 19, fontWeight: FontWeight.w800, color: _navy),
              ),
            ),
            const SizedBox(height: 18),
            PayPanel(
              info: _payInfo,
              amount: amount,
              note: 'Bus fee ${_studentName.isEmpty ? '' : _studentName}'.trim(),
              mode: _payMode,
              onMode: (m) => setState(() {
                _payMode = m;
                _payError = null;
              }),
              referenceController: _payRefCtrl,
              onReferenceChanged: (_) => setState(() => _payError = null),
              allowLater: true,
              errorText: _payError,
            ),
          ],
        ],
      ),
    );
  }

  // ── after submitting ──

  Widget _successView() {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        children: [
          _brandHeader(),
          const SizedBox(height: 40),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: _green.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: _green, size: 48),
          ),
          const SizedBox(height: 22),
          Text('Registration submitted',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 25, fontWeight: FontWeight.w800, color: _navy)),
          const SizedBox(height: 10),
          Text(
            'Our help desk will review it and contact you soon. '
            'Your login will be emailed once your enrollment is complete.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, height: 1.55, color: _muted),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _line),
            ),
            child: Column(
              children: [
                Text('Your registration number',
                    style: GoogleFonts.inter(fontSize: 12, color: _muted)),
                const SizedBox(height: 4),
                SelectableText(_regCode,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: _navy)),
                const SizedBox(height: 4),
                Text('Keep it. Quote it at the help desk.',
                    style: GoogleFonts.inter(fontSize: 12, color: _muted)),
              ],
            ),
          ),
          if (_submittedWithPayment && !_submittedCash) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _amberSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, color: Color(0xFFB7791F)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your payment was sent with the registration. The help desk will verify it, '
                      'and your fee is marked as paid once it is confirmed.',
                      style: GoogleFonts.inter(fontSize: 12.5, height: 1.5, color: _navy),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_submittedCash) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _amberSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.payments_outlined, color: Color(0xFFB7791F)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Please pay the fee in cash at the help desk',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5, fontWeight: FontWeight.w800, color: _navy)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Quote your registration number $_regCode. Your fee is marked as paid, '
                    'and your receipt is made, once the help desk has received the cash.',
                    style: GoogleFonts.inter(fontSize: 12.5, height: 1.5, color: _navy),
                  ),
                  if (_payInfo.cashNote != null) ...[
                    const SizedBox(height: 8),
                    Text(_payInfo.cashNote!,
                        style: GoogleFonts.inter(
                            fontSize: 12.5, fontWeight: FontWeight.w700, color: _navy)),
                  ],
                  if (_payInfo.helpPhone != null) ...[
                    const SizedBox(height: 4),
                    Text('Help desk: ${_payInfo.helpPhone}',
                        style: GoogleFonts.inter(
                            fontSize: 12.5, fontWeight: FontWeight.w700, color: _navy)),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 30),
          GestureDetector(
            onTap: _registerAnother,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _line, width: 1.4),
              ),
              child: Text('Register another person',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14.5, fontWeight: FontWeight.w800, color: _navy)),
            ),
          ),
        ],
      ),
    );
  }
}