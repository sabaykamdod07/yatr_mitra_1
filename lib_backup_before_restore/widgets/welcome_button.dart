import 'package:flutter/material.dart';

class WelcomeButton extends StatefulWidget {
  final String text;
  final bool isGradient;
  final VoidCallback onPressed;

  const WelcomeButton({
    super.key,
    required this.text,
    required this.isGradient,
    required this.onPressed,
  });

  @override
  State<WelcomeButton> createState() => _WelcomeButtonState();
}

class _WelcomeButtonState extends State<WelcomeButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          // 🚀 ADDED: Direct high-priority gesture responder wrapper
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: widget.isGradient
                ? Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5E17EB), Color(0xFF00F0FF)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00F0FF).withOpacity(_isHovered ? 0.4 : 0.2),
                          blurRadius: _isHovered ? 12 : 6,
                          offset: const Offset(0, 3),
                        )
                    ],
                  ),
                  child: Center(
                    child: Text(
                      widget.text,
                      style: const TextStyle(
                        color: Colors.white, 
                        fontSize: 15, 
                        fontWeight: FontWeight.bold, 
                        letterSpacing: 1
                      ),
                    ),
                  ),
                )
              : OutlinedButton(
                  onPressed: widget.onPressed,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: _isHovered ? Colors.cyanAccent : Colors.white.withOpacity(0.4), 
                      width: 1.5
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  child: Text(
                    widget.text,
                    style: TextStyle(
                      color: _isHovered ? Colors.cyanAccent : Colors.white, 
                      fontSize: 15, 
                      fontWeight: FontWeight.bold, 
                      letterSpacing: 1
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
