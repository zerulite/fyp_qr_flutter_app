import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: QRScannerPage(),
    );
  }
}

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  bool scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan QR Code")),

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

class TransactionPage extends StatefulWidget {
  final String qrData;

  const TransactionPage({super.key, required this.qrData});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  final LocalAuthentication auth = LocalAuthentication();

  late Map<String, dynamic> transaction;

  @override
  void initState() {
    super.initState();

    try {
      transaction = jsonDecode(widget.qrData);
    } catch (e) {
      transaction = {"raw_data": widget.qrData};
    }
  }

  Future<void> authenticate() async {
    bool authenticated = await auth.authenticate(
      localizedReason: "Confirm transaction",
      options: const AuthenticationOptions(
        biometricOnly: false,
        stickyAuth: true,
      ),
    );

    if (authenticated) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Payment Approved")));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Authentication Failed")));
      }
    }
  }

  Widget transactionField(String title, dynamic value) {
    if (value == null) return const SizedBox();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 6),

            SelectableText(
              value.toString(),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Confirm Payment")),

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Payment Confirmation",
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 30),

            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),

                child: Column(
                  children: [
                    Text(
                      transaction["merchant"] ?? "Unknown Merchant",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      "${transaction["currency"] ?? ""} ${transaction["amount"] ?? ""}",
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      "Transaction ID: ${transaction["transaction_id"] ?? ""}",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              "Encrypted Transaction Data",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            transactionField("Encrypted Key", transaction["encrypted_key"]),
            transactionField("IV", transaction["iv"]),
            transactionField("Ciphertext", transaction["ciphertext"]),
            transactionField("Auth Tag", transaction["auth_tag"]),

            const Spacer(),

            ElevatedButton.icon(
              icon: const Icon(Icons.fingerprint),
              label: const Text("Authenticate & Pay"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              onPressed: authenticate,
            ),
          ],
        ),
      ),
    );
  }
}
