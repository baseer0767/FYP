import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // ✅ ADD THIS
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // ✅ REQUIRED
  MediaKit.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ntfgzmuzwaklxcapiydi.supabase.co', // ✅ YOUR URL
    anonKey: 'sb_publishable_4Ir_1KDJhoN2PkCV6kI7vQ_5HNSvvtb', // ✅ YOUR KEY
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FitPose',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomeScreen(), // ✅ KEEP THIS
    );
  }
}