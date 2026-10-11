import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Yatra Mitra UI kit.
///
/// Same look as the rest of the app: creamy-yellow background, navy text,
/// amber accents, Plus Jakarta Sans (headings) + Inter (body) like the login
/// screen. Every student screen builds on these pieces so they all match.
class Ym {
  Ym._();

  // palette (matches AppTheme / AppColors / driver + admin dashboards)
  static const navy = Color(0xFF0F1B4C);
  static const blue = Color(0xFF3B5BFF);
  static const amber = Color(0xFFFBB03B);
  static const amberDark = Color(0xFFF59E0B);
  static const green = Color(0xFF059669);
  static const red = Color(0xFFE0403A);
  static const purple = Color(0xFF7C3AED);
  static const grey = Color(0xFF8892AA);
  static const line = Color(0xFFF0E2C8);

  static const creamTop = Color(0xFFFFF8EC);
  static const creamMid = Color(0xFFFDF3E7);
  static const creamBot = Color(0xFFFCEAD3);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F1B4C), Color(0xFF2B45D8)],
  );

  static TextStyle h(double size,
          {Color color = navy, FontWeight w = FontWeight.w800}) =>
      GoogleFonts.plusJakartaSans(
          fontSize: size, fontWeight: w, color: color, height: 1.15);

  static TextStyle t(double size,
          {Color color = navy, FontWeight w = FontWeight.w500}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: color);

  static List<BoxShadow> shadow([Color c = navy, double o = 0.08]) => [
        BoxShadow(
            color: c.withOpacity(o), blurRadius: 24, offset: const Offset(0, 10)),
      ];
}

// ───────────────────────── BACKGROUND + PAGE ─────────────────────────

/// Cream gradient with soft decorative blobs. Put it behind any screen.
class YmBackground extends StatelessWidget {
  const YmBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Ym.creamTop, Ym.creamMid, Ym.creamBot],
              ),
            ),
          ),
        ),
        Positioned(
          top: -70,
          right: -60,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: Ym.amber.withOpacity(0.16)),
          ),
        ),
        Positioned(
          bottom: 120,
          left: -90,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: Ym.blue.withOpacity(0.06)),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// Standard inner page: gradient background, glass back button, centred title.
class YmPage extends StatelessWidget {
  const YmPage({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ym.creamTop,
      body: YmBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: [
                    YmRoundButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(title,
                              textAlign: TextAlign.center, style: Ym.h(19)),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(subtitle!,
                                  textAlign: TextAlign.center,
                                  style: Ym.t(11.5, color: Ym.grey)),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: 44, child: trailing),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// White circular icon button with a soft shadow.
class YmRoundButton extends StatelessWidget {
  const YmRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badge = 0,
    this.color = Ym.navy,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badge;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return YmPressable(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: Ym.shadow(Ym.navy, 0.10),
            ),
            child: Icon(icon, size: size * 0.42, color: color),
          ),
          if (badge > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2),
                decoration: BoxDecoration(
                  color: Ym.red,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(badge > 9 ? '9+' : '$badge',
                    style: Ym.t(9.5, color: Colors.white, w: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── CARDS + BUTTONS ─────────────────────────

class YmCard extends StatelessWidget {
  const YmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.gradient,
    this.color = Colors.white,
    this.radius = 24,
    this.margin,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color color;
  final double radius;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Ym.line.withOpacity(0.7), width: 0.8),
        boxShadow: Ym.shadow(),
      ),
      child: child,
    );
    return onTap == null
        ? box
        : YmPressable(onTap: onTap, scale: 0.98, child: box);
  }
}

class YmButton extends StatelessWidget {
  const YmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.outline = false,
    this.color,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool outline;
  final Color? color; // set for danger/green buttons (white text)
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final base = color ?? Ym.amber;
    final fg = outline ? Ym.navy : (color == null ? Ym.navy : Colors.white);

    final content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
        else if (icon != null)
          Icon(icon, size: 19, color: fg),
        if (loading || icon != null) const SizedBox(width: 9),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: Ym.h(14.5, color: fg, w: FontWeight.w800)),
        ),
      ],
    );

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: YmPressable(
        onTap: enabled ? onPressed : null,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            gradient: outline
                ? null
                : LinearGradient(colors: [
                    base,
                    Color.lerp(base, Colors.black, 0.14)!,
                  ]),
            color: outline ? Colors.white.withOpacity(0.7) : null,
            border: outline ? Border.all(color: Ym.amber, width: 1.6) : null,
            boxShadow: outline
                ? null
                : [
                    BoxShadow(
                        color: base.withOpacity(0.38),
                        blurRadius: 18,
                        offset: const Offset(0, 8)),
                  ],
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Scales slightly while pressed. Wrap any tappable widget.
class YmPressable extends StatefulWidget {
  const YmPressable(
      {super.key, required this.child, this.onTap, this.scale = 0.95});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<YmPressable> createState() => _YmPressableState();
}

class _YmPressableState extends State<YmPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _down = false),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ───────────────────────── SMALL PIECES ─────────────────────────

class YmChip extends StatelessWidget {
  const YmChip(this.text,
      {super.key, this.color = Ym.blue, this.icon, this.solid = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? color : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12.5, color: fg),
            const SizedBox(width: 4),
          ],
          Text(text, style: Ym.t(11.5, color: fg, w: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Soft tinted rounded-square with an icon.
class YmIconBadge extends StatelessWidget {
  const YmIconBadge(
      {super.key, required this.icon, this.color = Ym.amberDark, this.size = 46});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.24), color.withOpacity(0.08)],
        ),
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}

/// Solid gradient tile with a white icon (quick actions).
class YmGradientTile extends StatelessWidget {
  const YmGradientTile(
      {super.key, required this.icon, required this.color, this.size = 56, this.child});
  final IconData? icon;
  final Color color;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.36),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.18)!],
        ),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 7)),
        ],
      ),
      child: Center(
        child: child ?? Icon(icon, color: Colors.white, size: size * 0.46),
      ),
    );
  }
}

class YmSectionTitle extends StatelessWidget {
  const YmSectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(right: 9),
            decoration: BoxDecoration(
                color: Ym.amber, borderRadius: BorderRadius.circular(4)),
          ),
          Expanded(child: Text(text, style: Ym.h(18))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class YmEmpty extends StatelessWidget {
  const YmEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.color = Ym.amberDark,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withOpacity(0.07))),
                  Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withOpacity(0.12))),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: Ym.shadow(color, 0.18),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Ym.h(17)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(subtitle!,
                    textAlign: TextAlign.center,
                    style: Ym.t(13, color: Ym.grey)),
              ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── ANIMATION ─────────────────────────

/// Fades + slides a child in. Use `index` to stagger a list of sections.
class YmFadeSlide extends StatefulWidget {
  const YmFadeSlide({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  State<YmFadeSlide> createState() => _YmFadeSlideState();
}

class _YmFadeSlideState extends State<YmFadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 70 * math.min(widget.index, 10)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(_a),
        child: widget.child,
      ),
    );
  }
}

/// A dot with a soft expanding ring. Used for "live" indicators.
class YmPulse extends StatefulWidget {
  const YmPulse({super.key, this.color = Ym.green, this.size = 9});
  final Color color;
  final double size;

  @override
  State<YmPulse> createState() => _YmPulseState();
}

class _YmPulseState extends State<YmPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.6,
      height: s * 2.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: (1 - _c.value) * 0.55,
              child: Transform.scale(
                scale: 1 + _c.value * 1.6,
                child: Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: widget.color)),
              ),
            ),
            Container(
                width: s,
                height: s,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ],
        ),
      ),
    );
  }
}

/// Shimmering placeholder block shown while data loads.
class YmSkeleton extends StatefulWidget {
  const YmSkeleton({super.key, this.height = 80, this.width, this.radius = 22});
  final double height;
  final double? width;
  final double radius;

  @override
  State<YmSkeleton> createState() => _YmSkeletonState();
}

class _YmSkeletonState extends State<YmSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1.5 + 3 * _c.value, 0),
            end: Alignment(-0.5 + 3 * _c.value, 0),
            colors: const [
              Color(0xFFF3E8D2),
              Color(0xFFFCF6EA),
              Color(0xFFF3E8D2),
            ],
          ),
        ),
      ),
    );
  }
}

class YmSkeletonList extends StatelessWidget {
  const YmSkeletonList({super.key, this.count = 4, this.height = 92});
  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, __) => YmSkeleton(height: height),
    );
  }
}