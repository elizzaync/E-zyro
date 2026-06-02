"""
Prueba local del chatbot E-Zybot (REPL por consola).

Chatea contra la BD real sin necesidad de levantar el servidor ni la app.

Requisitos (en el .env del backend, o como variables de entorno):
  - DATABASE_URL        → la BD PostgreSQL (la misma de Railway)
  - ANTHROPIC_API_KEY   → tu API key de console.anthropic.com

Uso:
  cd C:\\dev\\code\\E-zyro-Backend\\BACKEND
  pip install anthropic          # solo la primera vez
  python probar_chatbot.py

Comandos dentro del chat:  'salir' para terminar · 'reset' para reiniciar la conversación.
"""
import os
import sys

from dotenv import load_dotenv

load_dotenv()

# --- Validación temprana: database.py exige DATABASE_URL al importarse ---
if not os.getenv("DATABASE_URL"):
    print("❌ Falta DATABASE_URL. Añádela al .env del backend, por ejemplo:")
    print('   DATABASE_URL=postgresql://postgres:...@kodama.proxy.rlwy.net:50179/railway')
    sys.exit(1)

_PROVIDER = os.getenv("CHATBOT_PROVIDER", "local").lower().strip()

if _PROVIDER == "claude":
    if not os.getenv("ANTHROPIC_API_KEY"):
        print("❌ CHATBOT_PROVIDER=claude pero falta ANTHROPIC_API_KEY.")
        sys.exit(1)
    try:
        import anthropic  # noqa: F401
    except ImportError:
        print("❌ Falta 'anthropic'. Instálalo con:  pip install anthropic")
        sys.exit(1)
else:
    try:
        import openai  # noqa: F401
    except ImportError:
        print("❌ Falta 'openai'. Instálalo con:  pip install openai")
        sys.exit(1)

from sqlalchemy import text  # noqa: E402

from app.db.database import SessionLocal  # noqa: E402
from app.services.chatbot import responder  # noqa: E402
from app.services.chatbot import config as _cfg  # noqa: E402


def construir_payload(db) -> dict:
    """Simula el JWT de un Administrador de la primera empresa de la BD."""
    emp_id = os.getenv("CHATBOT_TEST_EMPRESA_ID")
    nombre = "la empresa"
    if emp_id:
        row = db.execute(
            text("SELECT razon_social FROM empresa WHERE id=:id"), {"id": emp_id}
        ).first()
        nombre = row[0] if row else nombre
    else:
        row = db.execute(text("SELECT id, razon_social FROM empresa ORDER BY created_at LIMIT 1")).first()
        if not row:
            print("❌ No hay ninguna empresa en la BD.")
            sys.exit(1)
        emp_id, nombre = str(row[0]), row[1]
    return {
        "id": "00000000-0000-0000-0000-000000000000",
        "empresa_id": emp_id,
        "rol": "Administrador",
        "sub": "tester",
    }, nombre


def main():
    db = SessionLocal()
    try:
        payload, empresa = construir_payload(db)
        if _cfg.CHATBOT_PROVIDER == "claude":
            motor = f"Claude · {_cfg.CHATBOT_MODEL} (effort: {_cfg.CHATBOT_EFFORT})"
        else:
            motor = f"Local · {_cfg.OLLAMA_MODEL} @ {_cfg.OLLAMA_BASE_URL}"
        print("=" * 64)
        print(f"  E-Zybot — prueba local")
        print(f"  Empresa: {empresa}")
        print(f"  Motor:   {motor}")
        print("=" * 64)
        print("Escribe tu pregunta. 'salir' para terminar · 'reset' para reiniciar.\n")
        print("Ejemplos:")
        print("  • ¿Cuántos materiales y herramientas tenemos?")
        print("  • Busca martillos en el inventario")
        print("  • ¿Qué EPP está con stock bajo?")
        print("  • Lista los equipos intervenidos del cliente Talma")
        print("  • Dame un resumen general de la empresa\n")

        historial: list[dict] = []
        while True:
            try:
                pregunta = input("Tú > ").strip()
            except (EOFError, KeyboardInterrupt):
                print("\n¡Hasta luego!")
                break
            if not pregunta:
                continue
            if pregunta.lower() in ("salir", "exit", "quit"):
                print("¡Hasta luego!")
                break
            if pregunta.lower() == "reset":
                historial = []
                print("(conversación reiniciada)\n")
                continue

            historial.append({"role": "user", "content": pregunta})
            print("E-Zybot > pensando...", end="\r")
            resultado = responder(db, payload, historial)
            print(" " * 30, end="\r")  # limpia "pensando..."

            respuesta = resultado["respuesta"]
            print(f"E-Zybot > {respuesta}")
            if resultado.get("herramientas_usadas"):
                nombres = ", ".join(h["nombre"] for h in resultado["herramientas_usadas"])
                print(f"          \033[90m(herramientas: {nombres})\033[0m")
            print()
            historial.append({"role": "assistant", "content": respuesta})
    finally:
        db.close()


if __name__ == "__main__":
    main()
