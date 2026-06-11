"""
Backfill script — one-time run.

For every equipo_intervenido where proyecto_servicio_id IS NULL,
look up the most recent historial_inspeccion record and copy its
proyecto_servicio_id to the equipment. Also propagates proyecto_id
and cliente_id through the relation tree.

Usage:
    python backfill_ei_service_link.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))

from sqlalchemy import text
from app.db.database import SessionLocal

def run():
    db = SessionLocal()
    try:
        # Find all equipment without a service link that have at least one inspection
        rows = db.execute(text("""
            SELECT DISTINCT ON (ei.id)
                ei.id                          AS ei_id,
                hi.proyecto_servicio_id        AS ps_id,
                ps.proyecto_id                 AS proyecto_id,
                p.cliente_id                   AS cliente_id
            FROM equipo_intervenido ei
            JOIN historial_inspeccion hi ON hi.equipo_intervenido_id = ei.id
            LEFT JOIN proyecto_servicio ps ON ps.id = hi.proyecto_servicio_id
            LEFT JOIN proyecto          p  ON p.id  = ps.proyecto_id
            WHERE ei.proyecto_servicio_id IS NULL
              AND hi.proyecto_servicio_id IS NOT NULL
            ORDER BY ei.id, hi.created_at DESC
        """)).fetchall()

        if not rows:
            print("Nada que actualizar — todos los registros ya tienen proyecto_servicio_id.")
            return

        updated = 0
        for r in rows:
            ei_id, ps_id, proyecto_id, cliente_id = r
            db.execute(text("""
                UPDATE equipo_intervenido
                SET proyecto_servicio_id = :ps_id,
                    proyecto_id          = COALESCE(proyecto_id, :proy_id),
                    cliente_id           = COALESCE(cliente_id,  :cid),
                    updated_at           = NOW()
                WHERE id = :eid
            """), {
                "ps_id":   str(ps_id),
                "proy_id": str(proyecto_id) if proyecto_id else None,
                "cid":     str(cliente_id)  if cliente_id  else None,
                "eid":     str(ei_id),
            })
            updated += 1

        db.commit()
        print(f"Backfill completado: {updated} equipo(s) actualizado(s).")

    except Exception as exc:
        db.rollback()
        print(f"ERROR: {exc}")
        raise
    finally:
        db.close()

if __name__ == "__main__":
    run()
