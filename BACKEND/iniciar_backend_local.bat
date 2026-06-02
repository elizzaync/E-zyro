@echo off
REM ── Arranca el backend en el PC para pruebas locales ──────────────────────
REM Datos: BD de Railway (DATABASE_URL del .env)  ·  IA: Ollama local
REM Escucha en toda la red (0.0.0.0:8000) para que el celular/emulador llegue.
REM PYTHONUTF8=1 evita el crash por emojis en la consola de Windows.
cd /d "%~dp0"
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
"C:\dev\code\.venv\Scripts\python.exe" -c "from dotenv import load_dotenv; load_dotenv(); import uvicorn; uvicorn.run('app.main:app', host='0.0.0.0', port=8000)"
pause
