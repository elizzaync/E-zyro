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
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? surface : color,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(color: iconColor.withValues(alpha: 0.65), width: 1.5)
            : null,
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: iconColor.withValues(alpha: 0.30),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icono con fondo circular suave
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: isDark ? 0.18 : 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(iconData, size: 20, color: iconColor),
          ),
          const SizedBox(height: 8),
          // Valor con animación cuando cambia
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Text(
              value,
              key: ValueKey(value),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? iconColor
                    : (isHighlighted ? iconColor : Colors.black87),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? iconColor.withValues(alpha: 0.80)
                  : (isHighlighted ? iconColor : Colors.grey.shade600),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
