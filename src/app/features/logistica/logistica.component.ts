import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { LogisticaService } from '../../core/services/logistica.service';
import { AuthService } from '../../core/services/auth.service';
import { LogisticaKpis } from './logistica.models';
import { MaterialesTablaComponent } from './components/materiales-tabla/materiales-tabla.component';
import { EquiposTablaComponent } from './components/equipos-tabla/equipos-tabla.component';
import { SalidasComponent } from './components/salidas/salidas.component';
import { IngresosTablaComponent } from './components/ingresos-tabla/ingresos-tabla.component';
import { RetornosTablaComponent } from './components/retornos-tabla/retornos-tabla.component';
import { IncidenciasTablaComponent } from './components/incidencias-tabla/incidencias-tabla.component';

type TabLogistica = 'materiales' | 'equipos' | 'salidas' | 'ingresos' | 'retornos' | 'incidencias';

@Component({
  selector: 'app-logistica',
  standalone: true,
  imports: [CommonModule, MaterialesTablaComponent, EquiposTablaComponent, SalidasComponent, IngresosTablaComponent, RetornosTablaComponent, IncidenciasTablaComponent],
  templateUrl: './logistica.component.html',
  styleUrls: ['./logistica.component.css']
})
export class LogisticaComponent implements OnInit {
  private svc  = inject(LogisticaService);
  private auth = inject(AuthService);

  get isTecnico(): boolean { return this.auth.isTecnico(); }
  get isJefeOperaciones(): boolean { return this.auth.isJefeOperaciones(); }
  get esOperativo(): boolean { return this.isTecnico || this.isJefeOperaciones; }

  tab: TabLogistica = 'materiales';
  kpis: LogisticaKpis = {
    totalMateriales: 0, materialesStockBajo: 0,
    totalEquipos: 0, totalHerramientas: 0, enMantenimiento: 0,
  };

  ngOnInit(): void { this.cargarKpis(); }

  cargarKpis(): void {
    this.svc.getKpis().subscribe({ next: k => (this.kpis = k) });
  }

  setTab(t: TabLogistica): void { this.tab = t; }
}
