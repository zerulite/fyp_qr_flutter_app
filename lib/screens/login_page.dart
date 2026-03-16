import 'package:flutter/material.dart';
import 'qr_scanner_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'register_page.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final LocalAuthentication auth = LocalAuthentication();

  bool obscurePassword = true;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricLogin();
  }

  Future<void> _checkBiometricLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final supabase = Supabase.instance.client;

    bool biometricEnabled = prefs.getBool("biometricEnabled") ?? false;
    bool hasLoggedInBefore = prefs.getBool("hasLoggedInBefore") ?? false;
    String? lastUser = prefs.getString("lastUser");

    final session = supabase.auth.currentSession;

    if (session != null &&
        biometricEnabled &&
        hasLoggedInBefore &&
        lastUser != null) {
      if (!mounted) return;
      await _biometricLogin();
    }
  }

  Future<void> _login() async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (response.user != null) {
        //final token = response.session?.accessToken;

        final apiResponse = await http.post(
          Uri.parse(
            'https://nurturing-renewal-production.up.railway.app/api/auth/login',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': emailController.text.trim(),
            'password': passwordController.text.trim(),
          }),
        );

        if (apiResponse.statusCode == 200) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('loggedIn', true);
          await prefs.setString('lastUser', emailController.text.trim());

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const QRScannerPage()),
          );
        } else {
          final error = jsonDecode(apiResponse.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error['message'] ?? 'API login failed')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Unexpected error: $e")));
    }
  }

  Future<void> _askEnableBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    bool alreadyEnabled = prefs.getBool("biometricEnabled") ?? false;

    if (alreadyEnabled) return;

    bool enable =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Enable Biometric Login?"),
            content: const Text(
              "You can log in next time using fingerprint or face ID.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("No"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Yes"),
              ),
            ],
          ),
        ) ??
        false;

    if (enable) {
      await prefs.setBool("biometricEnabled", true);
    }
  }

  Future<void> _biometricLogin() async {
    try {
      bool authenticated = await auth.authenticate(
        localizedReason: "Login using biometrics",
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );

      if (!mounted) return;

      if (authenticated) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const QRScannerPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Biometric authentication failed")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Biometric authentication not available")),
      );
    }
  }

  Future<void> _handleBiometricLogin() async {
    final prefs = await SharedPreferences.getInstance();
    bool biometricEnabled = prefs.getBool("biometricEnabled") ?? false;
    String? lastUser = prefs.getString("lastUser");

    if (!biometricEnabled || lastUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You must log in with email/password first to use biometrics",
          ),
        ),
      );
      return;
    }

    await _biometricLogin();
  }

  Future<void> _debugReset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("App reset. Cache cleared.")));

    emailController.clear();
    passwordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.account_balance_wallet,
                        size: 60,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Secure Pay",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 30),
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Enter your email";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: "Password",
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Enter your password";
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 30),

                      SizedBox(
                        width: double.infinity,

                        child: ElevatedButton(
                          onPressed: loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                          ),

                          child: loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text("Login"),
                        ),
                      ),

                      const SizedBox(height: 15),

                      ElevatedButton.icon(
                        icon: const Icon(Icons.fingerprint),
                        label: const Text("Login with Biometrics"),
                        onPressed: _handleBiometricLogin,
                      ),

                      const SizedBox(height: 10),

                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterPage(),
                            ),
                          );
                        },
                        child: const Text("Create Account"),
                      ),

                      const SizedBox(height: 10),

                      ElevatedButton(
                        onPressed: _debugReset,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text(
                          "Debug Reset App",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
