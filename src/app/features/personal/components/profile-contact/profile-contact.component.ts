import { Component, Input, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute } from '@angular/router';

@Component({
  selector: 'app-profile-contact',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './profile-contact.component.html',
  styleUrls: ['./profile-contact.component.css']
})
export class ProfileContactComponent implements OnInit {
  @Input() perfil: any = {};

  tabActiva: string = 'perfil';
  private route = inject(ActivatedRoute);
  ngOnInit() {
    this.route.queryParams.subscribe(params => {
      if (params['tab']) {
        this.tabActiva = params['tab'];
      }
    });
  }

  cambiarTab(tab: string) {
    this.tabActiva = tab;
  }
}