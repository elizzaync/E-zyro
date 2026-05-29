-- Semilla idempotente de rol_permiso según la matriz RBAC aprobada (2026-05-29).
-- Espejo de app/db/rbac_seed.py::sembrar_rol_permiso (que corre en el lifespan).
-- Seguro de re-ejecutar: solo inserta vínculos que falten.

-- ── Administrador / SuperAdmin: TODO el catálogo de permisos ──────────────────
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
  FROM rol r CROSS JOIN permiso p
 WHERE r.nombre IN ('Administrador', 'SuperAdmin', 'Super Admin')
   AND NOT EXISTS (
       SELECT 1 FROM rol_permiso rp WHERE rp.rol_id = r.id AND rp.permiso_id = p.id
   );

-- ── Roles operativos: matriz (rol, modulo, accion) ────────────────────────────
WITH matriz(rol, modulo, accion) AS (VALUES
  -- Jefe de Operaciones
  ('Jefe de Operaciones','dashboard','ver'),
  ('Jefe de Operaciones','reportes','ver'),
  ('Jefe de Operaciones','proyectos','ver'),
  ('Jefe de Operaciones','proyectos','crear'),
  ('Jefe de Operaciones','proyectos','editar'),
  ('Jefe de Operaciones','asistencia','ver'),
  ('Jefe de Operaciones','asistencia','validar'),
  ('Jefe de Operaciones','requerimientos','ver'),
  ('Jefe de Operaciones','requerimientos','aprobar'),
  ('Jefe de Operaciones','correctivo','ver'),
  ('Jefe de Operaciones','correctivo','crear'),
  ('Jefe de Operaciones','correctivo','editar'),
  ('Jefe de Operaciones','correctivo','aprobar'),
  ('Jefe de Operaciones','correctivo','finalizar'),
  ('Jefe de Operaciones','observacion','ver'),
  ('Jefe de Operaciones','observacion','crear'),
  ('Jefe de Operaciones','observacion','editar'),
  ('Jefe de Operaciones','observacion','eliminar'),
  ('Jefe de Operaciones','itse','ver'),
  ('Jefe de Operaciones','itse','crear'),
  ('Jefe de Operaciones','itse','editar'),
  ('Jefe de Operaciones','itse','finalizar'),
  ('Jefe de Operaciones','informe_servicio','ver'),
  ('Jefe de Operaciones','informe_servicio','generar'),
  ('Jefe de Operaciones','equipo','ver_estado'),
  ('Jefe de Operaciones','equipo','marcar_inoperativo'),
  ('Jefe de Operaciones','equipo','reactivar'),
  ('Jefe de Operaciones','calibracion','ver'),
  ('Jefe de Operaciones','calibracion','crear'),
  ('Jefe de Operaciones','calibracion','editar'),
  ('Jefe de Operaciones','epp','ver'),
  ('Jefe de Operaciones','inventario','ver'),
  ('Jefe de Operaciones','empleados','ver'),
  ('Jefe de Operaciones','galeria','ver'),
  ('Jefe de Operaciones','galeria','subir'),
  -- Logístico
  ('Logístico','dashboard','ver'),
  ('Logístico','inventario','ver'),
  ('Logístico','inventario','gestionar'),
  ('Logístico','requerimientos','ver'),
  ('Logístico','requerimientos','aprobar'),
  ('Logístico','epp','ver'),
  ('Logístico','epp','crear'),
  ('Logístico','epp','editar'),
  ('Logístico','epp','entregar'),
  ('Logístico','epp','ingresar'),
  ('Logístico','epp','eliminar'),
  ('Logístico','catalogos','ver'),
  ('Logístico','catalogos','crear'),
  ('Logístico','catalogos','editar'),
  ('Logístico','catalogos','eliminar'),
  ('Logístico','calibracion','ver'),
  ('Logístico','calibracion','crear'),
  ('Logístico','calibracion','editar'),
  ('Logístico','equipo','ver_estado'),
  ('Logístico','proyectos','ver'),
  ('Logístico','galeria','ver'),
  ('Logístico','galeria','subir'),
  -- Supervisor
  ('Supervisor','dashboard','ver'),
  ('Supervisor','proyectos','ver'),
  ('Supervisor','proyectos','editar'),
  ('Supervisor','asistencia','ver'),
  ('Supervisor','asistencia','validar'),
  ('Supervisor','itse','ver'),
  ('Supervisor','itse','crear'),
  ('Supervisor','itse','editar'),
  ('Supervisor','itse','finalizar'),
  ('Supervisor','observacion','ver'),
  ('Supervisor','observacion','crear'),
  ('Supervisor','observacion','editar'),
  ('Supervisor','correctivo','ver'),
  ('Supervisor','correctivo','crear'),
  ('Supervisor','correctivo','editar'),
  ('Supervisor','equipo','ver_estado'),
  ('Supervisor','equipo','marcar_inoperativo'),
  ('Supervisor','informe_servicio','ver'),
  ('Supervisor','informe_servicio','generar'),
  ('Supervisor','requerimientos','ver'),
  ('Supervisor','epp','ver'),
  ('Supervisor','calibracion','ver'),
  ('Supervisor','galeria','ver'),
  ('Supervisor','galeria','subir'),
  -- Técnico de Campo
  ('Técnico de Campo','asistencia','registrar'),
  ('Técnico de Campo','asistencia','ver'),
  ('Técnico de Campo','proyectos','ver'),
  ('Técnico de Campo','itse','ver'),
  ('Técnico de Campo','itse','crear'),
  ('Técnico de Campo','itse','editar'),
  ('Técnico de Campo','observacion','ver'),
  ('Técnico de Campo','observacion','crear'),
  ('Técnico de Campo','correctivo','ver'),
  ('Técnico de Campo','correctivo','crear'),
  ('Técnico de Campo','equipo','ver_estado'),
  ('Técnico de Campo','requerimientos','ver'),
  ('Técnico de Campo','epp','ver'),
  ('Técnico de Campo','calibracion','ver'),
  ('Técnico de Campo','informe_servicio','ver'),
  ('Técnico de Campo','galeria','ver'),
  ('Técnico de Campo','galeria','subir')
)
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
  FROM matriz m
  JOIN rol r     ON r.nombre = m.rol
  JOIN permiso p ON p.modulo = m.modulo AND p.accion = m.accion
 WHERE NOT EXISTS (
     SELECT 1 FROM rol_permiso rp WHERE rp.rol_id = r.id AND rp.permiso_id = p.id
 );
