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
import { OperacionesDetalleComponent } from './features/operaciones/components/operaciones-detalle/operaciones-detalle.component';
import { OperacionesServiciosListaComponent } from './features/operaciones/components/operaciones-servicios-lista/operaciones-servicios-lista.component';
import { OperacionesCronogramaComponent } from './features/operaciones/components/operaciones-cronograma/operaciones-cronograma.component';
import { EquiposIntervenidosComponent } from './features/operaciones/components/equipos-intervenidos/equipos-intervenidos.component';
import { IntervencionEquipoComponent } from './features/operaciones/components/intervencion-equipo/intervencion-equipo.component';
import { CertificadoComponent } from './features/operaciones/components/certificado/certificado.component';
import { clientPortalGuard } from './core/guards/client-portal.guard';
import { bloquearRolesGuard } from './core/guards/roles.guard';
import { LegajoListaComponent } from './features/rrhh/legajo/legajo-lista.component';
import { LegajoDetalleComponent } from './features/rrhh/legajo/components/legajo-detalle/legajo-detalle.component';
import { SolicitudesListaComponent } from './features/rrhh/solicitudes/solicitudes-lista.component';

// Roles que NO pueden acceder a Requerimientos, Compras, Salidas y Planos
const _ROLES_BLOQUEADOS_LOGISTICA_AVANZADA = ['Técnico de Campo', 'Jefe de Operaciones'];
const _ROLES_BLOQUEADOS_TECNICO = ['Técnico de Campo'];
import { PortalDashboardComponent } from './features/portal-cliente/dashboard/portal-dashboard.component';
import { PortalProyectosComponent } from './features/portal-cliente/proyectos/portal-proyectos.component';
import { PortalProyectoDetalleComponent } from './features/portal-cliente/proyecto-detalle/portal-proyecto-detalle.component';
import { PortalDocumentosComponent } from './features/portal-cliente/documentos/portal-documentos.component';
import { PortalEquipoDetalleComponent } from './features/portal-cliente/equipo-detalle/portal-equipo-detalle.component';
import { ClientEquipmentHistoryComponent } from './features/portal-cliente/mantenimientos/client-equipment-history.component';

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
    canActivate: [authGuard]
  },
  {
    path: 'rrhh/legajo/:id',
    component: LegajoDetalleComponent,
    title: 'Expediente | e-zyro TIC',
    canActivate: [authGuard]
  },
  {
    path: 'rrhh/solicitudes',
    component: SolicitudesListaComponent,
    title: 'Bandeja de Solicitudes | e-zyro TIC',
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
    title: 'Salidas de Materiales | e-zyro TIC',
    canActivate: [authGuard, bloquearRolesGuard(_ROLES_BLOQUEADOS_LOGISTICA_AVANZADA)]
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
    component: PortalDashboardComponent,
    title: 'Dashboard | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'portal-cliente/proyectos',
    component: PortalProyectosComponent,
    title: 'Proyectos | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'portal-cliente/proyecto/:id',
    component: PortalProyectoDetalleComponent,
    title: 'Detalle Proyecto | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'portal-cliente/documentos',
    component: PortalDocumentosComponent,
    title: 'Documentos | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'portal-cliente/mantenimientos',
    component: ClientEquipmentHistoryComponent,
    title: 'Historial de Mantenimientos | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: 'portal-cliente/mantenimiento/:id',
    component: PortalEquipoDetalleComponent,
    title: 'Detalle Mantenimiento | Portal Cliente',
    canActivate: [clientPortalGuard],
  },
  {
    path: '**',
    redirectTo: ''
  }
];