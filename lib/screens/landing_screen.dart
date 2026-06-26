import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/landing_content.dart';
<<<<<<< HEAD
import 'welcome_screen.dart';
=======
>>>>>>> 3534e475c09ebf20b66ba6a27b1ee91fd98c5a5a

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Expanded(
              child: LandingContent(), // Renders your static landing layout
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
<<<<<<< HEAD
                  onPressed: () {
                    // =========================================================
                    // 🚀 NAVIGATION TRIGGER WIRING
                    // Smoothly cross-fades out of Landing into the new Welcome page
                    // =========================================================
                    Navigator.of(context).pushReplacement(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const WelcomeScreen(),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        transitionDuration: const Duration(milliseconds: 800), // Clean 800ms fade
                      ),
                    );
                  },
=======
                  onPressed: () {},
>>>>>>> 3534e475c09ebf20b66ba6a27b1ee91fd98c5a5a
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow,
                    foregroundColor: AppColors.primaryBlue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Get Started', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
