import 'package:flutter/material.dart';

class PersonalScreen extends StatefulWidget {
  const PersonalScreen({super.key});

  @override
  State<PersonalScreen> createState() => _PersonalScreenState();
}

class _PersonalScreenState extends State<PersonalScreen> {
  // TODO: Reemplazar con estado real
  int _selectedTab = 0;
  final List<String> _tabs = ['Perfil', 'Asistencia', 'Documentos'];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Encabezado ────────────────────────────────────────
                const Text(
                  'Personal',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // ── Tabs ─────────────────────────────────────────────
                Row(
                  children: List.generate(
                    _tabs.length,
                    (i) => _TabButton(
                      label: _tabs[i],
                      isSelected: _selectedTab == i,
                      onTap: () => setState(() => _selectedTab = i),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // ── Contenido según tab ──────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: const [
                _ProfileTab(),
                _AttendanceTab(),
                _DocumentsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Botón de tab ─────────────────────────────────────────────────────────────
class _TabButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8FD11B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF8FD11B) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Tab: Perfil ──────────────────────────────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Avatar + datos
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: const Color(0xFF8FD11B),
                  child: const Icon(
                    Icons.person,
                    size: 44,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                // TODO: Reemplazar con datos reales del usuario
                const Text(
                  'Alex Rodriguez',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Técnico Senior de Campo',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'EMP-2847',
                  style: TextStyle(
                    color: Color(0xFF8FD11B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Información de contacto
          _InfoSection(
            title: 'Información de Contacto',
            items: const [
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Teléfono',
                value: '+1 (555) 123-4567', // TODO: dato real
              ),
              _InfoRow(
                icon: Icons.email_outlined,
                label: 'Correo',
                value: 'alex.rodriguez@esystem.com', // TODO: dato real
              ),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Ubicación',
                value: 'Área de la Bahía de San Francisco', // TODO: dato real
              ),
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: 'Fecha de Ingreso',
                value: 'Enero 2024', // TODO: dato real
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Certificaciones (placeholder)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Certificaciones',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                SizedBox(height: 8),
                // TODO: Lista dinámica de certificaciones
                Text(
                  '(conectar con datos reales)',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final List<_InfoRow> items;

  const _InfoSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          ...items,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFFAE0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF8FD11B)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Tab: Asistencia (placeholder) ───────────────────────────────────────────
class _AttendanceTab extends StatelessWidget {
  const _AttendanceTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Vista de Asistencia\n(conectar con datos reales)',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey),
      ),
    );
  }
}

// ─── Tab: Documentos (placeholder) ───────────────────────────────────────────
class _DocumentsTab extends StatelessWidget {
  const _DocumentsTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Vista de Documentos\n(conectar con datos reales)',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey),
      ),
    );
  }
}
