import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/animated_splash_screen.dart';
import 'screens/role_selection_screen.dart'; 

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://itkplcmlvweggsriwzqq.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0a3BsY21sdndlZ2dzcml3enFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0Mzk4MTMsImV4cCI6MjA5ODAxNTgxM30.p8ACzNXs9pmNVRGhPHzhe1ZjMRY7ABwdU8E9FL3x1tQ',
  );
  print('Supabase connected: ${Supabase.instance.client.auth.currentSession}');


  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
  debugShowCheckedModeBanner: false,
  title: 'Yatra Mitra',
  home: const AnimatedSplashScreen(),
  routes: {
    '/admin_dashboard': (context) => const Scaffold(
      body: Center(child: Text('Admin Dashboard Coming Soon!')),
    ),
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
    '/helpdesk_dashboard': (context) => const Scaffold(
      body: Center(child: Text('Helpdesk Dashboard Coming Soon!')),
    ),
  },
);
  }
}