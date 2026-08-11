import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/animated_splash_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/helpdesk_management_screen.dart'; // MATCHED: Your exact file name
import 'screens/student_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(
    DevicePreview(
      enabled: true,
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
      builder: DevicePreview.appBuilder,
      // till this
      debugShowCheckedModeBanner: false,
      title: 'Yatra Mitra',
      home: const AnimatedSplashScreen(),
      routes: {
        '/admin_dashboard': (context) => const AdminDashboardScreen(),
        '/helpdesk_dashboard': (context) => const HelpDeskDashboard(), // UPDATED: Points to your widget
        '/student_dashboard': (context) => const StudentDashboardScreen(),
        '/parent_dashboard': (context) => const Scaffold(
          body: Center(child: Text('Parent Dashboard Coming Soon!')),
        ),
        '/driver_dashboard': (context) => const Scaffold(
          body: Center(child: Text('Driver Dashboard Coming Soon!')),
        ),
        '/faculty_dashboard': (context) => const Scaffold(
          body: Center(child: Text('Faculty Dashboard Coming Soon!')),
        ),
      },
    );
  }
}