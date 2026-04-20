import { Component, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { RouterModule, Router, ActivatedRoute } from '@angular/router';
import { AlertComponent } from '../shared/components/login/alert.component';
import { SpinnerComponent } from '../shared/components/spinner/spinner.component';

@Component({
  selector: 'app-new-password',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, RouterModule, AlertComponent, SpinnerComponent],
  templateUrl: './new-password.component.html',
  styleUrls: ['./new-password.component.css']
})
export class NewPasswordComponent implements OnInit {
  newPasswordForm: FormGroup;

  showPassword  = signal(false);
  showConfirm   = signal(false);
  isGuardando   = signal(false);
  errorMessage  = signal('');
  successMessage = signal('');
  tokenInvalido = signal(false);

  private token = '';

  // ── Fortaleza de contraseña ──────────────────────────────────────────────
  strengthClass = computed(() => {
    const val = this.newPasswordForm?.get('nuevaPassword')?.value ?? '';
    const score = this.calcScore(val);
    if (score <= 1) return 'weak';
    if (score <= 3) return 'medium';
    return 'strong';
  });

  strengthLabel = computed(() => {
    const map: Record<string, string> = {
      weak:   'Débil',
      medium: 'Media',
      strong: 'Fuerte'
    };
    return map[this.strengthClass()];
  });

  constructor(
    private fb: FormBuilder,
    private router: Router,
    private route: ActivatedRoute
  ) {
    this.newPasswordForm = this.fb.group({
      nuevaPassword:    ['', [Validators.required, Validators.minLength(6)]],
      confirmarPassword: ['', [Validators.required]]
    });
  }

  ngOnInit(): void {
    // Lee el token del query param: /new-password?token=ABC123
    this.token = this.route.snapshot.queryParamMap.get('token') ?? '';
    if (!this.token) {
      this.tokenInvalido.set(true);
    }
    // Aquí puedes validar el token contra el backend si lo deseas
  }

  get nuevaPassword()    { return this.newPasswordForm.get('nuevaPassword')!; }
  get confirmarPassword() { return this.newPasswordForm.get('confirmarPassword')!; }

  noCoinciden(): boolean {
    return this.nuevaPassword.value !== this.confirmarPassword.value &&
           this.confirmarPassword.touched;
  }

  togglePassword(): void { this.showPassword.update(v => !v); }
  toggleConfirm():  void { this.showConfirm.update(v => !v); }

  onSubmit(): void {
    if (this.newPasswordForm.invalid || this.noCoinciden()) {
      this.newPasswordForm.markAllAsTouched();
      return;
    }

    this.isGuardando.set(true);
    this.errorMessage.set('');

    // Simulación — reemplaza con tu servicio real pasando this.token
    setTimeout(() => {
      this.isGuardando.set(false);
      this.successMessage.set('ok');

      // Redirige al login después de 2.5s
      setTimeout(() => this.router.navigate(['/']), 2500);
    }, 1500);
  }

  private calcScore(password: string): number {
    let score = 0;
    if (password.length >= 6)  score++;
    if (password.length >= 10) score++;
    if (/[A-Z]/.test(password)) score++;
    if (/[0-9]/.test(password)) score++;
    if (/[^A-Za-z0-9]/.test(password)) score++;
    return score;
  }
}