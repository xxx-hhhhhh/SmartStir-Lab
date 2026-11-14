import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/app_preferences.dart';
import 'screens/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPrefs.init();
  runApp(const SmartStirApp());
}

class SmartStirApp extends StatelessWidget {
  const SmartStirApp({super.key});

  static const navy = Color(0xFF1B365D);
  static const brass = Color(0xFFC5A059);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: navy,
      primary: navy,
      secondary: brass,
      surface: Colors.white,
    );
    return ValueListenableBuilder<String>(
      valueListenable: AppPrefs.language,
      builder: (context, lang, _) => MaterialApp(
      title: L.t('app'),
      locale: Locale(lang),
      supportedLocales: const [Locale('zh'),Locale('en'),Locale('ja')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: scheme,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      home: const LoginPage(),
    ));
  }
}
