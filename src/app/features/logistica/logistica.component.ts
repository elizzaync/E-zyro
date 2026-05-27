import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { LogisticaService } from '../../core/services/logistica.service';
import { LogisticaKpis } from './logistica.models';
import { MaterialesTablaComponent } from './components/materiales-tabla/materiales-tabla.component';
import { EquiposTablaComponent } from './components/equipos-tabla/equipos-tabla.component';

type TabLogistica = 'materiales' | 'equipos';

@Component({
  selector: 'app-logistica',
  standalone: true,
  imports: [CommonModule, MaterialesTablaComponent, EquiposTablaComponent],
  templateUrl: './logistica.component.html',
  styleUrls: ['./logistica.component.css']
})
export class LogisticaComponent implements OnInit {
  private svc = inject(LogisticaService);

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
