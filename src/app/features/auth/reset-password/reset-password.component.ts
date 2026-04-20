import { Component, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { RouterModule } from '@angular/router';
import { AlertComponent } from '../shared/components/login/alert.component';
import { SpinnerComponent } from '../shared/components/spinner/spinner.component';

@Component({
  selector: 'app-forgot-password',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, RouterModule, AlertComponent, SpinnerComponent],
  templateUrl: './reset-password.component.html',
  styleUrls: ['./reset-password.component.css']
})
export class ForgotPasswordComponent {
  forgotForm: FormGroup;
  isSending   = signal(false);
  errorMessage  = signal('');
  successMessage = signal('');

  constructor(private fb: FormBuilder) {
    this.forgotForm = this.fb.group({
      email: ['', [Validators.required, Validators.email]]
    });
  }

  get email() { return this.forgotForm.get('email')!; }

  onSubmit(): void {
    if (this.forgotForm.invalid) {
      this.forgotForm.markAllAsTouched();
      return;
    }

    this.isSending.set(true);
    this.errorMessage.set('');
    this.successMessage.set('');

    // Simulación de llamada al backend
    setTimeout(() => {
      this.isSending.set(false);
      // Aquí conectas tu servicio real
      this.successMessage.set(
        'Si el correo está registrado, recibirás un enlace en tu bandeja de entrada.'
      );
    }, 1500);
  }
}