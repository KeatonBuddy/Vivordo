import 'package:flutter/material.dart';
import 'package:vivordo_health/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:vivordo_health/src/services/notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home_screen.dart';

// Global navigator key for notification navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Initialize notification service
  await NotificationService().initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Vivordo Health',
      debugShowCheckedModeBanner: false,
      // Global Theme Definition
      theme: ThemeData(
        primaryColor: const Color(0xFF857DEA),
        scaffoldBackgroundColor: const Color(0xFFFBFaff),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xFF857DEA),
          secondary: const Color(0xFF857DEA),
        ),
        useMaterial3: true,
      ),
      // Route Definitions
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}
