import 'package:flutter/material.dart';
import 'package:vivordo_health/firebase_options.dart';
import 'package:vivordo_health/src/pages/log_in_demo.dart' show LoginDemo;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'screens/login.dart';
import 'screens/dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final model = FirebaseAI.googleAI().generativeModel(
    model: 'gemini-2.5-flash',
  );

  // Provide a prompt that contains text
  final prompt = [Content.text('Write a story about a magic backpack.')];

  // To generate text output, call generateContent with the text input
  final response = await model.generateContent(prompt);
  print(response.text);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vivordo Health',
      theme: ThemeData(primarySwatch: Colors.purple),
      initialRoute: '/',
      routes: {
        '/': (context) => LoginScreen(),
        '/dashboard': (context) => DashboardScreen(),
      },
    );
  }
}
