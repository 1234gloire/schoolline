import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';

const _biometricLockEnabledKey = 'biometric_lock_enabled';

class BiometricLockState {
  const BiometricLockState({
    this.enabled = false,
    this.supported = false,
    this.locked = false,
    this.checking = true,
    this.authenticating = false,
    this.errorMessage,
  });

  final bool enabled;
  final bool supported;
  final bool locked;
  final bool checking;
  final bool authenticating;
  final String? errorMessage;

  BiometricLockState copyWith({
    bool? enabled,
    bool? supported,
    bool? locked,
    bool? checking,
    bool? authenticating,
    String? errorMessage,
    bool clearError = false,
  }) {
    return BiometricLockState(
      enabled: enabled ?? this.enabled,
      supported: supported ?? this.supported,
      locked: locked ?? this.locked,
      checking: checking ?? this.checking,
      authenticating: authenticating ?? this.authenticating,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final biometricLockProvider =
    StateNotifierProvider<BiometricLockNotifier, BiometricLockState>((ref) {
      return BiometricLockNotifier()..initialize();
    });

class BiometricLockNotifier extends StateNotifier<BiometricLockState> {
  BiometricLockNotifier() : super(const BiometricLockState());

  final LocalAuthentication _auth = LocalAuthentication();

  Box<dynamic> get _settings => Hive.box<dynamic>('settings');

  Future<void> initialize() async {
    final enabled = _settings.get(_biometricLockEnabledKey) == true;
    final supported = await _isSupported();
    state = state.copyWith(
      enabled: enabled && supported,
      supported: supported,
      locked: enabled && supported,
      checking: false,
      clearError: true,
    );
    if (enabled && !supported) {
      await _settings.put(_biometricLockEnabledKey, false);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final supported = await _isSupported();
    if (enabled && !supported) {
      state = state.copyWith(
        supported: false,
        checking: false,
        errorMessage:
            'Aucune biométrie disponible. Configure Face ID ou empreinte dans les réglages du téléphone.',
      );
      return;
    }

    if (enabled) {
      final unlocked = await authenticate();
      if (!unlocked) return;
    }

    await _settings.put(_biometricLockEnabledKey, enabled);
    state = state.copyWith(
      enabled: enabled,
      supported: supported,
      locked: false,
      checking: false,
      clearError: true,
    );
  }

  void lock() {
    if (!state.enabled || !state.supported || state.authenticating) return;
    state = state.copyWith(locked: true, clearError: true);
  }

  Future<bool> authenticate() async {
    if (state.authenticating) return false;

    state = state.copyWith(authenticating: true, clearError: true);
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Déverrouille DiakExam pour accéder à ton compte.',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      state = state.copyWith(
        locked: !ok,
        authenticating: false,
        clearError: ok,
        errorMessage: ok ? null : 'Déverrouillage annulé.',
      );
      return ok;
    } catch (_) {
      state = state.copyWith(
        locked: true,
        authenticating: false,
        errorMessage:
            'Déverrouillage impossible. Vérifie Face ID ou empreinte sur ton téléphone.',
      );
      return false;
    }
  }

  Future<bool> _isSupported() async {
    try {
      final deviceSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return deviceSupported && canCheck;
    } catch (_) {
      return false;
    }
  }
}
