import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'transaction_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  bool scanned = false;

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("loggedIn");

    // Return to login page and remove all previous routes
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
            onPressed: logout,
          ),
        ],
      ),
      body: MobileScanner(
        onDetect: (BarcodeCapture capture) {
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
