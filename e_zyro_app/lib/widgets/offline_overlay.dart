import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../core/connectivity_service.dart';

/// Envuelve un widget hijo: si hay red lo muestra normal,
/// si no hay red reemplaza la pantalla con el aviso offline.
class OfflineOverlay extends StatelessWidget {
  final Widget child;
  const OfflineOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isOnlineNotifier,
      builder: (context, isOnline, child) =>
          isOnline ? this.child : const _OfflineScreen(),
    );
  }
}

class _OfflineScreen extends StatelessWidget {
  const _OfflineScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.wifi_off_rounded,
                  size: 56,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Sin conexión',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Esta sección requiere internet para cargar.\n\nPuedes marcar tu asistencia y consultar tus proyectos sin conexión.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final r = await Connectivity().checkConnectivity();
                  isOnlineNotifier.value =
                      ConnectivityService.isConnected(r);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner fino que aparece en la parte superior cuando no hay red.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isOnlineNotifier,
      builder: (context, isOnline, child) {
        if (isOnline) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFFD98A16), // ámbar
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 15, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Sin conexión · Asistencia y proyectos disponibles offline',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
