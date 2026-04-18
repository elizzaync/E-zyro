import 'package:flutter/material.dart';

/// Tarjeta de estadística reutilizable usada en HomeScreen y OperationsScreen.
///
/// [label]         → texto debajo del número
/// [value]         → número a mostrar (String para flexibilidad)
/// [iconData]      → ícono del encabezado
/// [color]         → color de fondo de la tarjeta
/// [iconColor]     → color del ícono
/// [isHighlighted] → si es true, el texto del valor usa el color del ícono
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
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
              color: isHighlighted ? iconColor : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isHighlighted ? iconColor : Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
