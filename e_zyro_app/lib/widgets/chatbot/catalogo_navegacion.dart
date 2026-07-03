import 'package:flutter/material.dart';

import '../../screens/finanzas/finanzas_navegacion.dart';
import '../../screens/finanzas/pantalla_finanzas.dart';
import '../../screens/logistica/almacen/pantalla_requerimientos_logistica.dart';
import '../../screens/logistica/almacen/pantalla_transferencias_almacen.dart';
import '../../screens/logistica/pantalla_ingreso_directo.dart';
import '../../screens/pantalla_accesos_portal.dart';
import '../../screens/pantalla_auditoria.dart';
import '../../screens/pantalla_auditoria_general.dart';
import '../../screens/pantalla_bandeja_solicitudes.dart';
import '../../screens/pantalla_calibraciones.dart';
import '../../screens/pantalla_catalogos.dart';
import '../../screens/pantalla_centro_ayuda.dart';
import '../../screens/pantalla_compras_logistica.dart';
import '../../screens/pantalla_comunicados.dart';
import '../../screens/pantalla_configuracion.dart';
import '../../screens/pantalla_control_asistencias.dart';
import '../../screens/pantalla_cotizaciones.dart';
import '../../screens/pantalla_dashboards.dart';
import '../../screens/pantalla_documentos_sst.dart';
import '../../screens/pantalla_drive.dart';
import '../../screens/pantalla_equipos_intervenidos.dart';
import '../../screens/pantalla_equipos_logistica.dart';
import '../../screens/pantalla_evaluaciones.dart';
import '../../screens/pantalla_galeria.dart';
import '../../screens/pantalla_garantias_correctivos.dart';
import '../../screens/pantalla_gestion_usuarios.dart';
import '../../screens/pantalla_indicadores.dart';
import '../../screens/pantalla_inventario_panel.dart';
import '../../screens/pantalla_itse.dart';
import '../../screens/pantalla_materiales_logistica.dart';
import '../../screens/pantalla_mi_espacio.dart';
import '../../screens/pantalla_movimientos_logistica.dart';
import '../../screens/pantalla_pendientes.dart';
import '../../screens/pantalla_personal.dart';
import '../../screens/pantalla_personal_hub.dart';
import '../../screens/pantalla_planos.dart';
import '../../screens/pantalla_plantillas_procedimiento.dart';
import '../../screens/pantalla_privacidad_seguridad.dart';
import '../../screens/pantalla_privilegios.dart';
import '../../screens/pantalla_proveedores_logistica.dart';
import '../../screens/pantalla_tramites.dart';
import '../../screens/pantalla_vacaciones.dart';
import '../../utils/app_session.dart';

/// Catálogo de navegación del asistente E-zyro — fuente única de TODAS las
/// pantallas que el LLM puede pedir abrir vía acción `{tipo:'navegar'}`.
///
/// El asistente nunca ejecuta nada por sí mismo: emite la clave como dato,
/// la app la muestra como chip "Abrir X" y es el usuario quien toca. El
/// catálogo (filtrado por los permisos del usuario) viaja como contexto en
/// cada request, así el LLM siempre sabe exactamente qué destinos existen
/// sin redeployar el servidor del chatbot.
class PantallaNavegable {
  final String nombre; // etiqueta visible en el chip
  final String descripcion; // qué encuentra el usuario ahí (lo lee el LLM)
  final bool Function(AppSession) visible; // gate por permiso (igual al menú)
  /// null cuando el destino es una pestaña del MainShell: pushear una tab como
  /// pantalla suelta crea una copia sin bottom nav ni OfflineOverlay (ISSUE-002).
  final WidgetBuilder? builder;
  final int? tabIndex; // índice en MainShell si el destino es una pestaña
  const PantallaNavegable(
      this.nombre, this.descripcion, this.visible, this.builder,
      {this.tabIndex});
}

bool _todos(AppSession _) => true;

/// Mapa completo clave → pantalla. Se construye por llamada (barato) para que
/// Finanzas salga de [finanzasSecciones], que ya filtra por permisos.
Map<String, PantallaNavegable> catalogoNavegacion() {
  final m = <String, PantallaNavegable>{
    // ── Logística (claves históricas del chatbot: NO renombrar) ──────────
    'bandeja_requerimientos': PantallaNavegable(
        'Requerimientos',
        'Bandeja de requerimientos de materiales y su aprobación',
        _todos,
        (_) => const PantallaRequerimientosLogistica()),
    // Pestaña 2 del MainShell: se conmuta la tab, no se pushea (ISSUE-002).
    'catalogo_logistica': PantallaNavegable(
        'Logística',
        'Módulo de logística: catálogo de materiales con stock y solicitudes',
        (s) => s.canGestInventario,
        null,
        tabIndex: 2),
    'operaciones': PantallaNavegable(
        'Operaciones',
        'Servicios y proyectos en curso, calendario de operaciones',
        _todos,
        null,
        tabIndex: 1),
    'inventario': PantallaNavegable(
        'Panel de inventario',
        'Stock actual por almacén, materiales y equipos',
        _todos,
        (_) => const PantallaInventarioPanel()),
    'compras': PantallaNavegable('Compras',
        'Órdenes de compra y su estado', _todos,
        (_) => const PantallaComprasLogistica()),
    'movimientos': PantallaNavegable(
        'Movimientos',
        'Historial de entradas y salidas de inventario',
        _todos,
        (_) => const PantallaMovimientosLogistica()),
    'materiales': PantallaNavegable('Materiales',
        'Catálogo de materiales', _todos,
        (_) => const PantallaMaterialesLogistica()),
    'equipos': PantallaNavegable('Equipos', 'Catálogo de equipos de logística',
        _todos, (_) => const PantallaEquiposLogistica()),
    'proveedores': PantallaNavegable('Proveedores',
        'Directorio de proveedores', _todos,
        (_) => const PantallaProveedoresLogistica()),
    'transferencias': PantallaNavegable(
        'Transferencias',
        'Transferencias de stock entre almacenes',
        _todos,
        (_) => const PantallaTransferenciasAlmacen()),
    'ingreso_directo': PantallaNavegable(
        'Ingreso directo',
        'Ingreso de materiales al almacén sin orden de compra',
        _todos,
        (_) => const PantallaIngresoDirecto()),

    // ── Trabajo (visibles para todos, igual que el menú Más) ─────────────
    'mi_espacio': PantallaNavegable(
        'Mi perfil',
        'TODO lo personal del empleado: marcar MI asistencia, ver MIS boletas '
            'de pago, MIS solicitudes y MI perfil',
        _todos,
        (_) => const PantallaMiEspacio()),
    'pendientes': PantallaNavegable('Mis pendientes',
        'Tareas y pendientes asignados al usuario', _todos,
        (_) => const PantallaPendientes()),
    'comunicados': PantallaNavegable('Comunicados',
        'Comunicados internos de la empresa', _todos,
        (_) => const ComunicadosScreen()),
    'tramites': PantallaNavegable(
        'Trámites y Permisos',
        'Solicitudes de permisos, licencias y otros trámites del empleado',
        _todos,
        (_) => const PantallaTramites()),
    'drive': PantallaNavegable('Drive de empresa',
        'Documentos compartidos de la empresa', _todos,
        (_) => const PantallaDrive()),

    // ── Administración (mismos gates que el menú Más) ────────────────────
    'privilegios': PantallaNavegable(
        'Privilegios',
        'Gestión de roles y permisos del sistema',
        (s) => s.canGestionarPrivilegios,
        (_) => const PantallaPrivilegios()),
    'gestion_usuarios': PantallaNavegable(
        'Gestión de usuarios',
        'Alta, baja y edición de usuarios',
        (s) => s.canGestionarUsuarios,
        (_) => const PantallaGestionUsuarios()),
    'rrhh': PantallaNavegable(
        'Recursos Humanos',
        'Hub de RR.HH.: asistencias, solicitudes, personal, evaluaciones y vacaciones',
        (s) => s.canVerControlAsistencias || s.canVerPersonal,
        (_) => const PantallaPersonalHub()),
    'dashboards': PantallaNavegable(
        'Dashboards',
        'Tableros e indicadores gerenciales',
        (s) => s.canVerDashboards,
        (_) => const PantallaDashboards()),
    'accesos_portal': PantallaNavegable(
        'Accesos Portal Cliente',
        'Credenciales de clientes para el portal externo',
        (s) => s.isAdmin,
        (_) => const PantallaAccesosPortal()),
    'auditoria': PantallaNavegable(
        'Registro de Auditoría',
        'Bitácora de acciones de los usuarios en el sistema',
        (s) => s.canVerAuditoria,
        (_) => const PantallaAuditoria()),
    'auditoria_general': PantallaNavegable(
        'Auditoría General',
        'Auditoría global del sistema (superadmin)',
        (s) => s.esSuperAdmin,
        (_) => const PantallaAuditoriaGeneral()),

    // ── RR.HH. (pantallas internas del hub, mismos gates) ────────────────
    'control_asistencias': PantallaNavegable(
        'Control de asistencias',
        'Asistencias del personal: marcas, tardanzas y validación',
        (s) => s.canVerControlAsistencias,
        (_) => const PantallaControlAsistencias()),
    'bandeja_solicitudes': PantallaNavegable(
        'Bandeja de solicitudes',
        'Solicitudes del personal pendientes de aprobar',
        (s) => s.canVerControlAsistencias || s.canVerPersonal,
        (_) => const PantallaBandejaSolicitudes()),
    'indicadores': PantallaNavegable(
        'Indicadores',
        'Indicadores de RR.HH.',
        (s) => s.canVerIndicadores,
        (_) => const PantallaIndicadores()),
    'vacaciones': PantallaNavegable(
        'Vacaciones',
        'Solicitudes y saldos de vacaciones del personal',
        (s) => s.canVerVacaciones,
        (_) => const PantallaVacaciones()),
    'config_evaluaciones': PantallaNavegable(
        'Evaluaciones',
        'Configuración y plantillas de evaluaciones de personal',
        (s) => s.canVerEvaluacion,
        (_) => const ConfigEvaluacionesScreen()),
    'personal': PantallaNavegable(
        'Personal y sesiones',
        'Fichas del personal y sesiones activas por dispositivo',
        (s) => s.canVerPersonal,
        (_) => const PantallaPersonal()),

    // ── Módulos operativos (mismos gates que el menú Más) ────────────────
    'cotizaciones': PantallaNavegable(
        'Cotizaciones',
        'Cotizaciones a clientes y su estado',
        (s) =>
            s.isAdmin ||
            s.hasPerm('cotizaciones:ver') ||
            s.hasPerm('cotizaciones:gestionar'),
        (_) => const PantallaCotizaciones()),
    'finanzas': PantallaNavegable(
        'Finanzas',
        'Hub del módulo de Finanzas (contabilidad, cuentas, tesorería…)',
        (s) => s.canVerFinanzas,
        (_) => const PantallaFinanzas()),
    'mantenimientos': PantallaNavegable(
        'Mantenimientos',
        'Equipos intervenidos en servicios de mantenimiento',
        (s) => s.canVerEquipoIntervenido,
        (_) => const PantallaEquiposIntervenidos()),
    'calibraciones': PantallaNavegable(
        'Calibraciones',
        'Calibraciones de equipos y sus certificados',
        (s) => s.canVerCalibracion,
        (_) => const PantallaCalibraciones()),
    'garantias_correctivos': PantallaNavegable(
        'Garantías / Correctivos',
        'Garantías y trabajos correctivos',
        (s) => s.canVerCorrectivo,
        (_) => const PantallaGarantiasCorrectivos()),
    'itse': PantallaNavegable(
        'Inspección ITSE',
        'Inspecciones técnicas de seguridad en edificaciones',
        (s) => s.canVerItse,
        (_) => const PantallaItse()),
    'catalogos': PantallaNavegable(
        'Catálogos',
        'Catálogos maestros del sistema',
        (s) => s.canVerCatalogos,
        (_) => const PantallaCatalogos()),
    'procedimientos_estandar': PantallaNavegable(
        'Procedimientos estándar',
        'Plantillas de procedimientos de trabajo',
        (s) => s.canVerCatalogos,
        (_) => const PantallaPlantillasProcedimiento()),
    'documentos_sst': PantallaNavegable(
        'Documentos SST',
        'Documentos de seguridad y salud en el trabajo',
        (s) => s.canVerDocumentosSst,
        (_) => const PantallaDocumentosSst()),

    // ── Recursos y ayuda ─────────────────────────────────────────────────
    'galeria': PantallaNavegable(
        'Galería',
        'Galería de fotos de servicios y proyectos',
        (s) => s.canVerGaleria,
        (_) => const PantallaGaleria()),
    'planos': PantallaNavegable('Planos',
        'Planos de proyectos', _todos, (_) => const PantallaPlanos()),
    'centro_ayuda': PantallaNavegable('Centro de Ayuda',
        'Ayuda y preguntas frecuentes', _todos,
        (_) => const PantallaCentroAyuda()),
    'privacidad_seguridad': PantallaNavegable(
        'Privacidad y Seguridad',
        'Ajustes de privacidad, contraseña y biometría',
        _todos,
        (_) => const PantallaPrivacidadSeguridad()),
    'configuracion': PantallaNavegable('Configuración',
        'Preferencias de la app', _todos, (_) => const PantallaConfiguracion()),
  };

  // Submódulos de Finanzas: se reutiliza su mapa de navegación (fuente única,
  // ya filtrado por permisos). Claves: finanzas_<id> (p. ej. finanzas_cxp).
  for (final sec in finanzasSecciones(AppSession.i)) {
    for (final mod in sec.modulos) {
      m['finanzas_${mod.id}'] = PantallaNavegable(
          mod.titulo, mod.subtitulo, _todos, mod.builder);
    }
  }
  return m;
}

/// Catálogo visible para el usuario actual, listo para viajar como contexto
/// al LLM: [{clave, nombre, descripcion}]. El chatbot lo usa para saber qué
/// puede emitir en la acción `abrir_pantalla`.
List<Map<String, String>> pantallasParaLlm() => [
      for (final e in catalogoNavegacion().entries)
        if (e.value.visible(AppSession.i))
          {
            'clave': e.key,
            'nombre': e.value.nombre,
            'descripcion': e.value.descripcion,
          },
    ];
