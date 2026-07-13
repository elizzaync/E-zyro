/// Utilidades visuales compartidas del Portal Empresa: color por estado,
/// chips, formato de fechas e iniciales para avatares.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// MERGE "por valor" con lib/theme/ez_theme.dart (2026-07-13): el verde queda
// en brandExternal (#16A34A, única desviación permitida del Portal); ámbar/
// rojo/gris se igualan a warning/danger/inkMuted del sistema.
const Color kPortalVerde = Color(0xFF16A34A); // = ez brandExternal
const Color kPortalAmbar = Color(0xFFD98A16); // = ezLight.warning
const Color kPortalRojo = Color(0xFFD6584F); // = ezLight.danger
const Color kPortalGris = Color(0xFF8B968B); // = ezLight.inkMuted

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

/// Card estándar del portal — delega al CardTheme del sistema Ez (radio 20,
/// superficie y sombra/borde según tema), solo conserva el margen compacto.
Widget cardPortal({required Widget child, EdgeInsetsGeometry? margin}) => Card(
      margin: margin ?? const EdgeInsets.only(bottom: 8),
      child: child,
    );
