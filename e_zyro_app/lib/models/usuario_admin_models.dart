// Modelos para la Gestión de usuarios (Admin) — endpoints `/usuarios`.

class UsuarioAdmin {
  final String id;
  final String nombre;
  final String apellido;
  final String email;
  final String username;
  final String? rol;
  final String? rolId;
  final bool activo;
  final bool tieneFicha;

  const UsuarioAdmin({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.email,
    required this.username,
    required this.rol,
    required this.rolId,
    required this.activo,
    required this.tieneFicha,
  });

  String get nombreCompleto => '$nombre $apellido'.trim();

  factory UsuarioAdmin.fromJson(Map<String, dynamic> j) => UsuarioAdmin(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        apellido: j['apellido']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        rol: j['rol']?.toString(),
        rolId: j['rol_id']?.toString(),
        activo: j['activo'] == true,
        tieneFicha: j['tiene_ficha'] == true,
      );
}

class RolItem {
  final String id;
  final String nombre;

  const RolItem({required this.id, required this.nombre});

  factory RolItem.fromJson(Map<String, dynamic> j) => RolItem(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
      );
}
