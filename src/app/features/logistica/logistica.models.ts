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
  clase: ClaseArticulo;            // equipo | herramienta | equipo_tecnologico
  categoriaId: string | null;
  categoria: string;               // nombre de categoría (denormalizado)
  marcaId: string | null;
  marca: string | null;            // nombre denormalizado
  modeloId: string | null;
  modelo: string | null;           // variante específica del producto bajo la marca
  numeroSerie: string | null;
  almacenId: string | null;
  ubicacion: string | null;
  cantidad: number;
  stockMinimo: number;             // extraído de atributos.stock_minimo
  precioCompra: number | null;
  observaciones: string | null;
  estado: EstadoEquipo;
  // ── Mantenimiento ──
  requiereMantenimiento: boolean;
  frecuenciaMantenimiento: FrecuenciaMantenimiento;
  proximaFechaMantenimiento: string | null;
  fechaAdquisicion: string | null;
  fichaTecnica: string | null;
  atributos: Record<string, any> | null;
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
  estado: string;  // pendiente | comprando | listo | entregado | rechazado | aprobado
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
  firmaEntregadorUrl: string | null;
  fechaEntrega: string | null;
  firmandoPorNombre: string | null;
  firmandoDesde: string | null;
}

export interface EntregarPayload {
  recibidoPorId?: string | null;
  firmaUrl?: string | null;
  firmaEntregadorUrl?: string | null;
  notas?: string | null;
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
  cantidadSugerida: number | null;
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
  tipoItem: 'material' | 'equipo' | 'herramienta';
  equipoId: string | null;
}

export interface VincularInventarioPayload {
  nombre: string;
  descripcion?: string | null;
  almacenId?: string | null;
  precioUnitario?: number | null;
  // material
  unidad?: string | null;
  categoriaId?: string | null;
  stockMinimo?: number | null;
  codigo?: string | null;
  // equipo / herramienta
  modelo?: string | null;
  marca?: string | null;
  numeroSerie?: string | null;
  ubicacion?: string | null;
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
  ingresoRegistrado: boolean;
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

export type ClaseArticulo = 'equipo' | 'herramienta' | 'equipo_tecnologico';

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
  { value: 'equipo',              label: 'Equipo' },
  { value: 'herramienta',         label: 'Herramienta' },
  { value: 'equipo_tecnologico',  label: 'Equipo TI' },
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

// ── Ingreso de materiales comprados (HU-17 → inventario) ───────────────────

export interface IngresoItem {
  itemId: string;
  cantidad: number;
}

export interface RegistrarIngresoPayload {
  items: IngresoItem[];
}

/** KPIs de la cabecera de Logística. */
export interface LogisticaKpis {
  totalMateriales: number;
  materialesStockBajo: number;
  totalEquipos: number;
  totalHerramientas: number;
  enMantenimiento: number;
}

// ── Ingresos ──────────────────────────────────────────────────────────────

export interface IngresoItemLog {
  nombre: string;
  cantidad: number;
  unidad: string;
  tipoItem: 'material' | 'equipo' | 'herramienta';
  precioUnitario: number | null;
}

export interface Ingreso {
  id: string;
  ticketCodigo: string;
  fechaIngreso: string;
  proyectoNombre: string;
  servicioNombre: string | null;
  solicitanteNombre: string;
  proveedorNombre: string | null;
  totalReal: number | null;
  totalEstimado: number | null;
  items: IngresoItemLog[];
  totalItems: number;
  totalUnidades: number;
}

// ── Retornos ──────────────────────────────────────────────────────────────

export interface RetornoDetalle {
  id: string;
  materialId: string | null;
  equipoId: string | null;
  nombre: string;
  unidad: string;
  tipoItem: 'material' | 'equipo' | 'herramienta';
  cantidadEntregada: number;
  cantidadRetornada: number | null;
  cantidadConfirmada: number | null;
  esObligatorio: boolean;
  estadoItem: 'pendiente' | 'confirmado' | 'faltante';
}

export interface Retorno {
  id: string;
  proyectoServicioId: string | null;
  servicioNombre: string | null;
  proyectoNombre: string | null;
  requerimientoId: string | null;
  estado: 'enviado' | 'inspeccion' | 'completado';
  iniciadoPorNombre: string | null;
  inspeccionadoPorNombre: string | null;
  notaTecnico: string | null;
  notaLogistica: string | null;
  creadoEn: string;
  completadoEn: string | null;
  items: RetornoDetalle[];
  totalItems: number;
  itemsObligatorios: number;
  itemsPendientes: number;
}

// ── Incidencias ───────────────────────────────────────────────────────────

export type EstadoIncidencia = 'abierta' | 'en_reparacion' | 'solucionado' | 'dado_de_baja';
export type TipoFalla = 'no_enciende' | 'dano_fisico' | 'desgaste' | 'perdida' | 'otro';

export interface Incidencia {
  id: string;
  equipoId: string;
  equipoNombre: string;
  equipoClase: 'equipo' | 'herramienta';
  equipoSinSerie: boolean;
  proyectoServicioId: string | null;
  servicioNombre: string | null;
  reportadoPorNombre: string | null;
  resueltoPorNombre: string | null;
  numeroSerie: string | null;
  cantidadAfectada: number;
  tipoFalla: TipoFalla;
  descripcion: string;
  estado: EstadoIncidencia;
  resolucionNota: string | null;
  fechaReporte: string;
  fechaResolucion: string | null;
}

export interface EquipoStockDesglose {
  equipoId: string;
  cantidadTotal: number;
  operativos: number;
  enIncidencia: number;
  incidenciasAbiertas: number;
}
