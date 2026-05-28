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
import { OperacionesDetalleComponent } from './features/operaciones/components/operaciones-detalle/operaciones-detalle.component';
import { OperacionesServiciosListaComponent } from './features/operaciones/components/operaciones-servicios-lista/operaciones-servicios-lista.component';
import { OperacionesCronogramaComponent } from './features/operaciones/components/operaciones-cronograma/operaciones-cronograma.component';
import { EquiposIntervenidosComponent } from './features/operaciones/components/equipos-intervenidos/equipos-intervenidos.component';
import { EquiposZonaComponent } from './features/operaciones/components/equipos-intervenidos/components/equipos-zona/equipos-zona.component';
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
    path: 'operaciones/servicio/:id/equipos',
    component: EquiposIntervenidosComponent,
    title: 'Equipos Intervenidos | E-System Tic',
    canActivate: [authGuard]
},
{
    path: 'operaciones/servicio/:id/equipos/:zonaId',
    component: EquiposZonaComponent,
    title: 'Equipos por Zona | E-System Tic',
    canActivate: [authGuard]
},
  {
    path: '**',
    redirectTo: ''
  }
];