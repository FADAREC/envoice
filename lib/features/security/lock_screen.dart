import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/app_lock.dart';
import '../../core/theme/app_theme.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _lock = AppLock();
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final canBio = await _lock.canCheckBiometrics();
    final bioOn = await _lock.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = canBio;
      _biometricEnabled = bioOn;
    });
    if (canBio && bioOn) {
      await _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    setState(() => _busy = true);
    final ok = await _lock.authenticateBiometric();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      HapticFeedback.mediumImpact();
      widget.onUnlocked();
    }
  }

  Future<void> _submitPin() async {
    final pin = _pin.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'Enter your PIN');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await _lock.verifyPin(pin);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      HapticFeedback.mediumImpact();
      widget.onUnlocked();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = 'Wrong PIN';
        _pin.clear();
      });
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Text(
                'Envoice',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter PIN to unlock',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.secondary,
                    ),
              ),
              const SizedBox(height: 36),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                autofocus: true,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      letterSpacing: 8,
                    ),
                decoration: InputDecoration(
                  counterText: '',
                  errorText: _error,
                  hintText: '••••',
                ),
                onSubmitted: (_) => _submitPin(),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _busy ? null : _submitPin,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Unlock'),
              ),
              if (_biometricAvailable && _biometricEnabled) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _busy ? null : _tryBiometric,
                  icon: const Icon(Icons.fingerprint, size: 20),
                  label: const Text('Use fingerprint / face'),
                ),
              ],
              const Spacer(flex: 3),
              Text(
                'Your invoices stay on this device. Unlock is required each time you open the app when lock is on.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.tertiary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
