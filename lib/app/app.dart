import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'localization/gen/app_localizations.dart';
import '../core/providers/providers.dart';
import '../features/settings/presentation/app_lock_gate.dart';
import 'router.dart';
import 'theme.dart';

class TimeGridApp extends ConsumerWidget {
  const TimeGridApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final languageCode = settingsAsync.value?.languageCode ?? 'ar';

    return MaterialApp.router(
      title: 'TimeGrid',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      locale: Locale(languageCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Direction follows the selected app language, independent of
        // the device locale (PRD §8 — RTL Arabic / LTR English).
        return Directionality(
          textDirection:
              languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          // Every route sits behind the lock, so enabling it covers the app.
          child: AppLockGate(child: child!),
        );
      },
    );
  }
}
