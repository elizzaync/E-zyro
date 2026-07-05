"""Helper compartido para calcular la cantidad sugerida al generar un ticket de
compra automático (faltante + colchón de reposición sobre el mínimo).

Usado por:
  - app/routers/logistica.py  → _crear_ticket_compra() (compra de materiales
    desde un requerimiento aprobado)
  - app/routers/prestamo.py   → _crear_ticket_compra_faltante() (compra directa
    del faltante de un préstamo de equipos/herramientas)
"""
from __future__ import annotations


def calcular_cantidad_sugerida(faltante: int, stock_minimo: int, factor_reposicion: float = 1.5) -> int:
    """Sugerencia de compra: cubre el faltante + repone el mínimo con un 50% de colchón.

    - faltante: unidades que hacen falta para cubrir lo solicitado (>= 0).
    - stock_minimo: mínimo de reserva configurado para el material/equipo.
    - factor_reposicion: multiplicador de colchón sobre el mínimo (default 1.5 = 50% extra).

    Si la suma resultara 0 o negativa (edge case), se usa al menos el faltante
    (nunca negativo) para no generar un ticket inútil.
    """
    reposicion = int(stock_minimo * factor_reposicion)
    sugerida = faltante + reposicion
    return sugerida if sugerida > 0 else max(faltante, 0)
