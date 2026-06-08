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
import { PortalDashboardComponent } from './features/portal-cliente/dashboard/portal-dashboard.component';
import { PortalProyectosComponent } from './features/portal-cliente/proyectos/portal-proyectos.component';
import { PortalProyectoDetalleComponent } from './features/portal-cliente/proyecto-detalle/portal-proyecto-detalle.component';
import { PortalDocumentosComponent } from './features/portal-cliente/documentos/portal-documentos.component';
export const routes: Routes = [
  {
    path: '',
    component: LoginComponent,
    title: 'Login | E-System Tic'
  },
  {
    path: 'reset-password',
    component: ResetPasswordComponent, // <-- Ahora este maneja todo el flujo de 4 pasos
    title: 'Recuperar Contraseña | E-System Tic'
  },
  {
    path: 'home',
    component: HomeComponent,
    title: 'Inicio | E-System Tic',
    canActivate: [authGuard] // Esto bloquea a los que no tienen Token JWT
  },
    {
    path: 'personal',
    component: PersonalComponent,
    title: 'Personal | E-System Tic',
    canActivate: [authGuard]
  },
  {
    path: 'mas',
    component: MasComponent,
    title: 'Más | E-System Tic',
    canActivate: [authGuard]
  },
    { path: 'permisos',
    component: PermisosComponent,
    canActivate: [authGuard] },
  {
    path: 'configuracion',
    component: ConfiguracionComponent,
    canActivate: [authGuard]
  },
  {
    path: 'centro-ayuda',
    component: CentroAyudaComponent,
    title: 'Centro de Ayuda | E-System Tic',
    canActivate: [authGuard]
  },
  {
    path: 'documentacion',
    component: DocumentacionComponent,
    title: 'Documentación | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'operaciones',
    component: OperacionesComponent,
    title: 'Operaciones | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'logistica',
    component: LogisticaComponent,
    title: 'Logística | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'logistica/requerimientos',
    component: RequerimientosComponent,
    title: 'Requerimientos | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'logistica/compras',
    component: ComprasComponent,
    title: 'Compras | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'logistica/salidas',
    component: SalidasComponent,
    title: 'Salidas de Materiales | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'operaciones/proyecto/:id',
    component: OperacionesServiciosListaComponent,
    title: 'Servicios del Proyecto | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'operaciones/servicio/:id',
    component: OperacionesDetalleComponent,
    title: 'Detalle de Servicio | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'operaciones/cronograma/:proyectoId',
    component: OperacionesCronogramaComponent,
    title: 'Cronograma | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'operaciones/servicio/:id/equipos-intervenidos',
    component: EquiposIntervenidosComponent,
    title: 'Equipos Intervenidos | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'operaciones/servicio/:id/equipos-intervenidos/:eiId',
    component: IntervencionEquipoComponent,
    title: 'Intervención de Equipo | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'operaciones/servicio/:id/equipos-intervenidos/:eiId/certificado/:tipo',
    component: CertificadoComponent,
    title: 'Certificado | E-System Tic',
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
    path: '**',
    redirectTo: ''
  }
];