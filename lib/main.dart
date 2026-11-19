import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/animated_splash_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/helpdesk_management_screen.dart'; // MATCHED: Your exact file name
import 'screens/student_dashboard_screen.dart';
import 'screens/driver_dashboard_screen.dart';
import 'screens/parent_dashboard_screen.dart';
import 'screens/faculty_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(
    DevicePreview(
      // The device simulator is only for testing in Chrome / on a computer.
      // It is OFF in the phone app (APK), so the app uses the real phone screen.
      enabled: !kReleaseMode && (kIsWeb || !(Platform.isAndroid || Platform.isIOS)),
      builder: (context) => const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // below are for the device preview
      useInheritedMediaQuery: true,
      locale: DevicePreview.locale(context),
      builder: (context, child) {
        final wrapped = DevicePreview.appBuilder(context, child);
        // Phones with "Large font" / "Large display" turned up made every screen
        // overflow. Keep the text at the size the screens were designed for.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.0),
          ),
          child: wrapped,
        );
      },
      // till this
      debugShowCheckedModeBanner: false,
      title: 'Yatra Mitra',
      home: const AnimatedSplashScreen(),
      routes: {
        '/admin_dashboard': (context) => const AdminDashboardScreen(),
        '/helpdesk_dashboard': (context) => const HelpDeskDashboard(), // UPDATED: Points to your widget
        '/student_dashboard': (context) => const StudentDashboardScreen(),
        '/parent_dashboard': (context) => const ParentDashboardScreen(),
        '/driver_dashboard': (context) => const DriverDashboardScreen(),
        '/faculty_dashboard': (context) => const FacultyDashboardScreen(),
      },
    );
  }
}