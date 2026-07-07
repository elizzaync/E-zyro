# Seed de tipos de equipo + plantillas de procedimientos de mantenimiento.
# Origen: tabla `procedimientos_mtto` del ERP PHP anterior (dump 2026-07-07).
# Idempotente: si el tipo ya existe para la empresa, solo completa la plantilla
# si está vacía (nunca pisa una plantilla editada).
#
# Correr contra prod:
#   railway run -s Postgres-SjrN python migrations/seed_tipo_equipo_procedimientos.py
# (usa DATABASE_PUBLIC_URL; local también sirve con esa variable en el entorno)

import json
import os
import sys
import uuid

from sqlalchemy import create_engine, text

EMPRESA_LIKE = "%SYSTEMTIC%"  # E-SystemTIC (empresa principal)

# ponytail: TOMACORRIENTES y LUMINARIAS traen los placeholders del sistema
# viejo; redactar contenido real cuando el usuario lo defina.
PROCEDIMIENTOS: dict[str, list[str]] = {
    "TABLEROS": [
        "Realizar una inspección visual detallada del tablero eléctrico y tomar fotografías para documentar su estado inicial, verificando el cumplimiento de las normas de accesibilidad y etiquetado. (Artículo 230 del CNE)",
        "Proceder con la apertura del tablero eléctrico asegurándose de cumplir con las medidas de seguridad, desconexión de energía y uso de equipo de protección personal (EPP) adecuado. (Artículo 240 del CNE)",
        "Realizar mediciones de temperatura con una cámara termográfica para detectar puntos calientes y asegurar que las temperaturas estén dentro de los límites aceptables. (Artículo 280 del CNE)",
        "Efectuar la limpieza del polvo y residuos acumulados utilizando brochas y aire comprimido, sin dañar los componentes internos del tablero. (Artículo 260 del CNE)",
        "Aplicar solventes dieléctricos aprobados para limpiar los componentes, asegurando que no haya humedad o residuos que puedan interferir con su funcionamiento. (Artículo 270 del CNE)",
        "Verificar y ajustar las conexiones de interruptores termomagnéticos y diferenciales para asegurar la fijación adecuada, siguiendo los valores de torque recomendados. (Artículo 290 del CNE)",
        "Medir el voltaje de las fases del tablero para asegurar que se encuentren dentro de los límites operativos recomendados, verificando el equilibrio y la estabilidad del sistema eléctrico. (Artículo 320 del CNE)",
        "Sustituir y actualizar la señalética del tablero para cumplir con las especificaciones de visibilidad y seguridad establecidas, asegurando que toda la información sea fácilmente identificable. (Artículo 310 del CNE)",
        "CONSIDERACIONES ADICIONALES",
    ],
    "POZOS": [
        "Identificar, etiquetar claramente, y documentar visualmente el pozo a tierra para asegurar que se pueda localizar fácilmente durante el mantenimiento. (Artículo 320 del CNE)",
        "Realizar una inspección visual inicial para evaluar la condición del pozo a tierra antes del mantenimiento, verificando su integridad física y las condiciones ambientales. (Artículo 330 del CNE)",
        "Retirar el conector AB del pozo a tierra siguiendo procedimientos de seguridad eléctrica para evitar daños o accidentes. (Artículo 340 del CNE)",
        "Realizar la medición inicial de la resistencia del pozo a tierra usando un telurómetro calibrado para establecer una línea base. (Artículo 350 del CNE)",
        "Aplicar la primera solución química Thorgel para mejorar la conductividad del suelo y reducir la resistencia del pozo a tierra. (Artículo 360 del CNE)",
        "Aplicar la segunda dosis de solución química Thorgel para optimizar la conductividad del suelo. (Artículo 360 del CNE)",
        "Realizar la medición final de la resistencia del pozo a tierra para verificar la efectividad de las mejoras aplicadas. (Artículo 370 del CNE)",
        "Instalar un nuevo conector AB, asegurando que las conexiones sean seguras y cumplan con las especificaciones de continuidad eléctrica. (Artículo 380 del CNE)",
        "Pintar la tapa de concreto del pozo a tierra para protección adicional y señalización adecuada. (Artículo 390 del CNE)",
        "Realizar una inspección final y documentar el estado del pozo después del mantenimiento, asegurando que todas las acciones correctivas se han realizado. (Artículo 400 del CNE)",
        "CONSIDERACIONES ADICIONALES",
    ],
    "TRANS. AISLAMIENTO": [
        "Realizar una inspección visual inicial del transformador para verificar su estado antes del mantenimiento, seguido del retiro seguro de las tapas de acceso. Esto incluye la evaluación de cualquier daño físico, signos de fugas de aceite, o corrosión. (Artículo 420 del CNE)",
        "Documentar el estado del transformador antes de cualquier intervención para tener un registro base del estado operativo y físico del equipo. (Artículo 425 del CNE)",
        "Identificar y diagnosticar problemas en componentes críticos del transformador, como pueden ser ventiladores, radiadores, o conexiones eléctricas que podrían afectar el rendimiento general del equipo. Esto incluye la verificación de conexiones eléctricas, pruebas de funcionamiento, y diagnóstico de fallas. (Artículo 430 del CNE)",
        "Proceder con la limpieza completa del transformador, removiendo polvo y residuos que puedan afectar su rendimiento. Esto incluye el uso de herramientas apropiadas para evitar daños en los componentes sensibles. (Artículo 440 del CNE)",
        "Reparar o reemplazar cualquier componente crítico del transformador que presente fallas o bajo rendimiento. Este paso incluye la verificación de compatibilidad de piezas y pruebas de funcionamiento post-intervención. (Artículo 450 del CNE)",
        "Realizar una inspección final del transformador para asegurar que todas las intervenciones fueron realizadas adecuadamente y que el equipo está en condiciones óptimas de operación. Este paso también incluye la reinstalación segura de las tapas. (Artículo 460 del CNE)",
        "CONSIDERACIONES ADICIONALES",
    ],
    "PARARRAYOS": [
        "Realizar una limpieza preliminar para remover suciedad y contaminantes superficiales del pararrayo. (RNE ITC-BT-24, Artículo 24.4.2)",
        "Emplear una brocha para eliminar el polvo acumulado en las superficies del pararrayo. (RNE ITC-BT-24, Artículo 24.4.3)",
        "Aplicar solvente dieléctrico para asegurar que no queden residuos que puedan afectar el funcionamiento eléctrico. (RNE ITC-BT-24, Artículo 24.4.3)",
        "Verificar y ajustar los conectores para garantizar que estén correctamente fijados y evitar conexiones defectuosas. (RNE ITC-BT-24, Artículo 24.4.4)",
        "Revisar el estado físico del pararrayo después de la limpieza para asegurar que esté en condiciones óptimas. (RNE ITC-BT-24, Artículo 24.4.5)",
        "Realizar una segunda limpieza con solvente para mantener las propiedades dieléctricas del pararrayo. (RNE ITC-BT-24, Artículo 24.4.3)",
        "Completar la limpieza con una aplicación final de solvente dieléctrico para asegurar el funcionamiento óptimo del pararrayo. (RNE ITC-BT-24, Artículo 24.4.3)",
        "CONSIDERACIONES ADICIONALES",
    ],
    "UPS": [
        "Confirmar la identificación correcta del equipo y sus especificaciones antes de comenzar el mantenimiento. (CNE NTP 205.025, Sección 5.1)",
        "Procedimiento seguro para retirar la carcasa y permitir el acceso interno al equipo. (CNE NTP 205.025, Sección 5.2)",
        "Inspección del Estado Interno del UPS - Evaluación del estado físico y funcional de los componentes internos. (CNE NTP 205.025, Sección 5.3)",
        "Verificación del Estado de las Baterías - Comprobar la integridad y capacidad de las baterías. (CNE NTP 205.025, Sección 5.4)",
        "Limpieza Interna del UPS Usando Soplador Inalámbrico - Eliminar polvo y suciedad con métodos seguros. (CNE NTP 205.025, Sección 5.5)",
        "Limpieza Externa del UPS con Trapo Industrial y Crema Limpiadora - Mantener la carcasa externa libre de contaminantes. (CNE NTP 205.025, Sección 5.6)",
        "Medición de Voltaje con Pinza Amperimétrica - Verificar parámetros eléctricos del UPS para asegurar su correcto funcionamiento. (CNE NTP 205.025, Sección 5.7)",
        "Termino del Mantenimiento del UPS - Asegurar que todos los componentes están operativos y seguros para el uso. (CNE NTP 205.025, Sección 5.8)",
        "CONSIDERACIONES ADICIONALES",
    ],
    "TOMACORRIENTES": [f"Procedimiento {i}" for i in range(1, 10)],
    "LUMINARIAS": [f"Procedimiento {i}" for i in range(1, 10)],
}


def main() -> None:
    url = os.environ.get("DATABASE_PUBLIC_URL") or os.environ.get("DATABASE_URL")
    if not url:
        sys.exit("Falta DATABASE_PUBLIC_URL en el entorno.")
    eng = create_engine(url)
    with eng.begin() as c:
        row = c.execute(
            text("SELECT id, razon_social FROM empresa WHERE upper(razon_social) LIKE :p"),
            {"p": EMPRESA_LIKE},
        ).fetchone()
        if not row:
            sys.exit(f"Empresa no encontrada con patrón {EMPRESA_LIKE}")
        empresa_id, razon = str(row[0]), row[1]
        print(f"Empresa destino: {razon} ({empresa_id})")

        creados = actualizados = intactos = 0
        for nombre, pasos in PROCEDIMIENTOS.items():
            plantilla = [
                {"orden": i, "nombre": p, "descripcion": ""}
                for i, p in enumerate(pasos, start=1)
            ]
            existente = c.execute(
                text("SELECT id, procedimientos_template FROM tipo_equipo "
                     "WHERE empresa_id = :e AND upper(nombre) = :n"),
                {"e": empresa_id, "n": nombre.upper()},
            ).fetchone()
            if existente is None:
                c.execute(
                    text("INSERT INTO tipo_equipo "
                         "(id, empresa_id, nombre, descripcion, procedimientos_template) "
                         "VALUES (:i, :e, :n, :d, :t)"),
                    {
                        "i": str(uuid.uuid4()),
                        "e": empresa_id,
                        "n": nombre,
                        "d": f"Mantenimiento preventivo de {nombre.title()}",
                        "t": json.dumps(plantilla, ensure_ascii=False),
                    },
                )
                creados += 1
                print(f"  + {nombre}: creado con {len(plantilla)} pasos")
            elif not existente[1]:
                c.execute(
                    text("UPDATE tipo_equipo SET procedimientos_template = :t WHERE id = :i"),
                    {"t": json.dumps(plantilla, ensure_ascii=False), "i": str(existente[0])},
                )
                actualizados += 1
                print(f"  ~ {nombre}: plantilla completada ({len(plantilla)} pasos)")
            else:
                intactos += 1
                print(f"  = {nombre}: ya tiene plantilla, no se toca")

        print(f"\nListo: {creados} creados, {actualizados} actualizados, {intactos} intactos.")


if __name__ == "__main__":
    main()
