import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, Boolean
from app.db.database import Base

def generate_uuid():
    return str(uuid.uuid4())

class Empresa(Base):
    __tablename__ = "empresa"

    id = Column(String(36), primary_key=True, default=generate_uuid)
    razon_social = Column(String(200), nullable=False)
    ruc = Column(String(20), nullable=False, unique=True)
    email_contacto = Column(String(150), nullable=False)
    # Contacto / domicilio fiscal para encabezar la boleta de pago (formalidad).
    telefono = Column(String(20), nullable=True)
    direccion = Column(String(200), nullable=True)
    slug = Column(String(100), nullable=False, unique=True)
    estado = Column(String(20), nullable=False)
    fecha_registro = Column(DateTime, nullable=False, default=datetime.utcnow)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    # ── Finanzas (Fase 0): configuración contable por empresa ──
    moneda_funcional = Column(String(3), nullable=False, default="PEN")
    regimen_tributario = Column(String(30), nullable=False, default="general")
    # ── Planilla (Fase 2): descuento automático de tardanzas (configurable) ──
    # Si está activo, el cálculo de planilla descuenta las tardanzas por minutos;
    # si se desactiva, las tardanzas solo se registran (descuento manual).
    descuento_tardanza_auto = Column(Boolean, nullable=False, default=True)
    # ── Planilla (Fase 8): régimen LABORAL (micro/pequeña/general, Ley 32353)
    # y esquema de pago de nómina. Distinto de `regimen_tributario` (SUNAT).
    regimen_laboral = Column(String(20), nullable=False, default="micro")
    esquema_pago_planilla = Column(String(20), nullable=False, default="quincenal")
    # ── Planilla (2026-07-07): gate de pago de sobretiempo sin trámite ──
    # Decisión de negocio CON RIESGO LEGAL, configurable por empresa (default
    # False): si está en False, solo se paga el sobretiempo cubierto por un
    # trámite de Permanencia Extra APROBADO; el resto queda como alerta sin
    # pagar. Si está en True, se paga TODO el sobretiempo registrado (SUNAFIL
    # presume autorización tácita) y el trámite queda solo como alerta.
    pagar_horas_extra_sin_tramite = Column(Boolean, nullable=False, default=False)