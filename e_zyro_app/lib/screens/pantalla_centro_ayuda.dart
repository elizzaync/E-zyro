import 'package:flutter/material.dart';
import '../utils/app_session.dart';
import 'pantalla_soporte.dart';
import 'pantalla_manual_usuario.dart';
import 'finanzas/pantalla_manual_finanzas.dart';

const _kGreen = Color(0xFF5A9A00);

class PantallaCentroAyuda extends StatefulWidget {
  const PantallaCentroAyuda({super.key});

  @override
  State<PantallaCentroAyuda> createState() => _PantallaCentroAyudaState();
}

class _PantallaCentroAyudaState extends State<PantallaCentroAyuda> {
  @override
  void initState() {
    super.initState();
    AppSession.load();
  }

  void _abrirManuales() {
    final s = AppSession.i;
    // Manuales disponibles según el rol del usuario
    final manuales = <_Manual>[
      if (s.esSuperAdmin)
        const _Manual('Manual SuperAdmin', 'assets/docs/manual_superadmin.md',
            Icons.admin_panel_settings_outlined),
      if (s.isAdmin)
        const _Manual('Manual Administrador', 'assets/docs/manual_admin.md',
            Icons.manage_accounts_outlined),
      if (s.canVerFinanzas)
        const _Manual(null, null, Icons.account_balance_outlined,
            isFinanzas: true),
      // Manuales siempre disponibles según rol
      const _Manual('Manual Jefe de Operaciones',
          'assets/docs/manual_jefe_operaciones.md', Icons.engineering_outlined),
      const _Manual('Manual Técnico', 'assets/docs/manual_tecnico.md',
          Icons.construction_outlined),
      const _Manual('Manual Logístico', 'assets/docs/manual_logistico.md',
          Icons.warehouse_outlined),
      const _Manual('Manual Cliente / Portal',
          'assets/docs/manual_cliente_portal.md', Icons.people_outline),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (ctx, scroll) => Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Manuales disponibles',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scroll,
                  itemCount: manuales.length,
                  separatorBuilder: (ctx3, idx) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (ctx2, i) {
                    final m = manuales[i];
                    return ListTile(
                      leading: Icon(m.icon, color: _kGreen),
                      title: Text(m.isFinanzas
                          ? 'Manual de Usuario · Finanzas'
                          : m.titulo!),
                      subtitle: m.isFinanzas
                          ? const Text(
                              'Pantallas, asientos contables PCGE y flujos',
                              style: TextStyle(fontSize: 12))
                          : null,
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () {
                        Navigator.pop(context);
                        if (m.isFinanzas) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const PantallaManualFinanzas()),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PantallaManualUsuario(
                                titulo: m.titulo!,
                                assetPath: m.assetPath!,
                              ),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    BoxDecoration groupDeco = BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Centro de Ayuda')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Recursos ────────────────────────────────────────────────────
          _sec('Recursos'),
          const SizedBox(height: 10),
          Container(
            decoration: groupDeco,
            child: Column(children: [
              _tile(
                icon: Icons.description_outlined,
                label: 'Manuales de usuario',
                subtitle: 'Guías por rol: Técnico, Logístico, Admin y más',
                onTap: _abrirManuales,
              ),
              const Divider(height: 1, indent: 56),
              _tile(
                icon: Icons.support_agent_outlined,
                label: 'Soporte TI',
                subtitle: 'Reportar un problema técnico con la app',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PantallaSoporte())),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // ── Contacto ────────────────────────────────────────────────────
          _sec('Contacto'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: groupDeco,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.email_outlined, size: 18, color: _kGreen),
                  SizedBox(width: 10),
                  Text('soporte@esystemtic.com',
                      style: TextStyle(fontSize: 14)),
                ]),
                SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.access_time_outlined, size: 18, color: _kGreen),
                  SizedBox(width: 10),
                  Text('Lun–Vie · 8:00 am – 6:00 pm',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                ]),
                SizedBox(height: 6),
                Text(
                  'Respuesta en 24 horas hábiles',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Preguntas frecuentes ─────────────────────────────────────────
          _sec('Preguntas frecuentes'),
          const SizedBox(height: 10),
          Container(
            decoration: groupDeco,
            child: Column(
              children: const [
                _Faq(
                  pregunta: '¿Qué hago si no tengo conexión a internet?',
                  respuesta:
                      'La app funciona en modo offline. Tus asistencias, '
                      'procedimientos y fotos se guardan localmente y se '
                      'sincronizan automáticamente cuando vuelve la conexión.',
                ),
                Divider(height: 1, indent: 20),
                _Faq(
                  pregunta: '¿Cómo recupero mi contraseña?',
                  respuesta:
                      'Contacta a tu administrador de empresa o al equipo '
                      'de Soporte TI para que restablezcan tu contraseña.',
                ),
                Divider(height: 1, indent: 20),
                _Faq(
                  pregunta: '¿Las fotos de evidencia se borran?',
                  respuesta:
                      'No. Las fotos se almacenan de forma permanente en '
                      'el servidor. Solo un Admin puede eliminarlas.',
                ),
                Divider(height: 1, indent: 20),
                _Faq(
                  pregunta: '¿Puedo usar la app en modo avión?',
                  respuesta:
                      'Sí. Puedes registrar asistencia, tomar fotos y '
                      'completar procedimientos. Todo se sincroniza al '
                      'recuperar conexión.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sec(String t) => Text(
        t.toUpperCase(),
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
            letterSpacing: 0.8),
      );

  Widget _tile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: Icon(icon, size: 22),
        title: Text(label,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing:
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        onTap: onTap,
      );
}

class _Manual {
  const _Manual(this.titulo, this.assetPath, this.icon,
      {this.isFinanzas = false});
  final String? titulo;
  final String? assetPath;
  final IconData icon;
  final bool isFinanzas;
}

class _Faq extends StatefulWidget {
  const _Faq({required this.pregunta, required this.respuesta});
  final String pregunta;
  final String respuesta;

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      childrenPadding:
          const EdgeInsets.fromLTRB(18, 0, 18, 14),
      leading: const Icon(Icons.help_outline, size: 20, color: _kGreen),
      title: Text(widget.pregunta,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      initiallyExpanded: _expanded,
      onExpansionChanged: (v) => setState(() => _expanded = v),
      children: [
        Text(widget.respuesta,
            style: const TextStyle(
                fontSize: 13, height: 1.55, color: Colors.grey)),
      ],
    );
  }
}
