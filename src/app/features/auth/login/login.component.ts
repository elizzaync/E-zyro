import { Component, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Router, RouterModule } from '@angular/router';
import { AlertComponent } from '../../../shared/components/login/alert.component';
import { SpinnerComponent } from '../../../shared/components/spinner/spinner.component';
import { AuthService } from '../../../core/services/auth.service';

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

  isAuthenticating = signal(false);
  errorMessage = signal('');
  successMessage = signal('');
  isPreparingEnv = signal(false);

  constructor(
    private fb: FormBuilder,
    private router: Router,
    private authService: AuthService // 2. INYECTAR EL SERVICIO
  ) {
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
    // 3. LLAMADA REAL A LA API
    this.authService.login({ username, password }).subscribe({
      next: (response) => {
        // La API validó la contraseña encriptada correctamente
        this.isAuthenticating.set(false);

        // Podemos usar el nombre real que viene de la base de datos!
        const nombre = response.data.nombre_completo;
        this.successMessage.set(`¡Bienvenido(a), ${nombre}! Preparando entorno...`);

        setTimeout(() => {
          this.isPreparingEnv.set(true);
          // Redirección final al panel principal (asegúrate de tener esta ruta creada)
          setTimeout(() => this.router.navigate(['/home']), 1500);
        }, 1500);
      },
      error: (err) => {
        this.isAuthenticating.set(false);
        if (err.status === 401) {
          this.errorMessage.set('Usuario o contraseña incorrectos.');
        } else {
          this.errorMessage.set('Error de conexión con el servidor.');
        }
      }
    });
  }
}