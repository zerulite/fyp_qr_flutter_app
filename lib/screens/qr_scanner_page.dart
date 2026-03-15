import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'transaction_page.dart';
import 'login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  bool scanned = false;

  /// Show confirmation dialog before logging out
  Future<void> _confirmLogout() async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Logout Confirmation"),
            content: const Text(
              "Are you sure you want to logout? You will need to login again.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "Logout",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      _logout();
    }
  }

  /// Logout function clears login state
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("loggedIn");
    await prefs.remove("biometricEnabled");

    // Navigate back to LoginPage and remove all previous routes
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan QR Code"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (scanned) return;

          final barcode = capture.barcodes.first;
          final String? code = barcode.rawValue;

          if (code != null) {
            scanned = true;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TransactionPage(qrData: code),
              ),
            ).then((_) {
              scanned = false;
            });
          }
        },
      ),
    );
  }
}
