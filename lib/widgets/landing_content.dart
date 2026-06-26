import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../config/app_text_styles.dart';
import 'feature_card.dart';
import 'stat_badge.dart';

class LandingContent extends StatelessWidget {
  const LandingContent({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          const SizedBox(height: 20),
          
          // App Header Pin Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.accentYellow,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_bus, color: Colors.white, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Brand Title
          RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              children: [
                TextSpan(text: 'YATRA ', style: TextStyle(color: AppColors.primaryBlue)),
                TextSpan(text: 'MITRA', style: TextStyle(color: AppColors.accentYellow)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Smart Safety-Oriented\nIntelligent Mobility System',
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitleStyle,
          ),
          const SizedBox(height: 20),
          
          // Bus Scene Graphics Area (Fixed Image Scaling)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Image.asset(
              'assets/images/bus.png',
              width: screenSize.width,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 25),
          
          // Main Headline
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              'Track Every Journey.\nEnsure Every Student\'s Safety.',
              textAlign: TextAlign.center,
              style: AppTextStyles.mainHeading,
            ),
          ),
          const SizedBox(height: 12),
          
          // Carousel Slider Indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Container(width: 16, height: 6, decoration: BoxDecoration(color: AppColors.accentYellow, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 4),
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 25),
          
          // Feature Grid Array
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.45,
              children: const [
                FeatureCard(
                  icon: Icons.rss_feed,
                  iconColor: Color(0xFF3F8CFF),
                  iconBgColor: Color(0xFFEAF2FF),
                  title: 'Live Bus Tracking',
                  subtitle: 'Real-time GPS tracking and live location updates.',
                ),
                FeatureCard(
                  icon: Icons.qr_code_scanner,
                  iconColor: Color(0xFF27AE60),
                  iconBgColor: Color(0xFFE8F8EE),
                  title: 'Student Boarding\nConfirmation',
                  subtitle: 'QR-based boarding and instant logging.',
                ),
                FeatureCard(
                  icon: Icons.notifications_active,
                  iconColor: Color(0xFFE67E22),
                  iconBgColor: Color(0xFFFDF2E9),
                  title: 'Parent Notifications',
                  subtitle: 'Instant alerts and safety updates.',
                ),
                FeatureCard(
                  icon: Icons.verified_user_outlined,
                  iconColor: Color(0xFF9B59B6),
                  iconBgColor: Color(0xFFF5EEF8),
                  title: 'Safety First',
                  subtitle: 'Emergency monitoring and smart transportation.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          
          // Analytics Badges
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderGrey),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: StatBadge(
                    icon: Icons.center_focus_strong,
                    iconColor: Colors.deepOrange,
                    value: '99.9%',
                    label: 'Tracking Accuracy',
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.grey.shade300),
                const Expanded(
                  child: StatBadge(
                    icon: Icons.security,
                    iconColor: Colors.blue,
                    value: '24/7',
                    label: 'Safety Monitoring',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
