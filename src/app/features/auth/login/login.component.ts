import { Component, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Router, RouterModule } from '@angular/router';
import { AlertComponent } from '../shared/components/login/alert.component';
import { SpinnerComponent } from '../shared/components/spinner/spinner.component';
@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, RouterModule, AlertComponent, SpinnerComponent],
  templateUrl: './login.component.html',
  styleUrls: ['./login.component.css']
})
export class LoginComponent {
  loginForm: FormGroup;
  showPassword = signal(false);

  // Nuevos estados divididos
  isAuthenticating = signal(false); // Carga en el botón
  errorMessage = signal('');        // Alerta de error
  successMessage = signal('');      // Alerta de éxito en el formulario
  isPreparingEnv = signal(false);   // Pantalla final de carga

  constructor(private fb: FormBuilder, private router: Router) {
    this.loginForm = this.fb.group({
      username: ['', [Validators.required, Validators.minLength(3)]],
      password: ['', [Validators.required, Validators.minLength(6)]],
      rememberMe: [false]
    });
  }

  get username() { return this.loginForm.get('username')!; }
  get password() { return this.loginForm.get('password')!; }

  togglePassword(): void {
    this.showPassword.update(v => !v);
  }

 onSubmit(): void {
    if (this.loginForm.invalid) {
      this.loginForm.markAllAsTouched();
      return;
    }

    this.isAuthenticating.set(true);
    this.errorMessage.set('');
    this.successMessage.set('');

    const { username, password } = this.loginForm.value;

    // 1. Simulamos la llamada a la base de datos
    setTimeout(() => {
      this.isAuthenticating.set(false);

      if (username === 'admin' && password === '123456') {
        // 2. Credenciales correctas: Mostramos alerta verde en el form
        this.successMessage.set('Autenticación exitosa. Redirigiendo...');

        // 3. Esperamos 1.5 segundos para que el usuario lea la alerta
        setTimeout(() => {
          this.isPreparingEnv.set(true); // Oculta el form, muestra pantalla de carga

          // 4. Simulamos la carga del sistema antes de ir al dashboard
          // setTimeout(() => this.router.navigate(['/dashboard']), 2000);
        }, 1500);

      } else {
        // Credenciales incorrectas
        this.errorMessage.set('Usuario o contraseña incorrectos.');
      }
    }, 1200);
  }
}