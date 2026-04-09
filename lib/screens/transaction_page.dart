import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
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
    _parseQRData();
  }

  /// Parse QR code: tries JSON first, else parses key: value pairs
  void _parseQRData() {
    transaction = {};
    try {
      transaction = jsonDecode(widget.qrData);
      print(transaction);
    } catch (e) {
      final pairs = widget.qrData.split(",");
      for (var pair in pairs) {
        final kv = pair.split(":");
        if (kv.length >= 2) {
          final key = kv[0].trim();
          final value = kv.sublist(1).join(":").trim();
          transaction[key] = value;
        }
      }
    }
    print("PARSED TRANSACTION: $transaction");
  }

  /// Send approval/rejection request to backend
  Future<void> _sendDecision(String action) async {
    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      if (token.isEmpty) {
        throw Exception('No token found. Please log in first.');
      }

      final response = await http.post(
        Uri.parse(
          "https://nurturing-renewal-production.up.railway.app/api/payments/decision/",
        ),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "transaction_id": transaction["transaction_id"],
          "qr_session_id": transaction["qr_session_id"],
          "action": action,
        }),
      );

      print("STATUS: ${response.statusCode}");
      print("BODY: ${response.body}");
      print("TOKEN: $token");

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (!mounted) return;

      if (response.statusCode == 200) {
        // Navigate to ApprovalPage with backend response
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ApprovalPage(transaction: data)),
        );
      } else {
        throw Exception(data["message"] ?? "Request failed");
      }
    } catch (e) {
      print("ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Authenticate user via biometrics before sending decision
  Future<void> _authenticateAndSend(String action) async {
    try {
      bool authenticated = await auth.authenticate(
        localizedReason: "Confirm transaction",
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );

      if (!mounted) return;

      if (authenticated) {
        await _sendDecision(action);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Authentication failed")));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Authentication error: $e")));
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
            const SizedBox(height: 20),
            const Text(
              "Payment Confirmation",
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Transaction Card
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const SizedBox(height: 10),
                    Text(
                      "QR Session ID: ${transaction["qr_session_id"] ?? ""}",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Approve Button
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text("Approve Payment"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              onPressed: isLoading
                  ? null
                  : () => _authenticateAndSend("APPROVE"),
            ),

            const SizedBox(height: 10),

            // Reject Button
            ElevatedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text("Reject Payment"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.all(16),
              ),
              onPressed: isLoading
                  ? null
                  : () => _authenticateAndSend("REJECT"),
            ),

            if (isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
