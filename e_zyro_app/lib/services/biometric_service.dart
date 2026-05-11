import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static final _auth = LocalAuthentication();

  static const _keyEnabled = 'biometric_enabled';
  static const _keyPolicyAccepted = 'biometric_policy_accepted';

  final SharedPreferences _prefs;
  BiometricService(this._prefs);

  // ── Device capability ─────────────────────────────────────────────────────

  Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  // ── User preferences ──────────────────────────────────────────────────────

  bool get isEnabled => _prefs.getBool(_keyEnabled) ?? false;
  bool get policyAccepted => _prefs.getBool(_keyPolicyAccepted) ?? false;

  Future<void> enable() async {
    await _prefs.setBool(_keyPolicyAccepted, true);
    await _prefs.setBool(_keyEnabled, true);
  }

  Future<void> disable() async {
    await _prefs.remove(_keyEnabled);
    await _prefs.remove(_keyPolicyAccepted);
  }

  // ── Authentication ────────────────────────────────────────────────────────

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason:
            'Usa tu huella digital para acceder a E-System TIC',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
