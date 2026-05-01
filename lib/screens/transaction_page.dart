import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'approval_page.dart';
import '../security/crypto_service.dart';

class TransactionPage extends StatefulWidget {
  final String qrData;

  const TransactionPage({super.key, required this.qrData});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  final LocalAuthentication auth = LocalAuthentication();
  Map<String, dynamic> transaction = {};
  bool isLoading = false;
  String? parseError;

  @override
  void initState() {
    super.initState();
    _parseQRData();
  }

  Map<String, dynamic> _normalizeTransaction(Map<String, dynamic> data) {
    return {
      ...data,
      "transaction_id":
          data["transaction_id"] ?? data["transactionId"] ?? data["id"],
      "qr_session_id":
          data["qr_session_id"] ?? data["qrSessionId"] ?? data["session_id"],
      "merchant_reference":
          data["merchant_reference"] ??
          data["merchantReference"] ??
          data["merchant"] ??
          data["merchant_name"],
      "currency": data["currency"],
      "amount": data["amount"],
    };
  }

  bool get _hasRequiredTransactionFields =>
      transaction["transaction_id"] != null &&
      transaction["qr_session_id"] != null;

  /// Parse QR code: tries encrypted JSON first, plain JSON second, else key/value pairs.
  void _parseQRData() async {
    final parsedTransaction = <String, dynamic>{};
    String? errorMessage;

    try {
      print("RAW QR DATA: ${widget.qrData}");
      final decodedQR = jsonDecode(widget.qrData);

      if (decodedQR is! Map<String, dynamic>) {
        throw const FormatException("QR JSON is not an object");
      }

      final hasEncryptedPayload =
          decodedQR["encAES"] != null &&
          decodedQR["initial_vector"] != null &&
          decodedQR["cipher"] != null;

      if (hasEncryptedPayload) {
        // decode base64 (require update from qr_session)
        final encAESKey = base64Decode(decodedQR["encAES"]);
        final iv = base64Decode(decodedQR["initial_vector"]);
        final ciphertext = base64Decode(decodedQR["cipher"]);

        // access private key
        final prefs = await SharedPreferences.getInstance();
        final accountId = prefs.getString('lastUser');
        if (accountId == null) throw Exception("No logged in user");

        final privateKey = await CryptoService.getPrivateKey(
          accountId: accountId,
        );
        if (privateKey == null) throw Exception("Lost Private key");

        // decrypt AES key with RSA private
        final rawAESKey = CryptoService.decryptAESKeyWithRSA(
          privateKey,
          encAESKey,
        );

        // decrypt ciphertext with AES key => get transaction plain text
        final plaintext = CryptoService.decryptPayloadWithAES(
          rawAESKey,
          iv,
          ciphertext,
        );
        print("DECRYPTED QR PLAINTEXT: $plaintext");

        final decryptedTransaction = jsonDecode(plaintext);
        if (decryptedTransaction is! Map<String, dynamic>) {
          throw Exception("Invalid decrypted transaction");
        }
        parsedTransaction.addAll(_normalizeTransaction(decryptedTransaction));
      } else {
        parsedTransaction.addAll(_normalizeTransaction(decodedQR));
      }

      print("PARSED JSON TRANSACTION: $parsedTransaction");
    } on FormatException {
      final pairs = widget.qrData.split(",");
      for (var pair in pairs) {
        final kv = pair.split(":");
        if (kv.length >= 2) {
          final key = kv[0].trim();
          final value = kv.sublist(1).join(":").trim();
          parsedTransaction[key] = value;
        }
      }
      parsedTransaction.addAll(_normalizeTransaction(parsedTransaction));
      print("PARSED TEXT TRANSACTION: $parsedTransaction");
    } catch (e) {
      errorMessage = e.toString();
      print("QR PARSE/DECRYPT ERROR: $e");
    }

    if (mounted) {
      setState(() {
        transaction = parsedTransaction;
        parseError = errorMessage;
      });
    } else {
      transaction = parsedTransaction;
      parseError = errorMessage;
    }
    print("PARSED TRANSACTION: $transaction");
  }

  /// Send approval/rejection request to backend
  Future<void> _sendDecision({
    required String action,
    required String signature,
    required String hash,
  }) async {
    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      if (token.isEmpty) {
        throw Exception('No token found. Please log in first.');
      }

      final Map<String, dynamic> requestBody = {
        "transaction_id": transaction["transaction_id"],
        "qr_session_id": transaction["qr_session_id"],
        "action": action,
        "signature": signature,
        "hash": hash,
      };

      print("DECISION REQUEST: ${jsonEncode(requestBody)}");

      final response = await http.post(
        Uri.parse(
          "https://nurturing-renewal-production.up.railway.app/api/payments/decision/",
        ),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode(requestBody),
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
  Future<void> _authenticateAndSend(String action, String plaintext) async {
    try {
      bool authenticated = await auth.authenticate(
        localizedReason: "Confirm transaction",
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );

      if (!mounted) return;

      if (authenticated) {
        if (!_hasRequiredTransactionFields) {
          throw Exception("Transaction data is incomplete");
        }

        // access private key
        final prefs = await SharedPreferences.getInstance();
        final accountId = prefs.getString('lastUser');
        if (accountId == null) return;

        final privateKey = await CryptoService.getPrivateKey(
          accountId: accountId,
        );
        if (privateKey == null) return;

        // sign content: transaction_id + decision
        String signContent = "${transaction["transaction_id"]}|$action";

        // generate hash and signature
        final signature = CryptoService.signData(privateKey, signContent);
        final hashDigest = CryptoService.getHash(signContent);

        // send decision, sign, hash back to server
        await _sendDecision(
          action: action,
          signature: signature,
          hash: hashDigest,
        );
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
                    if (parseError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        "QR Error: $parseError",
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
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
              onPressed: isLoading || !_hasRequiredTransactionFields
                  ? null
                  : () => _authenticateAndSend(
                      "APPROVE",
                      transaction["transaction_id"].toString(),
                    ),
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
              onPressed: isLoading || !_hasRequiredTransactionFields
                  ? null
                  : () => _authenticateAndSend(
                      "REJECT",
                      transaction["transaction_id"].toString(),
                    ),
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
