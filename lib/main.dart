import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/db/database_provider.dart';
import 'core/security/app_lock.dart';
import 'features/shell/app_shell.dart';
import 'features/security/lock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    const ProviderScope(
      child: EnvoiceApp(),
    ),
  );
}

class EnvoiceApp extends ConsumerStatefulWidget {
  const EnvoiceApp({super.key});

  @override
  ConsumerState<EnvoiceApp> createState() => _EnvoiceAppState();
}

class _EnvoiceAppState extends ConsumerState<EnvoiceApp>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _locked = false;
  bool _unlockedThisSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock when app goes to background if lock is enabled.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Mark for re-lock on resume without flashing lock during transitions.
    }
    if (state == AppLifecycleState.resumed) {
      _onResume();
    }
    if (state == AppLifecycleState.paused) {
      _unlockedThisSession = false;
    }
  }

  Future<void> _onResume() async {
    final enabled = await AppLock().isLockEnabled();
    if (!enabled) return;
    if (!_unlockedThisSession && mounted) {
      setState(() => _locked = true);
    }
  }

  Future<void> _checkLock() async {
    final enabled = await AppLock().isLockEnabled();
    if (!mounted) return;
    setState(() {
      _locked = enabled;
      _checking = false;
      if (!enabled) _unlockedThisSession = true;
    });
  }

  void _onUnlocked() {
    setState(() {
      _locked = false;
      _unlockedThisSession = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(databaseProvider);

    return MaterialApp(
      title: 'Envoice',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _checking
          ? const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.black,
                  ),
                ),
              ),
            )
          : _locked
              ? LockScreen(onUnlocked: _onUnlocked)
              : const AppShell(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(0.9, 1.15),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
