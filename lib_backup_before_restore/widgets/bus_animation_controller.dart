import 'package:flutter/material.dart';
import 'dart:math';
/// Controls the 3-phase bus animation sequence
class BusAnimationController {
  // Phase boundaries (as fractions of total animation)
  static const double phase1End = 0.45; // Bus approaching
  static const double phase2End = 0.75; // Bus moving up
  // Phase 3: 0.75 - 1.0  // Content reveal

  /// Returns the bus scale for the approaching phase
  static double getBusScale(double animationValue) {
    if (animationValue <= phase1End) {
      // Ease-out curve: bus comes from far (0.05) to full size (1.0)
      final t = animationValue / phase1End;
      final eased = _easeOutBack(t);
      return 0.05 + (1.0 - 0.05) * eased;
    }
    return 1.0;
  }

  /// Returns the bus vertical offset (negative = up)
  static double getBusVerticalOffset(double animationValue, double maxOffset) {
    if (animationValue <= phase1End) return 0.0;
    if (animationValue <= phase2End) {
      final t = (animationValue - phase1End) / (phase2End - phase1End);
      final eased = _easeInOutCubic(t);
      return -maxOffset * eased;
    }
    return -maxOffset;
  }

  /// Returns opacity for each content element (staggered)
  static double getContentOpacity(double animationValue, int index) {
    if (animationValue <= phase2End) return 0.0;
    final t = (animationValue - phase2End) / (1.0 - phase2End);
    final staggerDelay = index * 0.12;
    final adjustedT = (t - staggerDelay).clamp(0.0, 1.0);
    return _easeOutCubic(adjustedT);
  }

  /// Returns slide offset for content elements
  static double getContentSlideOffset(double animationValue, int index) {
    if (animationValue <= phase2End) return 30.0;
    final t = (animationValue - phase2End) / (1.0 - phase2End);
    final staggerDelay = index * 0.12;
    final adjustedT = (t - staggerDelay).clamp(0.0, 1.0);
    return 30.0 * (1.0 - _easeOutCubic(adjustedT));
  }

  /// Returns the bus opacity (fades in during approach)
  static double getBusOpacity(double animationValue) {
    if (animationValue <= 0.05) return animationValue / 0.05;
    return 1.0;
  }

  /// Easing: ease-out back (slight overshoot)
  static double _easeOutBack(double t) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2);
  }

  /// Easing: ease-in-out cubic
  static double _easeInOutCubic(double t) {
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3).toDouble() / 2;
  }

  /// Easing: ease-out cubic
  static double _easeOutCubic(double t) {
    return 1 - pow(1 - t, 3).toDouble();
  }
}