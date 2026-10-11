import 'package:supabase_flutter/supabase_flutter.dart';

/// Everything the student screens need to know about "my bus", in one place.
///
/// Bus resolution order (so it works with how your admin assigns things today
/// AND later with hardware):
///   1. students.bus_id
///   2. routes.bus_id of the student's route
///
/// Driver resolution: the active row in `drivers` assigned to that bus or route.
class StudentContext {
  StudentContext({
    required this.userId,
    required this.student,
    this.route,
    this.stop,
    this.bus,
    this.busId,
    this.driverName,
    this.driverPhone,
    this.rescueActive = false,
    this.isFaculty = false,
  });

  final String userId;
  final Map<String, dynamic> student;
  final Map<String, dynamic>? route;
  final Map<String, dynamic>? stop;
  final Map<String, dynamic>? bus;
  final String? busId;
  final String? driverName;
  final String? driverPhone;

  /// true while a rescue bus has taken over this route's bus (its bus broke down)
  final bool rescueActive;

  /// true when this is a faculty member (the "student" map then holds the faculty record)
  final bool isFaculty;

  String? get routeId => route?['id']?.toString();
  double? get stopLat => _num(stop?['lat']);
  double? get stopLng => _num(stop?['lng']);

  static double? _num(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());

  /// [forRouteId] lets other screens look at a different route (Other Buses).
  /// In that case there is no boarding stop and the bus/driver belong to that route.
  ///
  /// [studentId] is used by the parent app: it loads that child's record
  /// instead of looking the student up by the logged-in email.
  ///
  /// [faculty] loads the logged-in FACULTY member instead (same bus, route, stop
  /// and driver details, so the live map and Other Buses work for them too).
  static Future<StudentContext> load({
    String? forRouteId,
    String? studentId,
    bool faculty = false,
  }) async {
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    final email = user?.email;
    if (user == null || (studentId == null && email == null)) {
      throw Exception('Not logged in.');
    }

    Map<String, dynamic>? row;
    if (faculty) {
      // a faculty record: the route is embedded, the stop is looked up by its id
      final pattern = email!
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      final f = await sb
          .from('faculty')
          .select('*, routes(id,route_name,start_point,end_point,timings,bus_id)')
          .ilike('faculty_email', pattern)
          .maybeSingle();
      if (f == null) throw Exception('No faculty record found for $email.');
      Map<String, dynamic>? fStop;
      if (f['stop_id'] != null) {
        fStop = await sb
            .from('stops')
            .select('id,stop_name,timing,lat,lng')
            .eq('id', f['stop_id'])
            .maybeSingle();
      }
      row = {
        ...f,
        'student_name': f['faculty_name'],
        'stops': fStop,
      };
    } else {
      final query = sb.from('students').select(
        '*, routes(id,route_name,start_point,end_point,timings,bus_id), '
        'stops(id,stop_name,timing,lat,lng)',
      );
      row = studentId != null
          ? await query.eq('id', studentId).maybeSingle()
          : await query.eq('student_email', email!).maybeSingle();

      if (row == null) {
        throw Exception(studentId != null
            ? 'Student record not found.'
            : 'No student record found for $email.');
      }
    }

    Map<String, dynamic>? route = row['routes'] as Map<String, dynamic>?;
    Map<String, dynamic>? stop = row['stops'] as Map<String, dynamic>?;
    String? busId = (row['bus_id'] ?? route?['bus_id'])?.toString();

    if (forRouteId != null && forRouteId != route?['id']?.toString()) {
      route = await sb
          .from('routes')
          .select('id,route_name,start_point,end_point,timings,bus_id')
          .eq('id', forRouteId)
          .maybeSingle();
      stop = null;
      busId = route?['bus_id']?.toString();
    }

    // If this route's bus broke down and another bus accepted the rescue,
    // the student follows the rescue bus (map, ETA, driver, alerts).
    var rescueActive = false;
    String? rescueDriverId;
    if (busId != null) {
      try {
        final ra = await sb
            .from('rescue_assignments')
            .select('rescue_bus_id, rescue_driver_id')
            .eq('broken_bus_id', busId)
            .eq('status', 'accepted')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (ra != null && ra['rescue_bus_id'] != null) {
          rescueActive = true;
          busId = ra['rescue_bus_id'].toString();
          rescueDriverId = ra['rescue_driver_id']?.toString();
        }
      } catch (_) {
        // rescue table not created yet: carry on with the normal bus
      }
    }

    Map<String, dynamic>? bus;
    if (busId != null) {
      bus = await sb
          .from('buses')
          .select('id, bus_number, bus_name, status')
          .eq('id', busId)
          .maybeSingle();
    }

    String? driverName;
    String? driverPhone;
    final filters = rescueDriverId != null
        ? <String>['id.eq.$rescueDriverId']
        : <String>[
            if (busId != null) 'bus_id.eq.$busId',
            if (route?['id'] != null) 'route_id.eq.${route!['id']}',
          ];
    if (filters.isNotEmpty) {
      final d = await sb
          .from('drivers')
          .select('driver_name, driver_phone')
          .or(filters.join(','))
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();
      driverName = d?['driver_name']?.toString();
      driverPhone = d?['driver_phone']?.toString();
    }

    return StudentContext(
      userId: user.id,
      student: row,
      route: route,
      stop: stop,
      bus: bus,
      busId: busId,
      driverName: driverName,
      driverPhone: driverPhone,
      rescueActive: rescueActive,
      isFaculty: faculty,
    );
  }
}

/// `notifications.created_at` is a timestamp WITHOUT time zone (stored as UTC).
/// Dart would read it as local time and be off by 5h30 in India, so force UTC.
DateTime? parseUtc(dynamic v) {
  if (v == null) return null;
  var s = v.toString();
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d(:?\d\d)?$').hasMatch(s);
  if (!hasZone) s = '${s}Z';
  return DateTime.tryParse(s)?.toLocal();
}

String fmtClock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// 05 Oct 2026
String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

/// 2026-10-05 (what the database expects for `date` columns)
String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';