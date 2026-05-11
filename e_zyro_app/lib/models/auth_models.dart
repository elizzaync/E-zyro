class LoginRequest {
  final String username;
  final String password;

  LoginRequest({required this.username, required this.password});

  Map<String, dynamic> toJson() => {'username': username, 'password': password};
}

class LoginResponse {
  final String status;
  final String mensaje;
  final LoginData data;

  LoginResponse({
    required this.status,
    required this.mensaje,
    required this.data,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      status: json['status'] ?? '',
      mensaje: json['mensaje'] ?? '',
      data: LoginData.fromJson(json['data'] ?? {}),
    );
  }
}

class LoginData {
  final String nombreCompleto;
  final String rol;
  final String token;
  final String fotoUrl;

  LoginData({
    required this.nombreCompleto,
    required this.rol,
    required this.token,
    required this.fotoUrl,
  });

  factory LoginData.fromJson(Map<String, dynamic> json) {
    return LoginData(
      nombreCompleto: json['nombre_completo'] ?? '',
      rol: json['rol'] ?? '',
      token: json['token'] ?? '',
      fotoUrl: json['foto_url'] ?? '',
    );
  }
}

class PasswordResetRequest {
  final String email;

  PasswordResetRequest({required this.email});

  Map<String, dynamic> toJson() => {'email': email};
}

class PasswordVerifyCode {
  final String email;
  final String code;

  PasswordVerifyCode({required this.email, required this.code});

  Map<String, dynamic> toJson() => {'email': email, 'code': code};
}

class PasswordResetConfirm {
  final String email;
  final String code;
  final String newPassword;

  PasswordResetConfirm({
    required this.email,
    required this.code,
    required this.newPassword,
  });

  Map<String, dynamic> toJson() => {
    'email': email,
    'code': code,
    'new_password': newPassword,
  };
}

class ApiResponse<T> {
  final String status;
  final String mensaje;
  final T? data;

  ApiResponse({required this.status, required this.mensaje, this.data});

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>)? fromJsonT,
  ) {
    return ApiResponse(
      status: json['status'] ?? '',
      mensaje: json['mensaje'] ?? '',
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'])
          : null,
    );
  }
}
