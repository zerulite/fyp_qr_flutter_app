import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:secure_pay/screens/main_page.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'register_page.dart';
import '../security/crypto_service.dart';

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

  // Secure storage only
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  bool obscurePassword = true;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricLogin();
  }

  Future<void> _checkBiometricLogin() async {
    bool biometricEnabled =
        await secureStorage.read(key: 'biometricEnabled') == 'true';

    bool loggedIn = await secureStorage.read(key: 'loggedIn') == 'true';

    if (biometricEnabled && loggedIn) {
      await _biometricLogin();
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);

    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      final response = await http.post(
        Uri.parse('https://fyp-bank-backend.onrender.com/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"email": email, "password": password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final token = data['access_token'] ?? data['token'];

        if (token == null || token.isEmpty) {
          throw Exception("No token returned from backend");
        }

        // Store everything securely
        await secureStorage.write(key: 'loggedIn', value: 'true');

        await secureStorage.write(key: 'token', value: token);

        await secureStorage.write(key: 'email', value: email);

        await secureStorage.write(key: 'lastUser', value: email);

        await secureStorage.write(key: 'password', value: password);

        final keyReady = await _ensurePrivateKeyAfterLogin(
          email: email,
          token: token,
        );
        if (!keyReady) {
          await _clearIncompleteLogin();
          return;
        }

        await _askEnableBiometric();

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainPage()),
        );
      } else {
        final error = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error['message'] ?? 'Login failed')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Unexpected error: $e")));
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _askEnableBiometric() async {
    bool alreadyEnabled =
        await secureStorage.read(key: 'biometricEnabled') == 'true';

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
      await secureStorage.write(key: 'biometricEnabled', value: 'true');
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

      if (!authenticated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Biometric authentication failed")),
        );
        return;
      }

      // Read stored credentials
      final email = await secureStorage.read(key: 'email');
      final password = await secureStorage.read(key: 'password');

      if (email == null ||
          email.isEmpty ||
          password == null ||
          password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No saved credentials found")),
        );
        return;
      }

      setState(() => loading = true);

      // Call login API again
      final response = await http.post(
        Uri.parse('https://fyp-bank-backend.onrender.com/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"email": email, "password": password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final token = data['access_token'] ?? data['token'];

        if (token == null || token.isEmpty) {
          throw Exception("No token returned");
        }

        // Save refreshed token
        await secureStorage.write(key: 'token', value: token);

        await secureStorage.write(key: 'lastUser', value: email);

        await secureStorage.write(key: 'loggedIn', value: 'true');

        final keyReady = await _ensurePrivateKeyAfterLogin(
          email: email,
          token: token,
        );
        if (!keyReady) {
          await _clearIncompleteLogin();
          return;
        }

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainPage()),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Login failed")));
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Biometric authentication error")),
      );
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    bool biometricEnabled =
        await secureStorage.read(key: 'biometricEnabled') == 'true';

    if (!biometricEnabled) {
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

  Future<String?> _promptForTransactionPinForRebind() async {
    final formKey = GlobalKey<FormState>();
    var transactionPin = "";
    var obscurePin = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Device Rebind Required"),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "This device is missing its private key. Enter your transaction PIN to rebind this device.",
                ),
                const SizedBox(height: 16),
                TextFormField(
                  autofocus: true,
                  obscureText: obscurePin,
                  keyboardType: TextInputType.number,
                  onChanged: (value) => transactionPin = value.trim(),
                  decoration: InputDecoration(
                    labelText: "Transaction PIN",
                    prefixIcon: const Icon(Icons.pin),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePin ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setDialogState(() => obscurePin = !obscurePin);
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final pin = value?.trim() ?? "";
                    if (pin.isEmpty) return "Enter transaction PIN";
                    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
                      return "Transaction PIN must be 4 to 6 digits";
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, transactionPin);
                }
              },
              child: const Text("Rebind"),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _ensurePrivateKeyAfterLogin({
    required String email,
    required String token,
  }) async {
    final existingPrivateKey = await CryptoService.getPrivateKey(
      accountId: email,
    );
    if (existingPrivateKey != null) {
      final canDecryptCards = await _canDecryptCurrentCardCvv(
        email: email,
        token: token,
      );
      if (canDecryptCards) return true;
    }

    if (!mounted) return false;

    final transactionPin = await _promptForTransactionPinForRebind();
    if (transactionPin == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Device rebind is required to login.")),
        );
      }
      return false;
    }

    final keyPair = CryptoService.generateRSAKeyPair();
    final publicKeyPem = CryptoService.formatPublicKey(keyPair.publicKey);

    final response = await http.post(
      Uri.parse('https://fyp-bank-backend.onrender.com/api/account/public-key'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'public_key': publicKeyPem,
        'transaction_pin': transactionPin,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      await CryptoService.savePrivateKey(keyPair.privateKey, accountId: email);
      if (mounted) {
        final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
        final message = data['message'] ?? "Device rebound successfully.";
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      return true;
    }

    if (mounted) {
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      final message =
          data['message'] ?? data['error'] ?? "Device rebind failed.";
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    return false;
  }

  Future<bool> _canDecryptCurrentCardCvv({
    required String email,
    required String token,
  }) async {
    final privateKey = await CryptoService.getPrivateKey(accountId: email);
    if (privateKey == null) return false;

    try {
      final response = await http.get(
        Uri.parse('https://fyp-bank-backend.onrender.com/api/account/cards'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) return true;

      final decoded = jsonDecode(response.body);
      final cards = (decoded['cards'] as List?) ?? [];
      if (cards.isEmpty) return true;

      String? encryptedCvv;
      for (final card in cards) {
        if (card is Map) {
          final value = card['cvv_encrypted']?.toString();
          if (value != null && value.isNotEmpty) {
            encryptedCvv = value;
            break;
          }
        }
      }

      if (encryptedCvv == null) return true;

      final cvv = CryptoService.decryptStringWithRSAOAEP(
        privateKey,
        base64Decode(encryptedCvv),
      );

      return RegExp(r'^\d{3}$').hasMatch(cvv);
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearIncompleteLogin() async {
    await secureStorage.write(key: 'loggedIn', value: 'false');
    await secureStorage.delete(key: 'token');
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
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                        onPressed: loading ? null : _handleBiometricLogin,
                      ),

                      const SizedBox(height: 15),

                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RegisterPage(),
                            ),
                          );
                        },
                        child: const Text("Don't have an account? Register"),
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
