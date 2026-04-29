import 'package:flutter/material.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData iconData;
  final Color color;
  final Color iconColor;
  final bool isHighlighted;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.iconData,
    required this.color,
    required this.iconColor,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? surface : color,
        borderRadius: BorderRadius.circular(14),
        border: isDark
            ? Border.all(color: iconColor.withValues(alpha: 0.75), width: 1.5)
            : null,
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: iconColor.withValues(alpha: 0.35),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        children: [
          Icon(iconData, size: 22, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? iconColor : (isHighlighted ? iconColor : Colors.black87),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? iconColor.withValues(alpha: 0.8)
                  : (isHighlighted ? iconColor : Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
