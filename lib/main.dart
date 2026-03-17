import 'package:flutter/material.dart';
import 'screens/login_page.dart';
//import 'package:supabase_flutter/supabase_flutter.dart';

// Future<void> main() async {
//   await Supabase.initialize(
//     url: 'https://cgzjabtprjbcoqyquvbm.supabase.co',
//     anonKey: 'sb_publishable_6kNPlQLDw-vvvoENUercoQ_NNneVPs8',
//   );
//   runApp(MyApp());
// }

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginPage(),
    );
  }
}
