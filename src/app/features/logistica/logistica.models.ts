// ─────────────────────────────────────────────────────────────────────────
// Modelos del módulo de Logística (Inventario)
// Adaptado del sistema anterior (tablas `materiales` y `articulos`) al nuevo
// esquema PostgreSQL: material/stock/categoria_material y equipo/tipo_equipo/
// plan_mantenimiento.
//
// Nota de negocio: en el sistema anterior los EQUIPOS y las HERRAMIENTAS
// vivían mezclados en `articulos`. Aquí se separan con el campo `clase`
// ('equipo' | 'herramienta'). La mayoría de equipos requieren mantenimiento
// (mensual o trimestral); muchas herramientas no lo requieren.
// ─────────────────────────────────────────────────────────────────────────

/** Material consumible / insumo de almacén. */
export interface MaterialLog {
  id: string;
  codigo: string;
  nombre: string;
  categoriaId: string | null;
  categoria: string;
  unidad: string;
  descripcion: string | null;
  cantidad: number;        // stock actual
  stockMinimo: number;
  almacenId: string | null;
  almacen: string;
  precio: number | null;
  activo: boolean;
}

/** Equipo o herramienta del inventario (antes tabla `articulos`). */
export interface EquipoHerramienta {
  id: string;
  codigo: string;
  nombre: string;
  clase: ClaseArticulo;              // equipo | herramienta
  tipo: string;                      // tipo de equipo / familia
  marca: string | null;
  modelo: string | null;
  numeroSerie: string | null;
  ubicacion: string | null;
  cantidad: number;
  estado: EstadoEquipo;
  // ── Mantenimiento ──
  requiereMantenimiento: boolean;
  frecuenciaMantenimiento: FrecuenciaMantenimiento;
  proximaFechaMantenimiento: string | null;   // ISO yyyy-mm-dd
  fechaAdquisicion: string | null;
  fichaTecnica: string | null;
}

export type ClaseArticulo = 'equipo' | 'herramienta';

export type EstadoEquipo =
  | 'operativo'
  | 'en_mantenimiento'
  | 'fuera_de_servicio'
  | 'baja';

export type FrecuenciaMantenimiento =
  | 'ninguno'
  | 'mensual'
  | 'trimestral'
  | 'semestral'
  | 'anual';

// ── Catálogos para selects de los formularios ──────────────────────────────

export interface OpcionSelect {
  value: string;
  label: string;
}

export const ESTADOS_EQUIPO: { value: EstadoEquipo; label: string }[] = [
  { value: 'operativo',          label: 'Operativo' },
  { value: 'en_mantenimiento',   label: 'En mantenimiento' },
  { value: 'fuera_de_servicio',  label: 'Fuera de servicio' },
  { value: 'baja',               label: 'De baja' },
];

export const FRECUENCIAS_MANTENIMIENTO: { value: FrecuenciaMantenimiento; label: string }[] = [
  { value: 'ninguno',     label: 'Sin mantenimiento' },
  { value: 'mensual',     label: 'Mensual' },
  { value: 'trimestral',  label: 'Trimestral (cada 3 meses)' },
  { value: 'semestral',   label: 'Semestral (cada 6 meses)' },
  { value: 'anual',       label: 'Anual' },
];

export const CLASES_ARTICULO: { value: ClaseArticulo; label: string }[] = [
  { value: 'equipo',      label: 'Equipo' },
  { value: 'herramienta', label: 'Herramienta' },
];

/** KPIs de la cabecera de Logística. */
export interface LogisticaKpis {
  totalMateriales: number;
  materialesStockBajo: number;
  totalEquipos: number;
  totalHerramientas: number;
  enMantenimiento: number;
}
