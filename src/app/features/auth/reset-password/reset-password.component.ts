import { Component, signal, computed, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { RouterModule, Router } from '@angular/router';
import { AlertComponent } from '../shared/components/login/alert.component';
import { SpinnerComponent } from '../shared/components/spinner/spinner.component';
import { PasswordStrengthComponent } from '../shared/components/password-strength/password-strength.component';
import { SuccessCheckmarkComponent } from '../shared/components/success-checkmark/success-checkmark.component';
import { AuthService } from '../../../core/services/auth.service';

type ResetStep = 'EMAIL' | 'CODE' | 'PASSWORD' | 'SUCCESS';

@Component({
  selector: 'app-reset-password',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, RouterModule, AlertComponent, SpinnerComponent, PasswordStrengthComponent, SuccessCheckmarkComponent],
  templateUrl: './reset-password.component.html',
  styleUrls: ['./reset-password.component.css']
})
export class ResetPasswordComponent {
  private fb = inject(FormBuilder);
  private router = inject(Router);
  // 2. INYECTA EL SERVICIO
  private authService = inject(AuthService);

  currentStep = signal<ResetStep>('EMAIL');
  isLoading = signal(false);
  errorMessage = signal('');
  showPassword = signal(false);
  showConfirm = signal(false);

  emailForm: FormGroup;
  codeForm: FormGroup;
  passwordForm: FormGroup;

  constructor() {
    this.emailForm = this.fb.group({
      email: ['', [Validators.required, Validators.email]]
    });
    this.codeForm = this.fb.group({
      code: ['', [Validators.required, Validators.minLength(6), Validators.maxLength(6)]]
    });
    this.passwordForm = this.fb.group({
      nuevaPassword: ['', [Validators.required, Validators.minLength(6)]],
      confirmarPassword: ['', [Validators.required]]
    });
  }

  get email() { return this.emailForm.get('email')!; }
  get code() { return this.codeForm.get('code')!; }
  get nuevaPassword() { return this.passwordForm.get('nuevaPassword')!; }
  get confirmarPassword() { return this.passwordForm.get('confirmarPassword')!; }

  noCoinciden(): boolean {
    return this.nuevaPassword.value !== this.confirmarPassword.value && this.confirmarPassword.touched;
  }
  togglePassword(): void { this.showPassword.update(v => !v); }
  toggleConfirm(): void { this.showConfirm.update(v => !v); }

  // ── PASO 1: Enviar Correo al Backend ──
  submitEmail(): void {
    if (this.emailForm.invalid) {
      this.emailForm.markAllAsTouched();
      return;
    }
    this.isLoading.set(true);
    this.errorMessage.set('');

    const correoIngresado = this.email.value.toLowerCase();

    // LLAMADA REAL
    this.authService.solicitarCodigoRecuperacion(correoIngresado).subscribe({
      next: () => {
        this.isLoading.set(false);
        this.currentStep.set('CODE');
      },
      error: (err) => {
        this.isLoading.set(false);
        // Atrapa el error que mandemos desde FastAPI (ej. 404 Not Found)
        this.errorMessage.set(err.error?.detail || 'Este correo no está registrado en el sistema.');
      }
    });
  }

  // ── PASO 2: Verificar Código en Backend ──
  submitCode(): void {
    if (this.codeForm.invalid) {
      this.codeForm.markAllAsTouched();
      return;
    }
    this.isLoading.set(true);
    this.errorMessage.set('');

    // LLAMADA REAL
    this.authService.verificarCodigo(this.email.value, this.code.value).subscribe({
      next: () => {
        this.isLoading.set(false);
        this.currentStep.set('PASSWORD');
      },
      error: (err) => {
        this.isLoading.set(false);
        this.errorMessage.set(err.error?.detail || 'El código es incorrecto o ha expirado.');
      }
    });
  }

  volverAlEmail(): void {
    this.currentStep.set('EMAIL');
    this.codeForm.reset();
    this.errorMessage.set('');
  }

  // ── PASO 3: Guardar Nueva Clave en Backend ──
  submitPassword(): void {
    if (this.passwordForm.invalid || this.noCoinciden()) {
      this.passwordForm.markAllAsTouched();
      return;
    }
    this.isLoading.set(true);
    this.errorMessage.set('');

    // LLAMADA REAL
    this.authService.actualizarPassword(this.email.value, this.code.value, this.nuevaPassword.value).subscribe({
      next: () => {
        this.isLoading.set(false);
        this.currentStep.set('SUCCESS');
        setTimeout(() => this.router.navigate(['/']), 3000);
      },
      error: (err) => {
        this.isLoading.set(false);
        this.errorMessage.set(err.error?.detail || 'Hubo un error al actualizar la contraseña.');
      }
    });
  }
}