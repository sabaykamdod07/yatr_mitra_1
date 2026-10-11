import 'package:flutter/material.dart';

import '../theme/ym_ui.dart';

/// Row of child "pills" for a parent with more than one child.
/// Shows nothing when there is only one child.
class ParentChildPicker extends StatelessWidget {
  const ParentChildPicker({
    super.key,
    required this.children,
    required this.selected,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> children;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (children.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: YmPressable(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: i == selected
                          ? const LinearGradient(
                              colors: [Ym.amber, Ym.amberDark])
                          : null,
                      color: i == selected ? null : Colors.white,
                      boxShadow: Ym.shadow(Ym.navy, 0.07),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school_rounded,
                            size: 16,
                            color: i == selected ? Ym.navy : Ym.grey),
                        const SizedBox(width: 7),
                        Text(
                          (children[i]['student_name'] ?? 'Student')
                              .toString()
                              .trim()
                              .split(' ')
                              .first,
                          style: Ym.t(13,
                              color: i == selected ? Ym.navy : Ym.grey,
                              w: FontWeight.w800),
                        ),
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