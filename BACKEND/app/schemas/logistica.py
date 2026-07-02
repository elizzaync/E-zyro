"""
Schemas Pydantic para el módulo de Logística (HU-15).

Modelan Materiales (catálogo + stock agregado) y Equipos/Herramientas
(unifica lo que en el legacy era la tabla `articulos`, separado por
campo `clase`).
"""
from __future__ import annotations

from datetime import date
from typing import Literal, Optional, List, Dict, Any

from pydantic import BaseModel, Field


# ═══════════════════════════════════════════════════════════════════════════
# MATERIALES (catálogo + stock agregado por empresa)
# ═══════════════════════════════════════════════════════════════════════════

class MaterialOut(BaseModel):
    id:           str
    codigo:       str
    nombre:       str
    categoriaId:  Optional[str] = None
    categoria:    str
    unidadId:     Optional[str] = None
    unidad:       str
    descripcion:  Optional[str] = None
    cantidad:     int
    stockMinimo: int = Field(0, alias="stockMinimo")
    almacenId:   Optional[str] = None
    almacen:     str
    precio:      Optional[float] = None
    activo:      bool
    tipo:        str = "consumible"   # consumible | herramienta
    marca:       Optional[str] = None         # conveniencia: leído de atributos.marca
    imagenUrl:   Optional[str] = None
    atributos:   Optional[Dict[str, Any]] = None
    # ── Nuevos campos HU-15 v2 ────────────────────────────────────────────────
    precioCompra:    Optional[float] = None
    serie:           Optional[str] = None
    marcaId:         Optional[str] = None   # FK → marca.id
    almacenMaterialId: Optional[str] = None  # FK directo en material (distinto del almacen de stock)

    class Config:
        populate_by_name = True


class MaterialIn(BaseModel):
    codigo:       Optional[str] = None
    nombre:       str
    categoriaId:  str
    unidadId:     str
    descripcion:  Optional[str] = None
    cantidad:     int = 0
    stockMinimo: int = 0
    almacenId:   str
    precio:      Optional[float] = None
    activo:      bool = True
    tipo:        str = "consumible"
    marca:       Optional[str] = None         # opcional; se guarda dentro de atributos
    imagenUrl:   Optional[str] = None
    atributos:   Optional[Dict[str, Any]] = None
    # ── Nuevos campos HU-15 v2 ────────────────────────────────────────────────
    precioCompra:    Optional[float] = None
    serie:           Optional[str] = None
    marcaId:         Optional[str] = None   # FK → marca.id
    almacenMaterialId: Optional[str] = None  # FK directo en material


class MaterialPatch(BaseModel):
    codigo:       Optional[str] = None
    nombre:       Optional[str] = None
    categoriaId:  Optional[str] = None
    unidadId:     Optional[str] = None
    descripcion:  Optional[str] = None
    cantidad:     Optional[int] = None
    stockMinimo: Optional[int] = None
    almacenId:   Optional[str] = None
    precio:      Optional[float] = None
    activo:      Optional[bool] = None
    tipo:        Optional[str] = None
    marca:       Optional[str] = None
    imagenUrl:   Optional[str] = None
    atributos:   Optional[Dict[str, Any]] = None
    # ── Nuevos campos HU-15 v2 ────────────────────────────────────────────────
    precioCompra:    Optional[float] = None
    serie:           Optional[str] = None
    marcaId:         Optional[str] = None
    almacenMaterialId: Optional[str] = None


class MaterialesListResponse(BaseModel):
    items: List[MaterialOut]
    total: int
    page:  int
    pageSize: int


# ═══════════════════════════════════════════════════════════════════════════
# EQUIPOS Y HERRAMIENTAS
# ═══════════════════════════════════════════════════════════════════════════

ClaseArticulo = Literal["equipo", "herramienta", "equipo_tecnologico"]
EstadoEquipo  = Literal["operativo", "en_mantenimiento", "fuera_de_servicio", "baja"]
FrecuenciaMant = Literal["ninguno", "mensual", "trimestral", "semestral", "anual"]


class EquipoOut(BaseModel):
    id:          str
    codigo:      str
    nombre:      str
    clase:       ClaseArticulo
    categoriaId: Optional[str] = None
    categoria:   str = ""
    marcaId:     Optional[str] = None
    marca:       Optional[str] = None
    modeloId:    Optional[str] = None
    modelo:      Optional[str] = None
    numeroSerie: Optional[str] = None
    almacenId:   Optional[str] = None
    ubicacion:   Optional[str] = None
    # Jerarquía geográfica (FK)
    ubicacionId: Optional[str] = None
    zonaId:      Optional[str] = None
    areaId:      Optional[str] = None
    cantidad:    int
    stockMinimo: int = 0
    estado:      EstadoEquipo
    requiereMantenimiento:     bool
    frecuenciaMantenimiento:   FrecuenciaMant
    proximaFechaMantenimiento: Optional[str] = None
    fechaAdquisicion:          Optional[str] = None
    fichaTecnica:              Optional[str] = None
    # ── Ingreso Directo: specs flexibles + datos de compra/asignación ───────
    asignadoA:     Optional[str] = None
    proveedor:     Optional[str] = None
    precioCompra:  Optional[float] = None
    fechaGarantia: Optional[str] = None
    imagenUrl:     Optional[str] = None
    observaciones: Optional[str] = None
    atributos:     Optional[Dict[str, Any]] = None


class EquipoIn(BaseModel):
    # codigo autogenerado si viene vacío
    codigo:      Optional[str] = None
    nombre:      str
    clase:       ClaseArticulo = "equipo"
    categoriaId: Optional[str] = None     # FK → categoria_equipo.id
    marcaId:     Optional[str] = None
    modeloId:    Optional[str] = None
    numeroSerie: Optional[str] = None
    almacenId:   Optional[str] = None
    ubicacionId: Optional[str] = None
    zonaId:      Optional[str] = None
    areaId:      Optional[str] = None
    cantidad:    int = 1
    stockMinimo: Optional[int] = None
    estado:      EstadoEquipo = "operativo"
    requiereMantenimiento:     bool = False
    frecuenciaMantenimiento:   FrecuenciaMant = "ninguno"
    proximaFechaMantenimiento: Optional[date] = None
    fechaAdquisicion:          Optional[date] = None
    fichaTecnica:              Optional[str]  = None
    # ── Ingreso Directo ─────────────────────────────────────────────────────
    asignadoA:     Optional[str]  = None
    proveedor:     Optional[str]  = None
    precioCompra:  Optional[float] = None
    fechaGarantia: Optional[date] = None
    imagenUrl:     Optional[str]  = None
    observaciones: Optional[str]  = None
    atributos:     Optional[Dict[str, Any]] = None


class EquipoPatch(BaseModel):
    codigo:      Optional[str] = None
    nombre:      Optional[str] = None
    clase:       Optional[ClaseArticulo] = None
    categoriaId: Optional[str] = None
    marcaId:     Optional[str] = None
    modeloId:    Optional[str] = None
    numeroSerie: Optional[str] = None
    almacenId:   Optional[str] = None
    ubicacionId: Optional[str] = None
    zonaId:      Optional[str] = None
    areaId:      Optional[str] = None
    cantidad:    Optional[int] = None
    estado:      Optional[EstadoEquipo] = None
    requiereMantenimiento:     Optional[bool] = None
    frecuenciaMantenimiento:   Optional[FrecuenciaMant] = None
    proximaFechaMantenimiento: Optional[date] = None
    fechaAdquisicion:          Optional[date] = None
    fichaTecnica:              Optional[str]  = None
    # ── Ingreso Directo ─────────────────────────────────────────────────────
    asignadoA:     Optional[str]  = None
    proveedor:     Optional[str]  = None
    precioCompra:  Optional[float] = None
    fechaGarantia: Optional[date] = None
    imagenUrl:     Optional[str]  = None
    observaciones: Optional[str]  = None
    atributos:     Optional[Dict[str, Any]] = None


class EquiposListResponse(BaseModel):
    items: List[EquipoOut]
    total: int
    page:  int
    pageSize: int


# ═══════════════════════════════════════════════════════════════════════════
# KPIs
# ═══════════════════════════════════════════════════════════════════════════

class LogisticaKpis(BaseModel):
    totalMateriales:     int
    materialesStockBajo: int
    totalEquipos:        int
    totalHerramientas:   int
    enMantenimiento:     int


# ═══════════════════════════════════════════════════════════════════════════
# CATÁLOGOS (categoria, almacén, tipo, marca, modelo, unidad)
# ═══════════════════════════════════════════════════════════════════════════

class CatalogoItem(BaseModel):
    """Salida estándar para selects del frontend."""
    id:     str
    nombre: str


class CatalogoIn(BaseModel):
    nombre: str


class ProcedimientoItem(BaseModel):
    orden: int
    nombre: str
    descripcion: Optional[str] = None


class ProcedimientosTemplateIn(BaseModel):
    procedimientos: List["ProcedimientoItem"]


class AlmacenOut(CatalogoItem):
    ubicacion: Optional[str] = None
    predeterminado: bool = False


class AlmacenIn(BaseModel):
    nombre:    str
    ubicacion: Optional[str] = None


class UnidadOut(CatalogoItem):
    abreviatura: Optional[str] = None


class UnidadIn(BaseModel):
    nombre:      str
    abreviatura: Optional[str] = None


class ModeloOut(CatalogoItem):
    marcaId: str


class ModeloIn(BaseModel):
    nombre:  str
    marcaId: str


# ═══════════════════════════════════════════════════════════════════════════
# REQUERIMIENTOS (HU-16 — control de stock y aprobación de pedidos)
# ═══════════════════════════════════════════════════════════════════════════

class RequerimientoItemOut(BaseModel):
    id:              str
    materialId:      Optional[str] = None
    equipoId:        Optional[str] = None
    nombre:          str
    unidad:          str
    cantidad:        int
    cantidadAprobada: Optional[int] = None
    stockDisponible: int = 0          # stock actual del material (0 si compra externa)
    enStock:         bool = False     # True si hay stock suficiente
    esCompraExterna: bool = False     # material_id NULL → no está en catálogo
    especificacion:  Optional[str] = None
    estadoItem:      str = "pendiente"
    agregadoPor:     Optional[str] = None
    tipo:            str = "material"  # material | herramienta | equipo


class RequerimientoOut(BaseModel):
    id:              str
    estado:          str
    fecha:           Optional[str] = None
    observacion:     Optional[str] = None
    observacionLogistico: Optional[str] = None
    proyectoId:      Optional[str] = None
    proyectoNombre:  str
    servicioId:      Optional[str] = None
    servicioNombre:  Optional[str] = None
    solicitanteId:   Optional[str] = None
    solicitanteNombre: str
    solicitanteFoto: Optional[str] = None
    items:           List[RequerimientoItemOut]
    # Entrega (si ya se entregó)
    entregadoPorNombre: Optional[str] = None
    recibidoPorNombre:  Optional[str] = None
    firmaUrl:           Optional[str] = None
    firmaEntregadorUrl: Optional[str] = None
    firmandoPorNombre:  Optional[str] = None
    firmandoDesde:      Optional[str] = None
    fechaEntrega:       Optional[str] = None
    # Firma del solicitante al enviar el lote (quién firmó el pedido)
    firmaSolicitanteUrl: Optional[str] = None


class RequerimientosListResponse(BaseModel):
    items: List[RequerimientoOut]
    total: int
    page:  int
    pageSize: int


class AprobarItemDecision(BaseModel):
    detalleId:        str
    decision:         Literal["aprobar", "compra", "rechazar"]
    cantidadAprobada: Optional[int] = None   # si None → toma cantidad solicitada (o stock disponible)


class AprobarBody(BaseModel):
    almacenId:    Optional[str] = None       # almacén de salida; si None usa el primero
    decisiones:   List[AprobarItemDecision] = []
    observacion:  Optional[str] = None


class RechazarBody(BaseModel):
    observacion: str


class EntregarBody(BaseModel):
    recibidoPorId:      Optional[str] = None
    firmaEntregadorUrl: Optional[str] = None
    firmaUrl:           Optional[str] = None
    notas:         Optional[str] = None


class FirmarBody(BaseModel):
    """El técnico confirma recepción en el detalle del servicio (firma virtual)."""
    recibidoPorId: Optional[str] = None        # si None usa el empleado del usuario logueado
    firmaUrl:      str                         # data-url de la firma


# ═══════════════════════════════════════════════════════════════════════════
# COMPRAS (HU-17 — tickets de compra generados desde requerimientos)
# ═══════════════════════════════════════════════════════════════════════════

class TicketCompraItemOut(BaseModel):
    id:                   str
    ticketId:             str
    materialId:           Optional[str] = None
    nombre:               str
    cantidad:             int            # cantidad a comprar (editable por logística)
    cantidadSugerida:     Optional[int]  = None  # sugerencia automática (solo lectura)
    stockAlAprobar:       Optional[int]  = None  # snapshot de stock al momento de aprobar
    stockMinimoAlAprobar: Optional[int]  = None  # snapshot de mínimo al momento de aprobar
    cantidadComprada:     Optional[int]  = None
    unidad:               str            = ""
    precioUnitario:       Optional[float] = None
    totalItem:            Optional[float] = None
    proveedorId:          Optional[str]   = None
    proveedorNombre:      Optional[str]   = None
    canalPersonalizado:   Optional[str]   = None
    factura:              Optional[str]   = None
    estadoItem:           str             = "pendiente"
    nota:                 Optional[str]   = None
    # Fase 1 — clasificación del ítem (material | equipo | herramienta)
    tipoItem:             str             = "material"
    # Fase 2 — ID del equipo/herramienta creado en inventario (solo para equipo/herramienta)
    equipoId:             Optional[str]   = None


class TicketCompraOut(BaseModel):
    id:                   str
    codigo:               str
    requerimientoId:      Optional[str] = None
    proyectoId:           Optional[str] = None
    proyectoNombre:       str
    servicioId:           Optional[str] = None
    servicioNombre:       Optional[str] = None
    solicitanteNombre:    str
    estado:               str
    items:                List[TicketCompraItemOut]
    modoUnificado:        Optional[bool]  = None
    proveedorUnicoId:     Optional[str]   = None
    proveedorUnicoNombre: Optional[str]   = None
    canalUnico:           Optional[str]   = None
    totalEstimado:        Optional[float] = None
    totalReal:            Optional[float] = None
    responsableId:        Optional[str]   = None
    responsableNombre:    Optional[str]   = None
    nota:                 Optional[str]   = None
    creadoEn:             str
    actualizadoEn:        Optional[str]   = None
    ingresoRegistrado:    bool            = False


class ComprasListResponse(BaseModel):
    items:    List[TicketCompraOut]
    total:    int
    page:     int
    pageSize: int


class ProcesarCompraItemBody(BaseModel):
    itemId:             str
    cantidadComprada:   int = 0
    precioUnitario:     Optional[float] = None
    proveedorId:        Optional[str]   = None
    proveedorNombre:    Optional[str]   = None
    canalPersonalizado: Optional[str]   = None
    factura:            Optional[str]   = None
    nota:               Optional[str]   = None


class ComprobanteCompraIn(BaseModel):
    """Datos del comprobante del proveedor para generar la CxP (Cuenta por
    Pagar) automática al cerrar la compra. Si se omite, no se crea CxP.
    El asiento contable lo arma cuentas_por_pagar_service (Db 60 + 40 / Cr 42)."""
    proveedorId:      str
    tipoDocumento:    str = "factura"        # factura|boleta|nota_credito|nota_debito
    numeroDocumento:  str
    fechaEmision:     date
    fechaVencimiento: date
    subtotal:         float
    igv:              float = 0.0
    moneda:           Optional[str] = None


class ComprobanteProveedorIn(BaseModel):
    """Comprobante de un proveedor en una compra MULTI-proveedor. El subtotal
    NO viene del front: el backend lo calcula como la suma de los ítems de ese
    proveedor en el ticket (subtotal fijo). El IGV sí (auto por tasa, editable)."""
    proveedorId:      str
    tipoDocumento:    str = "factura"
    numeroDocumento:  str
    fechaEmision:     date
    fechaVencimiento: date
    igv:              float = 0.0
    moneda:           Optional[str] = None


class ProcesarCompraBody(BaseModel):
    modoUnificado:        bool
    proveedorUnicoId:     Optional[str]   = None
    proveedorUnicoNombre: Optional[str]   = None
    canalUnico:           Optional[str]   = None
    nota:                 Optional[str]   = None
    completado:           bool            = False
    items:                List[ProcesarCompraItemBody] = []
    # Comprobante opcional → al completar la compra crea la CxP del proveedor.
    #  - modo "un proveedor"   → `comprobante` (uno; subtotal explícito).
    #  - modo multi-proveedor  → `comprobantes` (uno por proveedor; subtotal lo
    #    calcula el backend = suma de ítems de ese proveedor).
    comprobante:          Optional[ComprobanteCompraIn] = None
    comprobantes:         Optional[List[ComprobanteProveedorIn]] = None


class CancelarCompraBody(BaseModel):
    motivo: Optional[str] = None


class ComprasResumen(BaseModel):
    pendiente:  int = 0
    en_proceso: int = 0
    completado: int = 0
    cancelado:  int = 0


# ═══════════════════════════════════════════════════════════════════════════
# PROVEEDORES
# ═══════════════════════════════════════════════════════════════════════════

class ProveedorOut(BaseModel):
    id:        str
    nombre:    str
    ruc:       Optional[str] = None
    contacto:  Optional[str] = None
    email:     Optional[str] = None
    rating:    int = 0
    categorias: List[str] = []
    activo:    bool = True


class ProveedorIn(BaseModel):
    nombre:   str
    ruc:      Optional[str] = None
    contacto: Optional[str] = None
    email:    Optional[str] = None
    rating:   int = 0



# ═══════════════════════════════════════════════════════════════════════════
# SALIDAS DE MATERIALES (HU-18 — registro de entregas desde requerimientos)
# ═══════════════════════════════════════════════════════════════════════════

class SalidaItemOut(BaseModel):
    id:                 str
    nombre:             str
    unidad:             str
    cantidadSolicitada: int
    cantidadEntregada:  int
    # 'stock' = vino de inventario directamente | 'compra' = llegó vía ticket_compra
    origenItem:         str = "stock"


class SalidaOut(BaseModel):
    id:                  str
    fechaSolicitud:      Optional[str] = None
    fechaSalida:         Optional[str] = None
    proyectoId:          Optional[str] = None
    proyectoNombre:      str
    servicioId:          Optional[str] = None
    servicioNombre:      Optional[str] = None
    solicitanteNombre:   str
    entregadoPorNombre:  Optional[str] = None
    recibidoPorNombre:   Optional[str] = None
    firmaUrl:            Optional[str] = None
    observacion:         Optional[str] = None
    items:               List[SalidaItemOut]
    totalItems:          int
    totalUnidades:       int


class SalidasListResponse(BaseModel):
    items:    List[SalidaOut]
    total:    int
    page:     int
    pageSize: int


class SalidasKpis(BaseModel):
    totalSalidas:            int = 0
    totalUnidadesEntregadas: int = 0
    salidasEsteMes:          int = 0
    proyectosAtendidos:      int = 0


# ═══════════════════════════════════════════════════════════════════════════
# REGISTRO DE INGRESO (entrada a inventario desde compra completada)
# ═══════════════════════════════════════════════════════════════════════════

class IngresoItemBody(BaseModel):
    itemId:    str
    cantidad:  int
    almacenId: Optional[str] = None


class RegistrarIngresoBody(BaseModel):
    almacenId: Optional[str]      = None   # almacén por defecto
    items:     List[IngresoItemBody] = []


# ═══════════════════════════════════════════════════════════════════════════
# FASE 2 — VINCULAR ÍTEM A INVENTARIO (crear/enlazar nuevo material o equipo)
# ═══════════════════════════════════════════════════════════════════════════

class VincularInventarioBody(BaseModel):
    """
    Crea el ítem en su tabla de inventario y lo enlaza al ticket_compra_item.
    Solo necesario cuando el ítem es 'nuevo' (sin material_id ni equipo_id).

    Para tipo_item='material': requiere nombre y unidad.
    Para tipo_item='equipo'|'herramienta': requiere nombre (clase se toma de tipo_item).
    """
    # Campos comunes
    nombre:         str
    descripcion:    Optional[str]   = None
    almacenId:      Optional[str]   = None
    precioUnitario: Optional[float] = None   # actualiza precio del material / equipo

    # Solo para material
    unidad:         Optional[str]   = None   # obligatorio si tipo_item='material'
    categoriaId:    Optional[str]   = None
    stockMinimo:    Optional[int]   = 0
    codigo:         Optional[str]   = None

    # Solo para equipo / herramienta
    modelo:         Optional[str]   = None
    marca:          Optional[str]   = None
    numeroSerie:    Optional[str]   = None
    ubicacion:      Optional[str]   = None


# ═══════════════════════════════════════════════════════════════════════════
# INGRESOS — historial de compras recibidas que afectaron el inventario
# ═══════════════════════════════════════════════════════════════════════════

class IngresoItemOut(BaseModel):
    nombre:        str
    cantidad:      int
    unidad:        str
    tipoItem:      str
    precioUnitario: Optional[float] = None


class IngresoOut(BaseModel):
    id:               str
    ticketCodigo:     str
    fechaIngreso:     str
    proyectoNombre:   str
    servicioNombre:   Optional[str] = None
    solicitanteNombre: str
    proveedorNombre:  Optional[str] = None
    totalReal:        Optional[float] = None
    totalEstimado:    Optional[float] = None
    items:            List[IngresoItemOut]
    totalItems:       int
    totalUnidades:    int


class IngresosListResponse(BaseModel):
    items:    List[IngresoOut]
    total:    int
    page:     int
    pageSize: int


# ═══════════════════════════════════════════════════════════════════════════
# RETORNOS — devolución de materiales/equipos al finalizar un servicio
# ═══════════════════════════════════════════════════════════════════════════

class RetornoItemIn(BaseModel):
    detalleId:         str
    cantidadRetornada: int


class CrearRetornoBody(BaseModel):
    requerimientoId: str
    items:           List[RetornoItemIn]
    notaTecnico:     Optional[str] = None


class CrearRetornoServicioBody(BaseModel):
    """Crea un único retorno agrupando todos los ítems aprobados/entregados
    de todos los requerimientos del servicio."""
    proyectoServicioId: str
    items:              List[RetornoItemIn]
    notaTecnico:        Optional[str] = None


class RetornoItemPendienteOut(BaseModel):
    """Ítem candidato a devolución, ANTES de crear el Retorno — usado por el
    cliente (web/móvil) para armar el formulario de declaración."""
    detalleId:         str
    nombre:             str
    unidad:             str
    tipoItem:           str
    cantidadEntregada:  int
    esObligatorio:      bool


class RetornoItemsPendientesOut(BaseModel):
    items: List[RetornoItemPendienteOut]


class InspeccionItemIn(BaseModel):
    detalleId:          str
    cantidadConfirmada: int


class InspectionarRetornoBody(BaseModel):
    items:         List[InspeccionItemIn]
    notaLogistica: Optional[str] = None


class RetornoDetalleOut(BaseModel):
    id:                 str
    materialId:         Optional[str] = None
    equipoId:           Optional[str] = None
    nombre:             str
    unidad:             str
    tipoItem:           str
    cantidadEntregada:  int
    cantidadRetornada:  Optional[int] = None
    cantidadConfirmada: Optional[int] = None
    esObligatorio:      bool
    estadoItem:         str


class RetornoOut(BaseModel):
    id:                   str
    proyectoServicioId:   Optional[str] = None
    servicioNombre:       Optional[str] = None
    proyectoNombre:       Optional[str] = None
    requerimientoId:      Optional[str] = None
    estado:               str
    iniciadoPorNombre:    Optional[str] = None
    inspeccionadoPorNombre: Optional[str] = None
    notaTecnico:          Optional[str] = None
    notaLogistica:        Optional[str] = None
    creadoEn:             str
    completadoEn:         Optional[str] = None
    items:                List[RetornoDetalleOut]
    totalItems:           int
    itemsObligatorios:    int
    itemsPendientes:      int


class RetornosListResponse(BaseModel):
    items:    List[RetornoOut]
    total:    int
    page:     int
    pageSize: int


# ═══════════════════════════════════════════════════════════════════════════
# INCIDENCIAS — daños/fallos reportados sobre equipos y herramientas
# ═══════════════════════════════════════════════════════════════════════════

class CrearIncidenciaBody(BaseModel):
    equipoId:           str
    proyectoServicioId: Optional[str]  = None
    numeroSerie:        Optional[str]  = None   # equipos únicos
    cantidadAfectada:   int            = 1      # herramientas genéricas
    tipoFalla:          str            = "otro"
    descripcion:        str


class ResolverIncidenciaBody(BaseModel):
    estado:        str              # 'en_reparacion' | 'solucionado' | 'dado_de_baja'
    resolucionNota: Optional[str]  = None


class IncidenciaOut(BaseModel):
    id:                  str
    equipoId:            str
    equipoNombre:        str
    equipoClase:         str
    equipoSinSerie:      bool
    proyectoServicioId:  Optional[str] = None
    servicioNombre:      Optional[str] = None
    reportadoPorNombre:  Optional[str] = None
    resueltoPorNombre:   Optional[str] = None
    numeroSerie:         Optional[str] = None
    cantidadAfectada:    int
    tipoFalla:           str
    descripcion:         str
    estado:              str
    resolucionNota:      Optional[str] = None
    fechaReporte:        str
    fechaResolucion:     Optional[str] = None


class IncidenciasListResponse(BaseModel):
    items:    List[IncidenciaOut]
    total:    int
    page:     int
    pageSize: int


class EquipoStockDesglose(BaseModel):
    """Desglose de stock para el tooltip de inventario."""
    equipoId:        str
    cantidadTotal:   int
    operativos:      int
    enIncidencia:    int
    incidenciasAbiertas: int


# ═══════════════════════════════════════════════════════════════════════════
# INGRESO DIRECTO  (compra/registro manual sin requerimiento previo)
# ═══════════════════════════════════════════════════════════════════════════
#
# Flujo: cabecera (quién compró + fecha + destino) + lote de ítems de cualquier
# clase (material | equipo | herramienta | equipo_tecnologico). Reutiliza la
# maquinaria de inventario (MovimientoInventario + costeo + asiento). El destino
# decide si el ingreso queda en stock o se imputa a un servicio/correctivo.

ClaseArticuloIngreso = Literal["material", "equipo", "herramienta", "equipo_tecnologico"]
TipoDestino          = Literal["stock", "servicio", "correctivo"]
ModoItem             = Literal["nuevo", "existente"]


class FormFieldDef(BaseModel):
    """Definición de un campo del formulario dinámico por clase de artículo."""
    key:         str                       # nombre del campo (atributos.<key> o campo nativo)
    label:       str
    inputType:   str = "text"              # text|number|date|select|textarea|image|ip|mac
    required:    bool = False
    nativo:      bool = False              # True → columna propia; False → va en atributos
    grupo:       Optional[str] = None      # sección del form (Básico, Specs, Compra…)
    placeholder: Optional[str] = None
    sugerencias: Optional[List[str]] = None  # autocompletar (procesador, RAM…)
    opciones:    Optional[List[CatalogoItem]] = None  # para selects servidos por catálogo


class FormSchemaOut(BaseModel):
    """Esquema del formulario para una clase de artículo."""
    clase:  ClaseArticuloIngreso
    titulo: str
    campos: List[FormFieldDef]


class DestinoIn(BaseModel):
    tipo:         TipoDestino = "stock"
    servicioId:   Optional[str] = None     # requerido si tipo=servicio
    correctivoId: Optional[str] = None     # requerido si tipo=correctivo


class IngresoItemIn(BaseModel):
    """Un ítem del lote de ingreso. Reúne campos comunes + atributos flexibles."""
    clase:        ClaseArticuloIngreso
    modo:         ModoItem = "nuevo"
    existenteId:  Optional[str] = None     # requerido si modo=existente (id material/equipo)
    # comunes
    nombre:       Optional[str] = None     # requerido si modo=nuevo
    codigo:       Optional[str] = None
    descripcion:  Optional[str] = None
    cantidad:     int = 1
    precioCompra: Optional[float] = None   # costo unitario → valuación
    almacenId:    Optional[str] = None
    imagenUrl:    Optional[str] = None
    # material
    categoriaId:  Optional[str] = None
    unidadId:     Optional[str] = None
    stockMinimo:  Optional[int] = None
    # equipo / herramienta / equipo_tecnologico
    categoriaEquipoId: Optional[str] = None  # FK → categoria_equipo.id
    marcaId:           Optional[str] = None
    modeloId:     Optional[str] = None
    marca:        Optional[str] = None     # texto libre (materiales / sin catálogo)
    numeroSerie:  Optional[str] = None
    ubicacionId:  Optional[str] = None
    zonaId:       Optional[str] = None
    areaId:       Optional[str] = None
    estado:       Optional[str] = None
    asignadoA:    Optional[str] = None
    fechaGarantia: Optional[date] = None
    observaciones: Optional[str] = None
    # libres por tipo (procesador, RAM, IP, MAC, SO…)
    atributos:    Optional[Dict[str, Any]] = None


class IngresoDirectoIn(BaseModel):
    personalCompraId: Optional[str] = None  # empleado que compró (default: usuario logueado)
    fechaCompra:      Optional[date] = None  # default: hoy
    proveedor:        Optional[str] = None
    destino:          DestinoIn = DestinoIn()
    notas:            Optional[str] = None
    items:            List[IngresoItemIn]
    # Comprobante opcional → crea la CxP del proveedor (Cuenta por Pagar).
    comprobante:      Optional[ComprobanteCompraIn] = None


class IngresoItemResult(BaseModel):
    clase:     ClaseArticuloIngreso
    articuloId: str                        # id del material/equipo creado o reusado
    nombre:    str
    cantidad:  int
    creado:    bool                        # True=nuevo registro, False=existente


class IngresoDirectoResult(BaseModel):
    ingresoId:  str                        # id del ticket sintético generado
    totalItems: int
    destino:    TipoDestino
    items:      List[IngresoItemResult]
    cxpFacturaId: Optional[str] = None     # CxP creada (si vino comprobante)
    cxpError:     Optional[str] = None      # motivo si la CxP no se pudo crear
