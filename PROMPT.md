# E-Zyro — Contexto de trabajo (no explores carpetas completas; esto te lo doy)

## Repos
- Backend (FastAPI):  C:\dev\code\E-zyro-Backend\BACKEND
- App (Flutter):      C:\dev\code\E-zyro-app\e_zyro_app
- Frontend Angular:   NO TOCAR (solo Backend y Flutter)
- Lab Finanzas:       NO CONECTADO

## Producción / Railway (úsalo para verificar datos sin desplegar)
- Proyecto: comfortable-education · entorno: production · cuenta: crewvsdev@gmail.com
- Servicios: E-zyro (backend, https://e-zyro-production-7f7d.up.railway.app), Postgres-SjrN (BD), scintillating-celebration
- Enlazar si hace falta: railway link -p comfortable-education -e production ; railway service E-zyro
- Consultar la BD de prod: escribe un script .py y córrelo con
  railway run -s Postgres-SjrN python script.py
  En el script usa DATABASE_PUBLIC_URL (NO DATABASE_URL: host interno no resuelve local).
  Local tiene psycopg2 + sqlalchemy. Borra el script al terminar; nunca imprimas credenciales.

## Stack / BD (para no redescubrir)
- Postgres con UUID nativos → normaliza a str() al salir de la BD.
- RBAC: permiso(modulo,accion) + rol + usuario_rol + rol_permiso. Permisos se siembran en
  main.py::_run_migrations (sembrar_permisos, ON CONFLICT DO NOTHING) y la matriz rol→permiso
  en app/db/rbac_seed.py. Admin/SuperAdmin = todo.
- Tablas: Base.metadata.create_all crea modelos faltantes pero NO altera tablas existentes.
  Los .sql de migrations/ son MANUALES (corre el ALTER con railway run si cambia una tabla viva).

## Reglas de trabajo
- Ubica con Grep/Glob; lee solo el tramo necesario (offset/limit). No leas archivos completos "por si acaso".
- No corras builds ni flutter analyze salvo que lo pida o sea imprescindible (si tocas mucho Dart,
  un analyze acotado a los archivos editados sí es válido). Compila el backend con py_compile tras editar.
- No hagas commit/push ni deploy sin que lo confirme. Antes de cambiar reglas de negocio, pregúntame.
- Tu MEMORY.md ya tiene el estado del proyecto y los accesos (ezyro-railway-prod): úsalo antes de re-investigar.

## Rutina de inicio (hazla siempre antes de codear)
1. Revisa MEMORY.md y dame un resumen corto de lo PENDIENTE (QA, redeploys, fases sin cerrar).
2. Propón un plan del día: 3–6 actividades concretas priorizadas (qué, por qué, archivos probables)
   + 1–2 mejoras/deudas técnicas que detectes. Formato lista, sin código aún.
3. Espera mi confirmación o ajustes antes de empezar. Luego ejecuta una a una.

## Tarea de hoy
>>> (la pego aquí) <<<

============================================================================================================================================

# E-Zyro — Contexto de trabajo (no explores carpetas completas; esto te lo doy)

## Repos
- Backend (FastAPI):  D:\e-zyro-backend
- App (Flutter):      D:\e-zyro-app
- Frontend Angular:   D:\e-zyro-frontend> 
- Lab Finanzas:       NO CONECTADO

## Producción / Railway (úsalo para verificar datos sin desplegar)
- Proyecto: comfortable-education · entorno: production · cuenta: crewvsdev@gmail.com
- Servicios: E-zyro (backend, https://e-zyro-production-7f7d.up.railway.app), Postgres-SjrN (BD), scintillating-celebration
- Enlazar si hace falta: railway link -p comfortable-education -e production ; railway service E-zyro
- Consultar la BD de prod: escribe un script .py y córrelo con
  railway run -s Postgres-SjrN python script.py
  En el script usa DATABASE_PUBLIC_URL (NO DATABASE_URL: host interno no resuelve local).
  Local tiene psycopg2 + sqlalchemy. Borra el script al terminar; nunca imprimas credenciales.

## Stack / BD (para no redescubrir)
- Postgres con UUID nativos → normaliza a str() al salir de la BD.
- RBAC: permiso(modulo,accion) + rol + usuario_rol + rol_permiso. Permisos se siembran en
  main.py::_run_migrations (sembrar_permisos, ON CONFLICT DO NOTHING) y la matriz rol→permiso
  en app/db/rbac_seed.py. Admin/SuperAdmin = todo.
- Tablas: Base.metadata.create_all crea modelos faltantes pero NO altera tablas existentes.
  Los .sql de migrations/ son MANUALES (corre el ALTER con railway run si cambia una tabla viva).

## Reglas de trabajo
- Ubica con Grep/Glob; lee solo el tramo necesario (offset/limit). No leas archivos completos "por si acaso".
- No corras builds ni flutter analyze salvo que lo pida o sea imprescindible (si tocas mucho Dart,
  un analyze acotado a los archivos editados sí es válido). Compila el backend con py_compile tras editar.
- No hagas commit/push ni deploy sin que lo confirme. Antes de cambiar reglas de negocio, pregúntame.
- Tu MEMORY.md ya tiene el estado del proyecto y los accesos (ezyro-railway-prod): úsalo antes de re-investigar.

## Rutina de inicio (hazla siempre antes de codear)
1. Revisa MEMORY.md y dame un resumen corto de lo PENDIENTE (QA, redeploys, fases sin cerrar).
2. Propón un plan del día: 3–6 actividades concretas priorizadas (qué, por qué, archivos probables)
   + 1–2 mejoras/deudas técnicas que detectes. Formato lista, sin código aún.
3. Espera mi confirmación o ajustes antes de empezar. Luego ejecuta una a una.

## Tarea de hoy
>>> (la pego aquí) <<<
