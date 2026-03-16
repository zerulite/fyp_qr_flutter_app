import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:convert';
import '../widgets/transaction_field.dart';
import 'approval_page.dart';

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
      biometricOnly: false, // allow PIN/passcode as fallback
      sensitiveTransaction: true, // platform-specific security
      persistAcrossBackgrounding: true, // retry if app goes to background
    );

    if (!mounted) return;

    if (authenticated) {
      // Navigate to ApprovalPage
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ApprovalPage(transaction: transaction),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Authentication Failed")));
    }
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

            TransactionField("Encrypted Key", transaction["encrypted_key"]),
            TransactionField("IV", transaction["iv"]),
            TransactionField("Ciphertext", transaction["ciphertext"]),
            TransactionField("Auth Tag", transaction["auth_tag"]),

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
