"""Schemas de Indicadores de desempeño (Punto 3.4)."""
from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel


class IndicadorEmpleado(BaseModel):
    empleado_id:           str
    empleado_nombre:       Optional[str] = None
    cargo:                 Optional[str] = None
    # Evaluaciones de desempeño (completadas)
    evaluaciones_total:    int = 0
    promedio_evaluaciones: Optional[float] = None     # 1-10
    # Asistencia
    asistencia_total:      int = 0
    asistencia_validados:  int = 0
    puntualidad_pct:       Optional[float] = None      # validados / total * 100
    # Vacaciones
    vacaciones_disponible: float = 0.0
    vacaciones_gozado:     int = 0
    # Score global (0-100): mezcla evaluación y puntualidad cuando hay datos
    score_global:          Optional[float] = None
    # Tendencia: promedio de evaluación (1-10) por periodo, los últimos N
    # periodos con evaluaciones completadas, en orden cronológico ascendente.
    # Vacío/1 elemento = sin suficiente historial para graficar tendencia.
    tendencia:             List[float] = []


class ResumenEmpresa(BaseModel):
    empleados:                int = 0
    promedio_evaluaciones:    Optional[float] = None   # 1-10
    puntualidad_promedio:     Optional[float] = None   # %
    calificacion_cliente:     Optional[float] = None   # 1-5 (promedio empresa)
    top: List[IndicadorEmpleado] = []                  # mejores por score_global
