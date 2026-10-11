import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_preview/device_preview.dart';
import 'screens/animated_splash_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/helpdesk_management_screen.dart'; // MATCHED: Your exact file name

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://itkplcmlvweggsriwzqq.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0a3BsY21sdndlZ2dzcml3enFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0Mzk4MTMsImV4cCI6MjA5ODAxNTgxM30.p8ACzNXs9pmNVRGhPHzhe1ZjMRY7ABwdU8E9FL3x1tQ',
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
        '/student_dashboard': (context) => const Scaffold(
          body: Center(child: Text('Student Dashboard Coming Soon!')),
        ),
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