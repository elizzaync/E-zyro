import { Component, signal, inject, OnInit } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { ReactiveFormsModule, FormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { RouterModule, Router } from '@angular/router';

import { AlertComponent } from '../../../shared/components/login/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';
import { PasswordStrengthComponent } from '../../../shared/components/password-strength/password-strength.component';
import { SuccessCheckmarkComponent } from '../../../shared/components/success-checkmark/success-checkmark.component';
import { AuthService } from '../../../core/services/auth.service';

type ResetStep = 'EMAIL' | 'CODE' | 'PASSWORD' | 'SUCCESS';
type CodeStatus = 'idle' | 'validating' | 'success' | 'error';

@Component({
  selector: 'app-reset-password',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, FormsModule, RouterModule, AlertComponent, SpinnerComponent, PasswordStrengthComponent, SuccessCheckmarkComponent],
  templateUrl: './reset-password.component.html',
  styleUrls: ['./reset-password.component.css']
})
export class ResetPasswordComponent implements OnInit {
  private fb = inject(FormBuilder);
  private router = inject(Router);
  private authService = inject(AuthService);
  private location = inject(Location);

  isUserAuthenticated = false;
  cerrarOtrasSesiones = false;

  currentStep = signal<ResetStep>('EMAIL');
  isLoading = signal(false);

  errorMessage = signal('');
  successMessage = signal('');
  codeStatus = signal<CodeStatus>('idle');

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

  ngOnInit(): void {
    this.isUserAuthenticated = this.authService.isAuthenticated();
  }

  volver(): void {
    if (this.isUserAuthenticated) {
      this.location.back();
    } else {
      this.router.navigate(['/login']);
    }
  }

  finalizarFlujo(): void {
    if (this.cerrarOtrasSesiones && this.isUserAuthenticated) {
      this.isLoading.set(true);
      this.authService.logoutAllDevices().subscribe(() => {
        this.isLoading.set(false);
        this.redirigirTrasExito();
      });
    } else {
      this.redirigirTrasExito();
    }
  }

  private redirigirTrasExito(): void {
    if (this.isUserAuthenticated) {
      this.router.navigate(['/home']);
    } else {
      this.router.navigate(['/login']);
    }
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
    this.successMessage.set('');

    const correoIngresado = this.email.value.toLowerCase();

    this.authService.solicitarCodigoRecuperacion(correoIngresado).subscribe({
      next: () => {
        this.isLoading.set(false);
        // 1. Mostramos la alerta verde en la pantalla actual
        this.successMessage.set('¡Correo validado! Revisa tu bandeja de entrada.');

        // 2. Esperamos 2 segundos para que el usuario lea, y cambiamos de pantalla
        setTimeout(() => {
          this.currentStep.set('CODE');
          this.successMessage.set(''); // Limpiamos la alerta para que no viaje al Paso 2
        }, 2000);
      },
      error: (err) => {
        this.isLoading.set(false);
        this.errorMessage.set(err.error?.detail || 'Este correo no está registrado en el sistema.');
      }
    });
  }

  // ── NUEVO: Escuchador directo del input del código ──
  onCodeInput(): void {
    // Si estaba en rojo por un error anterior, lo limpiamos apenas vuelva a escribir
    if (this.codeStatus() === 'error') {
      this.codeStatus.set('idle');
      this.errorMessage.set('');
    }

    // Si llega a 6 dígitos exactos, disparamos la verificación automáticamente
    const val = this.code.value;
    if (val && val.length === 6 && this.codeForm.valid && this.codeStatus() !== 'validating' && this.codeStatus() !== 'success') {
      this.submitCode();
    }
  }

  // ── PASO 2: Verificar Código en Backend ──
  submitCode(): void {
    if (this.codeForm.invalid) return;

    this.codeStatus.set('validating');
    this.isLoading.set(true);
    this.errorMessage.set('');

    this.authService.verificarCodigo(this.email.value, this.code.value).subscribe({
      next: () => {
        this.codeStatus.set('success');
        this.isLoading.set(false);

        // Pausa elegante antes de ir a crear contraseña
        setTimeout(() => {
          this.currentStep.set('PASSWORD');
          this.codeStatus.set('idle');
        }, 1500);
      },
      error: (err) => {
        this.codeStatus.set('error');
        this.isLoading.set(false);
        this.errorMessage.set(err.error?.detail || 'El código es incorrecto o ha expirado.');
      }
    });
  }

  volverAlEmail(): void {
    this.currentStep.set('EMAIL');
    this.codeForm.reset();
    this.errorMessage.set('');
    this.successMessage.set('');
    this.codeStatus.set('idle');
  }

  // ── PASO 3: Guardar Nueva Clave en Backend ──
  submitPassword(): void {
    if (this.passwordForm.invalid || this.noCoinciden()) {
      this.passwordForm.markAllAsTouched();
      return;
    }
    this.isLoading.set(true);
    this.errorMessage.set('');

    this.authService.actualizarPassword(this.email.value, this.code.value, this.nuevaPassword.value).subscribe({
      next: () => {
        this.isLoading.set(false);
        this.currentStep.set('SUCCESS');
      },
      error: (err) => {
        this.isLoading.set(false);
        this.errorMessage.set(err.error?.detail || 'Hubo un error al actualizar la contraseña.');
      }
    });
  }
}