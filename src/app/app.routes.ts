import { Routes } from '@angular/router';
import { LoginComponent } from './features/auth/login/login.component';
import { ResetPasswordComponent } from './features/auth/reset-password/reset-password.component';
import { HomeComponent } from './features/home/home.component';
import { authGuard } from './core/guards/auth.guards';
import { PersonalComponent } from './features/personal/personal.component';
import { PermisosComponent } from './features/permisos/permisos.component';
import { MasComponent } from './features/masComponentes/mas.component';
import { ConfiguracionComponent } from './features/configuracion/configuracion.component';
import { CentroAyudaComponent } from './features/centro-ayuda/centro-ayuda.component';
import { DocumentacionComponent } from './features/documentacion/documentacion.component';
import { OperacionesComponent } from './features/operaciones/operaciones.component';
import { LogisticaComponent } from './features/logistica/logistica.component';
import { RequerimientosComponent } from './features/logistica/components/requerimientos/requerimientos.component';
import { ComprasComponent } from './features/logistica/components/compras/compras.component';
import { SalidasComponent } from './features/logistica/components/salidas/salidas.component';
import { LogisticaServiciosComponent } from './features/logistica/components/servicios/logistica-servicios.component';
import { MantenimientoEquiposComponent } from './features/operaciones/components/mantenimiento-equipos/mantenimiento-equipos.component';
import { MapaParqueComponent } from './features/operaciones/components/mantenimiento-equipos/mapa-parque/mapa-parque.component';
import { DetalleEquipoComponent } from './features/operaciones/components/mantenimiento-equipos/detalle-equipo/detalle-equipo.component';
import { OperacionesDetalleComponent } from './features/operaciones/components/operaciones-detalle/operaciones-detalle.component';
import { OperacionesServiciosListaComponent } from './features/operaciones/components/operaciones-servicios-lista/operaciones-servicios-lista.component';
import { OperacionesCronogramaComponent } from './features/operaciones/components/operaciones-cronograma/operaciones-cronograma.component';
import { EquiposIntervenidosComponent } from './features/operaciones/components/equipos-intervenidos/equipos-intervenidos.component';
import { IntervencionEquipoComponent } from './features/operaciones/components/intervencion-equipo/intervencion-equipo.component';
import { CertificadoComponent } from './features/operaciones/components/certificado/certificado.component';
import { clientPortalGuard } from './core/guards/client-portal.guard';
import { bloquearRolesGuard, rolesGuard } from './core/guards/roles.guard';
import { LegajoListaComponent } from './features/rrhh/legajo/legajo-lista.component';
import { LegajoDetalleComponent } from './features/rrhh/legajo/components/legajo-detalle/legajo-detalle.component';
import { SolicitudesListaComponent } from './features/rrhh/solicitudes/solicitudes-lista.component';
import { PlanillasComponent } from './features/rrhh/planillas/planillas.component';
import { AsistenciaDashboardComponent } from './features/rrhh/asistencia/asistencia-dashboard.component';
import { AsistenciaComponent } from './features/asistencia/asistencia.component';
import { DocumentosSstComponent } from './features/rrhh/documentos-sst/documentos-sst.component';
import { CalibracionesComponent } from './features/operaciones/components/calibraciones/calibraciones.component';
import { CalendarioComponent } from './features/home/pages/calendario/calendario.component';
import { TicketsSoporteComponent } from './features/soporte/components/tickets/tickets.component';
import { MonitoreoComponent } from './features/soporte/components/monitoreo/monitoreo.component';
import { SeguridadComponent } from './features/soporte/components/seguridad/seguridad.component';
import { CrearCuentasComponent } from './features/soporte/components/crear-cuentas/crear-cuentas.component';
import { GestionPermisosComponent } from './features/soporte/components/gestion-permisos/gestion-permisos.component';
import { BackupsComponent } from './features/soporte/components/backups/backups.component';
import { SeguridadMonitoreoComponent } from './features/soporte/components/seguridad-monitoreo/seguridad-monitoreo.component';
import { AuditoriaEventosComponent } from './features/soporte/components/auditoria-eventos/auditoria-eventos.component';
import { DocumentosComponent } from './features/soporte/components/documentos/documentos.component';
import { AdministracionComponent } from './features/administracion/administracion.component';
import { ContabilidadComponent } from './features/administracion/components/contabilidad/contabilidad.component';
import { CxcComponent } from './features/administracion/components/cxc/cxc.component';
import { CxpComponent } from './features/administracion/components/cxp/cxp.component';
import { ReportesComponent } from './features/administracion/components/reportes/reportes.component';
import { ControllingComponent } from './features/administracion/components/controlling/controlling.component';
import { TributarioComponent } from './features/administracion/components/tributario/tributario.component';
import { CajaChicaComponent } from './features/administracion/components/caja-chica/caja-chica.component';
import { ConciliacionComponent } from './features/administracion/components/conciliacion/conciliacion.component';
import { ActivosFijosComponent } from './features/administracion/components/activos-fijos/activos-fijos.component';

// Roles que NO pueden acceder a Requerimientos, Compras, Salidas y Planos
const _ROLES_BLOQUEADOS_LOGISTICA_AVANZADA = ['Técnico', 'Jefe de Operaciones'];
const _ROLES_BLOQUEADOS_TECNICO = ['Técnico'];
// Portal Cliente: lazy (loadComponent) — ver bloque de rutas 'portal-cliente/*' más abajo.

export const routes: Routes = [
  {
    path: '',
    component: LoginComponent,
    title: 'Login | e-zyro TIC'
  },
  {
    path: 'reset-password',
    component: ResetPasswordComponent,
    title: 'Recuperar Contraseña | e-zyro TIC'
  },
  {
    path: 'home',
    component: HomeComponent,
    title: 'Inicio | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'personal',
    component: PersonalComponent,
    title: 'Personal | e-zyro TIC',
    canActivate: [authGuard]
  },

  // ── Módulo Recursos Humanos (HU-30) ────
  {
    path: 'rrhh/legajo',
    component: LegajoListaComponent,
    title: 'Legajo Digital | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(['Administración'])]
  },
  {
    path: 'rrhh/legajo/:id',
    component: LegajoDetalleComponent,
    title: 'Expediente | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(['Administración'])]
  },
  {
    path: 'rrhh/solicitudes',
    component: SolicitudesListaComponent,
    title: 'Bandeja de Solicitudes | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(['Administración'])]
  },
  {
    path: 'rrhh/planillas',
    component: PlanillasComponent,
    title: 'Planillas | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(['Administración'])]
  },
  {
    path: 'rrhh/asistencia',
    component: AsistenciaDashboardComponent,
    title: 'Asistencia | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(['Administración'])]
  },
  {
    path: 'rrhh/homologacion',
    component: DocumentosSstComponent,
    title: 'Homologación / SST | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(['Administración'])]
  },
  {
    path: 'asistencia',
    component: AsistenciaComponent,
    title: 'Marcar Asistencia | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'calendario',
    component: CalendarioComponent,
    title: 'Mi Calendario | e-zyro TIC',
    canActivate: [authGuard]
  },

  {
    path: 'mas',
    component: MasComponent,
    title: 'Más | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'permisos',
    component: PermisosComponent,
    canActivate: [authGuard]
  },
  {
    path: 'configuracion',
    component: ConfiguracionComponent,
    canActivate: [authGuard]
  },
  {
    path: 'centro-ayuda',
    component: CentroAyudaComponent,
    title: 'Centro de Ayuda | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'documentacion',
    component: DocumentacionComponent,
    title: 'Documentación | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(_ROLES_BLOQUEADOS_TECNICO)]
  },
  {
    path: 'operaciones',
    component: OperacionesComponent,
    title: 'Operaciones | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'logistica',
    component: LogisticaComponent,
    title: 'Logística | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'logistica/requerimientos',
    component: RequerimientosComponent,
    title: 'Requerimientos | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(_ROLES_BLOQUEADOS_LOGISTICA_AVANZADA)]
  },
  {
    path: 'logistica/compras',
    component: ComprasComponent,
    title: 'Compras | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(_ROLES_BLOQUEADOS_LOGISTICA_AVANZADA)]
  },
  {
    path: 'logistica/salidas',
    component: SalidasComponent,
    title: 'Salida de Inventario | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(_ROLES_BLOQUEADOS_LOGISTICA_AVANZADA)]
  },
  {
    path: 'operaciones/servicios',
    component: LogisticaServiciosComponent,
    title: 'Servicios | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'operaciones/mantenimiento',
    component: MantenimientoEquiposComponent,
    title: 'Mantenimiento de Equipos | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'operaciones/mantenimiento/mapa',
    component: MapaParqueComponent,
    title: 'Mapa del Parque de Equipos | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'operaciones/mantenimiento/:id',
    component: DetalleEquipoComponent,
    title: 'Detalle de Equipo | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'operaciones/calibraciones',
    component: CalibracionesComponent,
    title: 'Calibraciones | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'operaciones/proyecto/:id',
    component: OperacionesServiciosListaComponent,
    title: 'Servicios del Proyecto | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'operaciones/servicio/:id',
    component: OperacionesDetalleComponent,
    title: 'Detalle de Servicio | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'operaciones/cronograma/:proyectoId',
    component: OperacionesCronogramaComponent,
    title: 'Cronograma | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'operaciones/servicio/:id/equipos-intervenidos',
    component: EquiposIntervenidosComponent,
    title: 'Equipos Intervenidos | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'operaciones/servicio/:id/equipos-intervenidos/:eiId',
    component: IntervencionEquipoComponent,
    title: 'Intervención de Equipo | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'operaciones/servicio/:id/equipos-intervenidos/:eiId/certificado/:tipo',
    component: CertificadoComponent,
    title: 'Certificado | e-zyro TIC',
    canActivate: [authGuard]
  },

  // ── Portal Cliente (HU-22) — reutiliza el layout/navbar del ERP ────
  {
    path: 'portal-cliente',
    redirectTo: 'portal-cliente/dashboard',
    pathMatch: 'full',
  },
  {
    path: 'portal-cliente/dashboard',
    loadComponent: () => import('./features/portal-cliente/dashboard/portal-dashboard.component').then(m => m.PortalDashboardComponent),
    title: 'Dashboard | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'portal-cliente/proyectos',
    loadComponent: () => import('./features/portal-cliente/proyectos/portal-proyectos.component').then(m => m.PortalProyectosComponent),
    title: 'Proyectos | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'portal-cliente/proyecto/:id',
    loadComponent: () => import('./features/portal-cliente/proyecto-detalle/portal-proyecto-detalle.component').then(m => m.PortalProyectoDetalleComponent),
    title: 'Detalle Proyecto | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'portal-cliente/documentos',
    loadComponent: () => import('./features/portal-cliente/documentos/portal-documentos.component').then(m => m.PortalDocumentosComponent),
    title: 'Documentos | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'portal-cliente/mantenimientos',
    loadComponent: () => import('./features/portal-cliente/mantenimientos/client-equipment-history.component').then(m => m.ClientEquipmentHistoryComponent),
    title: 'Historial de Mantenimientos | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'portal-cliente/mantenimiento/:id',
    loadComponent: () => import('./features/portal-cliente/equipo-detalle/portal-equipo-detalle.component').then(m => m.PortalEquipoDetalleComponent),
    title: 'Detalle Mantenimiento | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'portal-cliente/soporte',
    loadComponent: () => import('./features/portal-cliente/soporte/portal-soporte.component').then(m => m.PortalSoporteComponent),
    title: 'Soporte Técnico | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'soporte/tickets',
    component: TicketsSoporteComponent,
    title: 'Tickets TI | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(['Administración', 'Admin'])]
  },
  {
    path: 'soporte/monitoreo',
    component: MonitoreoComponent,
    title: 'Monitoreo | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(['Administración', 'Admin'])]
  },
  {
    path: 'soporte/seguridad',
    component: SeguridadComponent,
    title: 'Seguridad | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(['Administración', 'Admin'])]
  },
  {
    path: 'soporte/cuentas',
    component: CrearCuentasComponent,
    title: 'Creación de Cuentas | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(['Administración', 'Admin'])]
  },
  {
    path: 'soporte/gestion-permisos',
    component: GestionPermisosComponent,
    title: 'Gestión de Permisos | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(['Administración', 'Admin'])]
  },
  {
    // Lista BLANCA (no negra como el resto de Gestión TIC): los backups
    // contienen la BD completa — solo Soporte/TI deben ver esta pantalla.
    // El backend refuerza con 403 en /backups para cualquier otro rol.
    path: 'soporte/backups',
    component: BackupsComponent,
    title: 'Backups | e-zyro TIC',
    canActivate: [authGuard, rolesGuard(['Soporte', 'TI'])]
  },
  {
    // Lista BLANCA: monitoreo de seguridad — solo Soporte/TI.
    path: 'soporte/seguridad-monitoreo',
    component: SeguridadMonitoreoComponent,
    title: 'Monitoreo de Seguridad | e-zyro TIC',
    canActivate: [authGuard, rolesGuard(['Soporte', 'TI'])]
  },
  {
    // Lista BLANCA: registro de eventos de acceso y seguridad — solo Soporte/TI.
    path: 'soporte/auditoria-eventos',
    component: AuditoriaEventosComponent,
    title: 'Auditoría de Eventos | e-zyro TIC',
    canActivate: [authGuard, rolesGuard(['Soporte', 'TI'])]
  },
  {
    // Lista BLANCA: documentos generados por el sistema — solo Soporte/TI.
    path: 'soporte/documentos',
    component: DocumentosComponent,
    title: 'Documentos | e-zyro TIC',
    canActivate: [authGuard, rolesGuard(['Soporte', 'TI'])]
  },

  // ── Módulo Administración ────────────────────────────────────────────────
  {
    path: 'administracion',
    component: AdministracionComponent,
    canActivate: [authGuard, rolesGuard(['Administración', 'Admin', 'Soporte'])],
    children: [
      { path: '', redirectTo: 'contabilidad', pathMatch: 'full' },
      { path: 'contabilidad',  component: ContabilidadComponent,  title: 'Contabilidad | e-zyro TIC' },
      { path: 'cxc',          component: CxcComponent,            title: 'Cuentas por Cobrar | e-zyro TIC' },
      { path: 'cxp',          component: CxpComponent,            title: 'Cuentas por Pagar | e-zyro TIC' },
      { path: 'reportes',     component: ReportesComponent,       title: 'Reportes Financieros | e-zyro TIC' },
      { path: 'planilla',     component: PlanillasComponent,      title: 'Planilla | e-zyro TIC' },
      { path: 'controlling',  component: ControllingComponent,    title: 'Controlling | e-zyro TIC' },
      { path: 'tributario',   component: TributarioComponent,     title: 'Tributario | e-zyro TIC' },
      { path: 'caja-chica',   component: CajaChicaComponent,      title: 'Caja Chica | e-zyro TIC' },
      { path: 'conciliacion', component: ConciliacionComponent,   title: 'Conciliación Bancaria | e-zyro TIC' },
      { path: 'activos-fijos',component: ActivosFijosComponent,   title: 'Activos Fijos | e-zyro TIC' },
    ]
  },
  {
    path: '**',
    redirectTo: ''
  }
];