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
  codigo: string;                  // autogenerado por backend (MAT-NNNN)
  nombre: string;
  categoriaId: string | null;
  categoria: string;               // nombre denormalizado
  unidadId: string | null;
  unidad: string;                  // nombre denormalizado
  descripcion: string | null;
  cantidad: number;                // stock actual
  stockMinimo: number;
  almacenId: string | null;
  almacen: string;                 // nombre denormalizado
  precio: number | null;
  activo: boolean;
}

/** Equipo o herramienta del inventario (antes tabla `articulos`). */
export interface EquipoHerramienta {
  id: string;
  codigo: string;                  // autogenerado por backend (EQ-NNNN / HR-NNNN)
  nombre: string;
  clase: ClaseArticulo;            // equipo | herramienta
  tipoId: string | null;
  tipo: string;                    // nombre de familia/tipo (denormalizado)
  marcaId: string | null;
  marca: string | null;            // nombre denormalizado
  modeloId: string | null;
  modelo: string | null;
  numeroSerie: string | null;
  almacenId: string | null;
  ubicacion: string | null;
  cantidad: number;
  estado: EstadoEquipo;
  // ── Mantenimiento ──
  requiereMantenimiento: boolean;
  frecuenciaMantenimiento: FrecuenciaMantenimiento;
  proximaFechaMantenimiento: string | null;
  fechaAdquisicion: string | null;
  fichaTecnica: string | null;
}

/** Item simple para selects de catálogo. */
export interface CatalogoItem {
  id: string;
  nombre: string;
}
export interface AlmacenItem extends CatalogoItem { ubicacion?: string | null; }
export interface UnidadItem  extends CatalogoItem { abreviatura?: string | null; }
export interface ModeloItem  extends CatalogoItem { marcaId: string; }

// ── Requerimientos (HU-16) ──────────────────────────────────────────────────

export interface RequerimientoItem {
  id: string;
  materialId: string | null;
  nombre: string;
  unidad: string;
  cantidad: number;
  cantidadAprobada: number | null;
  stockDisponible: number;
  enStock: boolean;
  esCompraExterna: boolean;
  especificacion: string | null;
  estadoItem: string;          // pendiente | aprobado | para_compra | rechazado
  agregadoPor: string | null;
}

export interface Requerimiento {
  id: string;
  estado: string;              // pendiente | aprobado | listo | entregado | rechazado
  fecha: string | null;
  observacion: string | null;
  observacionLogistico: string | null;
  proyectoId: string | null;
  proyectoNombre: string;
  servicioId: string | null;
  servicioNombre: string | null;
  solicitanteId: string | null;
  solicitanteNombre: string;
  solicitanteFoto: string | null;
  items: RequerimientoItem[];
  entregadoPorNombre: string | null;
  recibidoPorNombre: string | null;
  firmaUrl: string | null;
  fechaEntrega: string | null;
}

export interface AprobarItemDecision {
  detalleId: string;
  decision: 'aprobar' | 'compra' | 'rechazar';
  cantidadAprobada?: number | null;
}

// ── Compras (HU-17) ────────────────────────────────────────────────────────

export type EstadoCompra = 'pendiente' | 'en_proceso' | 'completado' | 'cancelado';

export interface Proveedor {
  id: string;
  nombre: string;
  ruc: string | null;
  contacto: string | null;
  email: string | null;
  rating: number;            // 1-5
  categorias: string[];
  activo: boolean;
}

export interface TicketCompraItem {
  id: string;
  ticketId: string;
  materialId: string | null;
  nombre: string;
  cantidad: number;
  cantidadComprada: number | null;
  unidad: string;
  precioUnitario: number | null;
  totalItem: number | null;
  proveedorId: string | null;
  proveedorNombre: string | null;
  canalPersonalizado: string | null;
  factura: string | null;
  estadoItem: 'pendiente' | 'comprado' | 'cancelado';
  nota: string | null;
}

export interface TicketCompra {
  id: string;
  codigo: string;
  requerimientoId: string;
  proyectoId: string | null;
  proyectoNombre: string;
  servicioId: string | null;
  servicioNombre: string | null;
  solicitanteNombre: string;
  estado: EstadoCompra;
  items: TicketCompraItem[];
  modoUnificado: boolean | null;
  proveedorUnicoId: string | null;
  proveedorUnicoNombre: string | null;
  canalUnico: string | null;
  totalEstimado: number | null;
  totalReal: number | null;
  responsableId: string | null;
  responsableNombre: string | null;
  nota: string | null;
  creadoEn: string;
  actualizadoEn: string | null;
}

export interface ProcesarCompraItemPayload {
  itemId: string;
  cantidadComprada: number;
  precioUnitario: number | null;
  proveedorId?: string | null;
  proveedorNombre?: string | null;
  canalPersonalizado?: string | null;
  factura?: string | null;
  nota?: string | null;
}

export interface ProcesarCompraPayload {
  modoUnificado: boolean;
  proveedorUnicoId?: string | null;
  proveedorUnicoNombre?: string | null;
  canalUnico?: string | null;
  nota?: string | null;
  completado: boolean;
  items: ProcesarCompraItemPayload[];
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

// ── Salidas de Materiales (HU-18) ──────────────────────────────────────────

export interface SalidaItem {
  id: string;
  nombre: string;
  unidad: string;
  cantidadSolicitada: number;
  cantidadEntregada: number;
}

export interface Salida {
  id: string;
  fechaSolicitud: string | null;
  fechaSalida: string | null;
  proyectoId: string | null;
  proyectoNombre: string;
  servicioId: string | null;
  servicioNombre: string | null;
  solicitanteNombre: string;       // quien pidio (jefe de proyecto)
  entregadoPorNombre: string | null; // quien entrego (logística)
  recibidoPorNombre: string | null;  // quien retiró (técnico en campo)
  firmaUrl: string | null;
  observacion: string | null;
  items: SalidaItem[];
  totalItems: number;
  totalUnidades: number;
}

export interface SalidasKpis {
  totalSalidas: number;
  totalUnidadesEntregadas: number;
  salidasEsteMes: number;
  proyectosAtendidos: number;
}

/** KPIs de la cabecera de Logística. */
export interface LogisticaKpis {
  totalMateriales: number;
  materialesStockBajo: number;
  totalEquipos: number;
  totalHerramientas: number;
  enMantenimiento: number;
}
