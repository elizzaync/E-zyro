/// Modelos del módulo "Accesos Portal Cliente" (`/portal-accesos`):
/// estado de acceso al portal por cliente y credenciales generadas.
library;

/// Fila de GET /portal-accesos: un cliente activo de la empresa con (o sin)
/// cuenta de portal asociada.
class AccesoPortalCliente {
  final String clienteId;
  final String razonSocial;
  final String ruc;
  final bool tieneAcceso;
  final String? usuarioId;
  final String? username;

  /// null cuando el cliente no tiene acceso; false = acceso revocado.
  final bool? usuarioActivo;
  final String? creadoEn; // ISO

  const AccesoPortalCliente({
    required this.clienteId,
    required this.razonSocial,
    required this.ruc,
    required this.tieneAcceso,
    this.usuarioId,
    this.username,
    this.usuarioActivo,
    this.creadoEn,
  });

  factory AccesoPortalCliente.fromJson(Map<String, dynamic> json) =>
      AccesoPortalCliente(
        clienteId: json['cliente_id']?.toString() ?? '',
        razonSocial: json['razon_social']?.toString() ?? '',
        ruc: json['ruc']?.toString() ?? '',
        tieneAcceso: json['tiene_acceso'] == true,
        usuarioId: json['usuario_id']?.toString(),
        username: json['username']?.toString(),
        usuarioActivo:
            json['usuario_activo'] is bool ? json['usuario_activo'] as bool : null,
        creadoEn: json['creado_en']?.toString(),
      );

  /// true cuando tiene acceso pero el usuario fue desactivado (revocado).
  bool get revocado => tieneAcceso && usuarioActivo == false;
}

/// Credenciales devueltas al crear acceso o restablecer contraseña.
/// La contraseña temporal solo viaja una vez: mostrarla de inmediato.
class CredencialesPortal {
  final String username;
  final String passwordTemporal;

  const CredencialesPortal({
    required this.username,
    required this.passwordTemporal,
  });

  factory CredencialesPortal.fromJson(Map<String, dynamic> json) =>
      CredencialesPortal(
        username: json['username']?.toString() ?? '',
        passwordTemporal: json['password_temporal']?.toString() ?? '',
      );
}
