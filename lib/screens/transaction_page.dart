import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
  bool isLoading = false;

  @override
  void initState() {
    super.initState();

    try {
      transaction = jsonDecode(widget.qrData);
    } catch (e) {
      transaction = {"raw_data": widget.qrData};
    }
  }

  // 🔐 AUTH + APPROVE FLOW
  Future<void> authenticateAndApprove() async {
    bool authenticated = await auth.authenticate(
      localizedReason: "Confirm transaction",
      biometricOnly: false,
      sensitiveTransaction: true,
      persistAcrossBackgrounding: true,
    );

    if (!mounted) return;

    if (authenticated) {
      await _sendDecision("APPROVE");
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Authentication Failed")));
    }
  }

  // ❌ REJECT FLOW (no biometric)
  Future<void> rejectTransaction() async {
    await _sendDecision("REJECT");
  }

  // 🌐 API CALL
  Future<void> _sendDecision(String action) async {
    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse(
          "https://nurturing-renewal-production.up.railway.app/api/payments/decision",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "transaction_id": transaction["transaction_id"],
          "qr_session_id": transaction["qr_session_id"],
          "action": action,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ApprovalPage(transaction: data),
          ),
        );
      } else {
        throw Exception(data["message"] ?? "Request failed");
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
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

            // 💳 MAIN CARD
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      transaction["merchant_reference"] ?? "Unknown Merchant",
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

            // 📋 DETAILS
            TransactionField("QR Session Id", transaction["qr_session_id"]),
            TransactionField(
              "Sender Account Id",
              transaction["sender_account_id"],
            ),
            TransactionField("Date", transaction["created_at"]),

            const Spacer(),

            // 🔄 LOADING INDICATOR
            if (isLoading) const Center(child: CircularProgressIndicator()),

            if (!isLoading) ...[
              // ✅ APPROVE BUTTON
              ElevatedButton.icon(
                icon: const Icon(Icons.fingerprint),
                label: const Text("Authenticate & Pay"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                onPressed: authenticateAndApprove,
              ),

              const SizedBox(height: 10),

              // ❌ REJECT BUTTON
              ElevatedButton(
                onPressed: rejectTransaction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.all(16),
                ),
                child: const Text("Reject"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
