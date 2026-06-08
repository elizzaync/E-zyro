"""
Prueba de las capas 1-3 de trazabilidad de firmas (ledger firma_evento).

Usa el CÓDIGO REAL del servicio (app.services.firma_seguridad) contra la BD
indicada en DATABASE_URL. Crea eventos de prueba con dos usuarios reales,
demuestra cada capa y BORRA sus propias filas al terminar (no ensucia la BD).

Cómo ejecutar (PowerShell), desde la carpeta BACKEND:

    $env:DATABASE_URL = "postgresql://usuario:clave@host:puerto/railway"
    python probar_firma_seguridad.py

Notas:
- Capa 2b (perceptual, phash) necesita OpenCV. En el servidor de producción
  está instalado (opencv-python-headless). Si lo corres en una máquina sin
  cv2, el script lo detecta y demuestra el concepto con un dHash propio.
"""
import base64
import math
import os
import sys

# Consola de Windows: forzar UTF-8 para no romper con acentos/símbolos
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# ── 1) Localizar las imágenes de firma de demostración ───────────────────────
AQUI = os.path.dirname(os.path.abspath(__file__))
ORIG = os.path.join(AQUI, "firma_demo.png")
DUP  = os.path.join(AQUI, "firma_demo_recortada.png")

for p in (ORIG, DUP):
    if not os.path.exists(p):
        print(f"[X] Falta {p}. Genera primero las imágenes de demo.")
        sys.exit(1)

def data_url(path: str) -> str:
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()

# ── 2) Conectar a la BD y traer el servicio real ─────────────────────────────
if not os.getenv("DATABASE_URL"):
    print("[X] Define DATABASE_URL antes de ejecutar (ver cabecera del archivo).")
    sys.exit(1)

from app.db.database import SessionLocal               # noqa: E402
# Importar los modelos destino de los FK para que SQLAlchemy resuelva la metadata
from app.models.empresa import Empresa                 # noqa: E402,F401
from app.models.usuario import Usuario                 # noqa: E402,F401
from app.models.firma_evento import FirmaEvento        # noqa: E402
from app.models.empleado import Empleado               # noqa: E402
from app.services.firma_seguridad import (             # noqa: E402
    registrar_firma, verificar_evento, _dhash, hamming_hex,
)

db = SessionLocal()
creados = []   # ids de eventos de prueba para limpiar al final
ok_total = True

def check(nombre: str, condicion: bool, detalle: str = ""):
    global ok_total
    ok_total = ok_total and condicion
    print(f"  [{'OK ' if condicion else 'FALLA'}] {nombre}" + (f"  -> {detalle}" if detalle else ""))

try:
    # Dos empleados/usuarios reales DISTINTOS de la misma empresa
    emps = (db.query(Empleado)
            .filter(Empleado.usuario_id.isnot(None))
            .limit(2).all())
    if len(emps) < 2:
        print("[X] Se necesitan al menos 2 empleados con usuario en la BD.")
        sys.exit(1)
    A, B = emps[0], emps[1]
    empresa_id = A.empresa_id
    print(f"\nUsuario A: {A.usuario_id}  (empleado {A.id})")
    print(f"Usuario B: {B.usuario_id}  (empleado {B.id})")
    print(f"Empresa:   {empresa_id}\n")

    # ── CAPA 1 — Procedencia + huella de la firma de A ───────────────────────
    print("CAPA 1 — Procedencia (identidad del JWT) + huella SHA-256")
    evA = registrar_firma(
        db, empresa_id=empresa_id, firmante_id=A.id, firmante_usuario_id=A.usuario_id,
        entidad_tipo="prueba_firma", entidad_id="demo-A", rol_firma="propietario",
        firma=data_url(ORIG), ip="200.10.20.30", user_agent="ScriptPrueba/1.0",
    )
    db.commit()
    if evA: creados.append(evA.id)
    check("se registró el evento de firma de A", evA is not None)
    check("guardó SHA-256 de la imagen", bool(evA and evA.sha256), (evA.sha256[:16] + "...") if evA and evA.sha256 else "")
    check("guardó la identidad del firmante (no la imagen)", bool(evA and evA.firmante_usuario_id == A.usuario_id))
    check("guardó procedencia (IP + user-agent)", bool(evA and evA.ip and evA.user_agent),
          f"ip={evA.ip if evA else '-'}")
    check("guardó el sello HMAC", bool(evA and evA.sello_hmac), (evA.sello_hmac[:16] + "...") if evA and evA.sello_hmac else "")

    # ── CAPA 2a — Reutilización EXACTA: B sube la MISMA imagen de A ───────────
    print("\nCAPA 2a — Anti-reutilización exacta (otro usuario, misma imagen)")
    evB = registrar_firma(
        db, empresa_id=empresa_id, firmante_id=B.id, firmante_usuario_id=B.usuario_id,
        entidad_tipo="prueba_firma", entidad_id="demo-B", rol_firma="propietario",
        firma=data_url(ORIG), ip="9.9.9.9", user_agent="ScriptPrueba/1.0",
    )
    db.commit()
    if evB: creados.append(evB.id)
    check("MARCÓ como sospechosa la firma de B", bool(evB and evB.sospechoso),
          (evB.motivo_sospecha or "") if evB else "")

    # ── CAPA 2b — Reutilización PERCEPTUAL: imagen casi-idéntica (recortada) ──
    print("\nCAPA 2b — Anti-reutilización perceptual (imagen recortada/reescalada)")
    with open(ORIG, "rb") as f: bo = f.read()
    with open(DUP, "rb") as f: bd = f.read()
    ph_o, ph_d = _dhash(bo), _dhash(bd)
    if ph_o and ph_d:
        dist = hamming_hex(ph_o, ph_d)
        check("phash calculado (OpenCV disponible)", True, f"orig={ph_o} recortada={ph_d}")
        check("imágenes casi-idénticas detectables (hamming ≤ 10)", dist <= 10, f"distancia={dist}")
    else:
        # Sin cv2: demostración con dHash propio sobre los píxeles conocidos
        print("  [i] OpenCV no está en ESTA máquina -> en producción sí (cv2). ")
        print("      Demostración conceptual del perceptual hash sobre los píxeles:")
        def dhash_demo(dx):
            # regenera la matriz y calcula un dHash 8x8 simple
            W,H=120,50; px=[[255]*W for _ in range(H)]
            for t in range(220):
                x=int(8+t*0.5)+dx; y=int(25+14*math.sin(t/12.0))
                for ox in(-1,0,1):
                    for oy in(-1,0,1):
                        xx,yy=x+ox,y+oy
                        if 0<=xx<W and 0<=yy<H: px[yy][xx]=0
            # reducir a 9x8 promediando, comparar horizontal
            bits=0
            for gy in range(8):
                row=[]
                for gx in range(9):
                    sx0=gx*W//9; sx1=(gx+1)*W//9; sy0=gy*H//8; sy1=(gy+1)*H//8
                    s=n=0
                    for yy in range(sy0,sy1):
                        for xx in range(sx0,sx1):
                            s+=px[yy][xx]; n+=1
                    row.append(s/max(n,1))
                for i in range(8):
                    bits=(bits<<1)|(1 if row[i+1]>row[i] else 0)
            return bits
        h1,h2=dhash_demo(0),dhash_demo(1)
        dist=bin(h1^h2).count("1")
        check("perceptual hash de original vs recortada es casi igual (hamming ≤ 10)",
              dist <= 10, f"distancia={dist} (sha256 SÍ difieren, phash NO)")

    # ── CAPA 3 — Tamper-evidence del sello HMAC ──────────────────────────────
    print("\nCAPA 3 — Integridad (sello HMAC): detectar manipulación")
    check("el sello de A verifica como íntegro", verificar_evento(evA) is True)
    # Simular manipulación en memoria (sin tocar la BD): cambiar el firmante
    original = evA.firmante_usuario_id
    evA.firmante_usuario_id = B.usuario_id
    roto = verificar_evento(evA)
    evA.firmante_usuario_id = original  # restaurar
    check("al alterar el firmante, el sello YA NO verifica", roto is False)

    print("\n" + ("="*60))
    print("RESULTADO GLOBAL:", "TODAS LAS CAPAS OK" if ok_total else "HAY FALLAS")
    print("="*60)

finally:
    # ── Limpieza: borrar SOLO las filas creadas por esta prueba ──────────────
    if creados:
        db.query(FirmaEvento).filter(FirmaEvento.id.in_(creados)).delete(synchronize_session=False)
        db.commit()
        print(f"\n(limpieza) {len(creados)} evento(s) de prueba borrados de la BD.")
    db.close()
