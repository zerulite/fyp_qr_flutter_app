import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'approval_page.dart';
import '../security/crypto_service.dart';

Map<String, dynamic> normalizeTransactionData(Map<String, dynamic> data) {
  final transactionId =
      data["transaction_id"] ??
      data["transactionId"] ??
      data["transactionID"] ??
      data["id"];
  final qrSessionId =
      data["qr_session_id"] ??
      data["qrSessionId"] ??
      data["qrSessionID"] ??
      data["session_id"] ??
      data["sessionId"];
  final applicationId =
      data["application_id"] ??
      data["applicationId"] ??
      data["app_id"] ??
      data["appId"];
  final merchantReference =
      data["merchant_reference"] ??
      data["merchantReference"] ??
      data["merchant_name"] ??
      data["merchantName"] ??
      data["merchant"] ??
      data["merchant_id"] ??
      data["merchantId"] ??
      data["application_name"] ??
      data["applicationName"] ??
      data["app_name"] ??
      data["appName"];

  return {
    ...data,
    "id": transactionId,
    "transaction_id": transactionId,
    "transactionId": transactionId,
    "qr_session_id": qrSessionId,
    "qrSessionId": qrSessionId,
    "application_id": applicationId,
    "applicationId": applicationId,
    "merchant_reference": merchantReference,
    "currency":
        data["currency"] ?? data["currency_code"] ?? data["currencyCode"],
    "amount": data["amount"] ?? data["total_amount"] ?? data["totalAmount"],
    "sender_account_id": data["sender_account_id"] ?? data["senderAccountId"],
    "created_at": data["created_at"] ?? data["createdAt"],
  };
}

Map<String, dynamic> buildDecisionRequestBody({
  required Map<String, dynamic> transaction,
  required String action,
  required String signature,
  required String hash,
}) {
  return {
    "id": transaction["id"] ?? transaction["transaction_id"],
    "transaction_id": transaction["transaction_id"],
    "transactionId": transaction["transaction_id"],
    "qr_session_id": transaction["qr_session_id"],
    "qrSessionId": transaction["qr_session_id"],
    if (transaction["sender_account_id"] != null)
      "sender_account_id": transaction["sender_account_id"],
    if (transaction["amount"] != null) "amount": transaction["amount"],
    if (transaction["merchant_reference"] != null)
      "merchant_reference": transaction["merchant_reference"],
    if (transaction["created_at"] != null)
      "created_at": transaction["created_at"],
    if (transaction["application_id"] != null)
      "application_id": transaction["application_id"],
    if (transaction["application_id"] != null)
      "applicationId": transaction["application_id"],
    "action": action,
    "signature": signature,
    "hash": hash,
  };
}

String buildIntegrityPlaintext(Map<String, dynamic> transaction) {
  const requiredFields = [
    "id",
    "qr_session_id",
    "sender_account_id",
    "amount",
    "merchant_reference",
    "created_at",
  ];

  final missingFields = requiredFields
      .where((field) => transaction[field] == null)
      .toList();

  if (missingFields.isNotEmpty) {
    throw Exception("Missing transaction fields: ${missingFields.join(', ')}");
  }

  return jsonEncode({
    for (final field in requiredFields) field: transaction[field],
  });
}

Map<String, dynamic> buildDisplayTransactionData(Map<String, dynamic> data) {
  const visibleKeys = [
    "id",
    "qr_session_id",
    "sender_account_id",
    "amount",
    "merchant_reference",
    "created_at",
  ];

  return {
    for (final key in visibleKeys)
      if (data.containsKey(key)) key: data[key],
  };
}

class TransactionPage extends StatefulWidget {
  final String qrData;

  const TransactionPage({super.key, required this.qrData});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  final LocalAuthentication auth = LocalAuthentication();
  Map<String, dynamic> transaction = {};
  Map<String, dynamic> displayTransaction = {};
  bool isLoading = false;
  String? parseError;

  @override
  void initState() {
    super.initState();
    _parseQRData();
  }

  bool get _hasRequiredTransactionFields =>
      transaction["id"] != null &&
      transaction["qr_session_id"] != null &&
      transaction["sender_account_id"] != null &&
      transaction["amount"] != null &&
      transaction["merchant_reference"] != null &&
      transaction["created_at"] != null;

  String _formatFieldLabel(String key) {
    final words = key
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1));
    return words.join(' ');
  }

  /// Parse QR code: tries encrypted JSON first, plain JSON second, else key/value pairs.
  void _parseQRData() async {
    final parsedTransaction = <String, dynamic>{};
    final rawDisplayTransaction = <String, dynamic>{};
    String? errorMessage;

    try {
      print("RAW QR DATA: ${widget.qrData}");
      final decodedQR = jsonDecode(widget.qrData);

      if (decodedQR is! Map<String, dynamic>) {
        throw const FormatException("QR JSON is not an object");
      }

      final encryptedKeyValue =
          decodedQR["encAES"] ??
          decodedQR["encrypted_key"] ??
          decodedQR["encryptedKey"];
      final ivValue =
          decodedQR["initial_vector"] ??
          decodedQR["iv"] ??
          decodedQR["initialVector"];
      final ciphertextValue =
          decodedQR["cipher"] ??
          decodedQR["ciphertext"] ??
          decodedQR["cipherText"];
      final authTagValue =
          decodedQR["auth_tag"] ?? decodedQR["authTag"] ?? decodedQR["tag"];

      final hasEncryptedPayload =
          encryptedKeyValue != null &&
          ivValue != null &&
          ciphertextValue != null;

      if (hasEncryptedPayload) {
        // decode base64 (require update from qr_session)
        final encAESKey = base64Decode(encryptedKeyValue.toString());
        final iv = base64Decode(ivValue.toString());
        final ciphertext = base64Decode(ciphertextValue.toString());

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
        final plaintext = authTagValue == null
            ? CryptoService.decryptPayloadWithAES(rawAESKey, iv, ciphertext)
            : CryptoService.decryptPayloadWithAESGCM(
                rawAESKey,
                iv,
                ciphertext,
                base64Decode(authTagValue.toString()),
              );
        print("DECRYPTED QR PLAINTEXT: $plaintext");

        final decryptedTransaction = jsonDecode(plaintext);
        if (decryptedTransaction is! Map<String, dynamic>) {
          throw Exception("Invalid decrypted transaction");
        }
        rawDisplayTransaction.addAll(
          buildDisplayTransactionData(decryptedTransaction),
        );
        parsedTransaction.addAll(
          normalizeTransactionData(decryptedTransaction),
        );
      } else {
        rawDisplayTransaction.addAll(buildDisplayTransactionData(decodedQR));
        parsedTransaction.addAll(normalizeTransactionData(decodedQR));
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
          if (buildDisplayTransactionData({key: value}).isNotEmpty) {
            rawDisplayTransaction[key] = value;
          }
        }
      }
      parsedTransaction.addAll(normalizeTransactionData(parsedTransaction));
      print("PARSED TEXT TRANSACTION: $parsedTransaction");
    } catch (e) {
      errorMessage = e.toString();
      print("QR PARSE/DECRYPT ERROR: $e");
    }

    if (mounted) {
      setState(() {
        transaction = parsedTransaction;
        displayTransaction = rawDisplayTransaction;
        parseError = errorMessage;
      });
    } else {
      transaction = parsedTransaction;
      displayTransaction = rawDisplayTransaction;
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

      final requestBody = buildDecisionRequestBody(
        transaction: transaction,
        action: action,
        signature: signature,
        hash: hash,
      );

      print("DECISION REQUEST: ${jsonEncode(requestBody)}");

      final response = await http.post(
        Uri.parse(
          "https://fyp-bank-backend.onrender.com/api/payments/decision/",
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

        final integrityPlaintext = buildIntegrityPlaintext(transaction);

        // generate hash and signature
        final signature = CryptoService.signData(
          privateKey,
          integrityPlaintext,
        );
        final hashDigest = CryptoService.getHashHex(integrityPlaintext);

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
      body: SafeArea(
        child: SingleChildScrollView(
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
                      const Text(
                        "Transaction Details",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (displayTransaction.isEmpty && parseError == null)
                        const Text(
                          "Loading transaction details...",
                          style: TextStyle(color: Colors.grey),
                        )
                      else
                        ...displayTransaction.entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatFieldLabel(entry.key),
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry.value?.toString() ?? "",
                                  softWrap: true,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
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

              const SizedBox(height: 32),

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
      ),
    );
  }
}
