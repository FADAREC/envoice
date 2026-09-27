import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App lock protects against casual device access (borrowed phone, staff,
/// someone opening the app from the recents screen).
///
/// This is NOT full disk encryption. A determined attacker with the unlocked
/// device and forensic tools can still extract the SQLite file. For V1 the
/// goal is: random access without the PIN/biometric cannot open invoices.
class AppLock {
  static const _pinHashKey = 'envoice_pin_hash';
  static const _lockEnabledKey = 'envoice_lock_enabled';
  static const _biometricKey = 'envoice_biometric_enabled';

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_lockEnabledKey) ?? false;
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode('envoice-v1|$pin');
    return sha256.convert(bytes).toString();
  }

  Future<void> enableLock(String pin, {bool biometric = false}) async {
    if (pin.length < 4) {
      throw ArgumentError('PIN must be at least 4 digits');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinHashKey, _hashPin(pin));
    await prefs.setBool(_lockEnabledKey, true);
    await prefs.setBool(_biometricKey, biometric);
  }

  Future<void> disableLock(String pin) async {
    if (!await verifyPin(pin)) {
      throw StateError('Wrong PIN');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinHashKey);
    await prefs.setBool(_lockEnabledKey, false);
    await prefs.setBool(_biometricKey, false);
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_pinHashKey);
    if (stored == null) return false;
    return stored == _hashPin(pin);
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Envoice',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  Future<void> setBiometric(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, enabled);
  }
}
