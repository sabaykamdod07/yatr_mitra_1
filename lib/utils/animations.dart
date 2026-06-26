import 'package:flutter/animation.dart';

class Animations {
  Animations._();

  static Curve get smoothCurve => Curves.easeOutCubic;
  static Curve get bounceCurve => Curves.easeOutBack;
  static Curve get sharpCurve => Curves.easeInOutCubic;

  static Duration get fast => const Duration(milliseconds: 200);
  static Duration get normal => const Duration(milliseconds: 350);
  static Duration get slow => const Duration(milliseconds: 600);
  static Duration get verySlow => const Duration(milliseconds: 1000);
}