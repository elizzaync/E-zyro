// ─────────────────────────────────────────────────────────────────────────
// Fuente única de verdad para las FASES del ciclo de vida de un servicio.
// La usan tanto el detalle del servicio como las tarjetas de la lista para
// que ambas vistas muestren exactamente las mismas etapas (concordancia).
// ─────────────────────────────────────────────────────────────────────────

export type EstadoServicio = 'Pendiente' | 'En_Proceso' | 'Completado' | 'Cancelado';

export interface FaseServicio {
  n: number;
  nombre: string;
  sub: string;
}

/** Las 4 fases por las que pasa un servicio, en orden. */
export const FASES_SERVICIO: FaseServicio[] = [
  { n: 1, nombre: 'Preparación', sub: 'Equipo y materiales' },
  { n: 2, nombre: 'En sitio',    sub: 'Inspección y medición' },
  { n: 3, nombre: 'Ejecución',   sub: 'Aplicación y pruebas' },
  { n: 4, nombre: 'Cierre',      sub: 'Informe y firma' },
];

/**
 * Fase activa (1-4) derivada del estado del servicio y su progreso.
 * Es un único cálculo compartido para que detalle y tarjetas no se desincronicen.
 *
 * - Pendiente  → 1 (Preparación: se arma equipo, tareas y materiales)
 * - En_Proceso → 2 (En sitio) hasta el 50 %, luego 3 (Ejecución)
 * - Completado → 4 (Cierre)
 */
export function faseActiva(estado: string, progreso = 0): number {
  switch (estado) {
    case 'Pendiente':  return 1;
    case 'En_Proceso': return progreso >= 50 ? 3 : 2;
    case 'Completado': return 4;
    default:           return 1;
  }
}

/** Clase de cada paso del stepper respecto de la fase activa. */
export function faseClase(n: number, estado: string, progreso = 0): 'done' | 'active' | 'muted' {
  if (estado === 'Completado') return 'done';
  const activa = faseActiva(estado, progreso);
  if (n < activa) return 'done';
  if (n === activa) return 'active';
  return 'muted';
}
