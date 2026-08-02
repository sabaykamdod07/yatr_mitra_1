import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_strategy/url_strategy.dart';
import 'package:yatra_mitra/screens/student_self_registration_screen.dart';

Future<void> main() async {
  setPathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://itkplcmlvweggsriwzqq.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0a3BsY21sdndlZ2dzcml3enFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0Mzk4MTMsImV4cCI6MjA5ODAxNTgxM30.p8ACzNXs9pmNVRGhPHzhe1ZjMRY7ABwdU8E9FL3x1tQ',
  );
  
  final uri = Uri.base;
  
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Yatra Mitra — Student Registration',
      home: StudentSelfRegistrationScreen(
        institutionId: uri.queryParameters['inst'],
      ),
    ),
  );
}