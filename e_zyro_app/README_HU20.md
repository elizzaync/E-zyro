# HU-20 — Mantenimiento Guiado

## Cómo correr el feature

```bash
# Instalar dependencias
flutter pub get

# Ejecutar la app
flutter run

# Correr todos los tests del feature
flutter test test/mantenimiento/
```

## Flujo de navegación

```
Tab Operaciones
  └─ Lista de proyectos
       └─ ServiciosScreen (proyecto)
            └─ Tab "Equipos"  ← EquiposTab
                 └─ ChecklistScreen (equipo)
                      └─ CameraEvidenciaScreen (paso, tipo)
```

## Permisos requeridos

### Android — `android/app/src/main/AndroidManifest.xml`

```xml
<!-- Cámara -->
<uses-permission android:name="android.permission.CAMERA" />

<!-- Geolocalización -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- Almacenamiento (Android < 13) -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28" />
```

Dentro de `<activity ...>` asegúrate de tener:
```xml
android:hardwareAccelerated="true"
```

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSCameraUsageDescription</key>
<string>Se necesita acceso a la cámara para capturar evidencias de mantenimiento.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Se necesita la ubicación para registrar dónde se tomaron las evidencias.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Se necesita la ubicación para registrar dónde se tomaron las evidencias.</string>
```

## Sincronización offline

Las evidencias se encolan localmente en `SharedPreferences` cuando no hay
conexión. Al recuperar la red, `SyncService.processQueue()` las sube
automáticamente. El técnico puede forzar la sincronización tocando el ícono
`cloud_upload` en el AppBar del checklist.

## Tests unitarios

| Archivo | Cubre |
|---|---|
| `test/mantenimiento/foto_maquina_test.dart` | Máquina de estados ANTES→DURANTE→DESPUÉS y serialización |
| `test/mantenimiento/bloqueo_secuencial_test.dart` | Lógica de bloqueo de pasos |
| `test/mantenimiento/mantenimiento_service_test.dart` | Endpoints HTTP con `MockClient` |
