import 'package:flutter/material.dart';
import 'package:vivordo_health/firebase_options.dart';
import 'package:vivordo_health/src/pages/log_in_demo.dart' show LoginDemo;
import 'package:vivordo_health/src/pages/stress_spike_test_page.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vivordo Health',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,

      // Option A: keep login as home
      home: const LoginDemo(),

      // Add a route to the test page so you can navigate to it easily
      routes: {
        '/stress-test': (context) => const StressSpikeTestPage(),
      },
    );
  }
}
