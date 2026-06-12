/// Utilidades visuales compartidas del Portal Empresa: color por estado,
/// chips, formato de fechas e iniciales para avatares.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const Color kPortalVerde = Color(0xFF16A34A); // completado / operativo
const Color kPortalAmbar = Color(0xFFF59E0B); // en proceso
const Color kPortalRojo = Color(0xFFEF4444); // cancelado / inoperativo
const Color kPortalGris = Color(0xFF6B7280); // pendiente / sin dato

/// Color sobrio por estado: completado=verde, en proceso=ámbar,
/// cancelado=rojo, pendiente (y desconocidos)=gris.
Color colorPorEstado(String? estado) {
  final e = (estado ?? '').toLowerCase().trim().replaceAll('_', ' ');
  if (e.startsWith('complet') ||
      e.startsWith('finaliz') ||
      e == 'aprobado' ||
      e == 'entregado' ||
      e == 'operativo') {
    return kPortalVerde;
  }
  if (e.contains('proceso') ||
      e.contains('progreso') ||
      e.contains('curso') ||
      e == 'activo') {
    return kPortalAmbar;
  }
  if (e.startsWith('cancel') ||
      e.startsWith('rechaz') ||
      e.startsWith('venc') ||
      e == 'inoperativo') {
    return kPortalRojo;
  }
  return kPortalGris;
}

/// Etiqueta legible de un estado: "en_proceso" → "En proceso".
String etiquetaEstado(String? estado) {
  final e = (estado ?? '').trim().replaceAll('_', ' ');
  if (e.isEmpty) return 'Sin estado';
  return e[0].toUpperCase() + e.substring(1).toLowerCase();
}

/// Fecha ISO (o null) → "dd/MM/yyyy"; si no hay dato devuelve [vacio].
String formatearFecha(String? iso, {String vacio = '—'}) {
  if (iso == null || iso.trim().isEmpty) return vacio;
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat('dd/MM/yyyy').format(d.toLocal());
}

/// Iniciales para avatares: "María Pérez" → "MP".
String iniciales(String nombre, [String? apellido]) {
  String primera(String? s) {
    final t = (s ?? '').trim();
    return t.isEmpty ? '' : t[0].toUpperCase();
  }

  final partes = nombre.trim().split(RegExp(r'\s+'));
  final a = primera(partes.isNotEmpty ? partes.first : '');
  final b = (apellido != null && apellido.trim().isNotEmpty)
      ? primera(apellido)
      : primera(partes.length > 1 ? partes.last : '');
  final r = '$a$b';
  return r.isEmpty ? '?' : r;
}

/// Chip compacto de estado (fondo suave + borde del color del estado).
Widget chipEstado(String? estado) {
  final color = colorPorEstado(estado);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Text(
      etiquetaEstado(estado),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

/// Card sobria estándar del portal (bordes redondeados, sin sombra fuerte).
Widget cardPortal({required Widget child, EdgeInsetsGeometry? margin}) => Card(
      margin: margin ?? const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
      ),
      child: child,
    );
