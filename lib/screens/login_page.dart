import 'package:flutter/material.dart';
import 'qr_scanner_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

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
    _checkLoginStatus();
  }

  /// Check if user previously logged in and opted for biometrics
  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    bool loggedIn = prefs.getBool("loggedIn") ?? false;
    bool biometricEnabled = prefs.getBool("biometricEnabled") ?? false;

    // Only auto-trigger biometrics if both conditions are true
    if (loggedIn && biometricEnabled) {
      _biometricLogin();
    }
  }

  /// Main login with email/password
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);

    await Future.delayed(const Duration(seconds: 2)); // simulate server delay

    String email = emailController.text;
    String password = passwordController.text;

    setState(() => loading = false);

    if (email == "user@test.com" && password == "123456") {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("loggedIn", true);

      // Ask user if they want to enable biometric login
      await _askEnableBiometric();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const QRScannerPage()),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Invalid credentials")));
    }
  }

  /// Ask the user if they want to enable biometric login
  Future<void> _askEnableBiometric() async {
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("biometricEnabled", true);
    }
  }

  /// Only allow biometric login if user has previously logged in
  Future<void> _handleBiometricLogin() async {
    final prefs = await SharedPreferences.getInstance();
    bool loggedIn = prefs.getBool("loggedIn") ?? false;
    bool biometricEnabled = prefs.getBool("biometricEnabled") ?? false;

    if (!loggedIn || !biometricEnabled) {
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

  /// Biometric login
  Future<void> _biometricLogin() async {
    try {
      bool authenticated = await auth.authenticate(
        localizedReason: "Login using biometrics",
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Biometric authentication not available")),
      );
    }
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
                      // Biometric login now gated
                      ElevatedButton.icon(
                        icon: const Icon(Icons.fingerprint),
                        label: const Text("Login with Biometrics"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                        onPressed: _handleBiometricLogin,
                      ),
                      const SizedBox(height: 15),
                      TextButton(
                        onPressed: () {},
                        child: const Text("Forgot password?"),
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
