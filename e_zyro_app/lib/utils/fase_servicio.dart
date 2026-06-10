// ─────────────────────────────────────────────────────────────────────────
//  Fuente única de verdad de las FASES del ciclo de vida de un servicio.
//  Espejo de `fase-servicio.ts` de la web para que móvil y web muestren
//  exactamente las mismas etapas y el mismo cálculo de fase activa.
// ─────────────────────────────────────────────────────────────────────────

class FaseServicio {
  final int n;
  final String nombre;
  final String sub;
  const FaseServicio(this.n, this.nombre, this.sub);
}

/// Las 4 fases por las que pasa un servicio, en orden.
const List<FaseServicio> fasesServicio = [
  FaseServicio(1, 'Preparación', 'Equipo y materiales'),
  FaseServicio(2, 'En sitio', 'Inspección y medición'),
  FaseServicio(3, 'Ejecución', 'Aplicación y pruebas'),
  FaseServicio(4, 'Cierre', 'Informe y firma'),
];

/// Fase activa (1-4) derivada del estado del servicio y el progreso de TAREAS.
/// - Pendiente  → 1 (Preparación)
/// - En_Proceso + 0 % tareas → 2 (En sitio: el equipo llegó, aún no ejecuta)
/// - En_Proceso + alguna tarea marcada → 3 (Ejecución)
/// - Completado → 4 (Cierre)
int faseActiva(String estado, [double progreso = 0]) {
  switch (estado) {
    case 'Pendiente':
      return 1;
    case 'En_Proceso':
      return progreso > 0 ? 3 : 2;
    case 'Completado':
      return 4;
    default:
      return 1;
  }
}

/// Clase visual de cada paso del stepper respecto de la fase activa.
/// Devuelve 'done' | 'active' | 'muted'.
String faseClase(int n, String estado, [double progreso = 0]) {
  if (estado == 'Completado') return 'done';
  final activa = faseActiva(estado, progreso);
  if (n < activa) return 'done';
  if (n == activa) return 'active';
  return 'muted';
}
