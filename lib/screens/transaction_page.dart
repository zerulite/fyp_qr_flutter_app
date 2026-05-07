import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
//import 'package:shared_preferences/shared_preferences.dart';
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

String friendlyDecisionError(int statusCode, Map<String, dynamic> data) {
  final message = data["message"] ?? data["error"];

  if (statusCode == 401) {
    return "We could not verify this transaction. Please try again.";
  }
  if (statusCode == 404) {
    return "This transaction is no longer available.";
  }
  if (message is String && message.isNotEmpty && statusCode >= 400) {
    return message;
  }
  return "We could not process this transaction. Please try again.";
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

  String _formatAmount() {
    final amount = transaction["amount"];
    if (amount == null) return "--";

    final currency = transaction["currency"];
    final amountText = amount is num
        ? amount.toStringAsFixed(2)
        : amount.toString();

    if (currency == null || currency.toString().isEmpty) {
      return amountText;
    }

    return "${currency.toString()} $amountText";
  }

  String _shortId(dynamic value) {
    final text = value?.toString() ?? "";
    if (text.length <= 13) return text;
    return "${text.substring(0, 4)}...${text.substring(text.length - 4)}";
  }

  String _formatCreatedAt() {
    final raw = transaction["created_at"]?.toString();
    if (raw == null || raw.isEmpty) return "--";

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return "$day/$month/$year $hour:$minute";
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Parse QR code: tries encrypted JSON first, plain JSON second, else key/value pairs.
  void _parseQRData() async {
    final parsedTransaction = <String, dynamic>{};
    final rawDisplayTransaction = <String, dynamic>{};
    String? errorMessage;

    try {
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
        final authTag = authTagValue == null
            ? null
            : base64Decode(authTagValue.toString());

        // access private key
        final prefs = await SharedPreferences.getInstance();
        final accountId = prefs.getString('lastUser');
        if (accountId == null) throw Exception("No logged in user");

        final privateKey = await CryptoService.getPrivateKey(
          accountId: accountId,
        );
        if (privateKey == null) throw Exception("Lost Private key");

        // decrypt AES key with RSA private
        late final Uint8List rawAESKey;
        try {
          rawAESKey = CryptoService.decryptAESKeyWithRSA(privateKey, encAESKey);
        } catch (e) {
          throw Exception("RSA AES key decrypt failed: $e");
        }

        // decrypt ciphertext with AES key => get transaction plain text
        late final String plaintext;
        try {
          plaintext = authTag == null
              ? CryptoService.decryptPayloadWithAES(rawAESKey, iv, ciphertext)
              : CryptoService.decryptPayloadWithAESGCM(
                  rawAESKey,
                  iv,
                  ciphertext,
                  authTag,
                );
        } catch (e) {
          throw Exception("AES payload decrypt failed: $e");
        }

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
    } catch (e) {
      errorMessage =
          "Unable to read this QR code. Please scan a valid transaction QR.";
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
  }

  /// Send approval/rejection request to backend
  Future<void> _sendDecision({
    required String action,
    required String signature,
    required String hash,
  }) async {
    setState(() => isLoading = true);

    try {
      final secureStorage = const FlutterSecureStorage();
      final token = await secureStorage.read(key: 'token') ?? '';

      if (token.isEmpty) {
        throw Exception('No token found. Please log in first.');
      }

      final requestBody = buildDecisionRequestBody(
        transaction: transaction,
        action: action,
        signature: signature,
        hash: hash,
      );

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

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (!mounted) return;

      if (response.statusCode == 200) {
        if (action == "APPROVE") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => ApprovalPage(transaction: data)),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => RejectedPage(transaction: data)),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyDecisionError(response.statusCode, data)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "We could not process this transaction. Please try again.",
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Authenticate user via biometrics before sending decision
  Future<void> _authenticateAndSend(String action, String plaintext) async {
    try {
      // Parse amount safely
      final amount = double.tryParse(transaction["amount"].toString()) ?? 0.0;

      // Step 1: show popup BEFORE biometrics (only for high value approvals)
      if (action == "APPROVE" && amount > 5000) {
        final confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text("High Value Transaction"),
            content: Text(
              "This transaction is ${transaction["currency"] ?? ""} ${amount.toStringAsFixed(2)}.\n\nProceed to authentication?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Continue"),
              ),
            ],
          ),
        );

        if (confirm != true) return;
      }

      // Step 2: biometric authentication
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
        final hashDigest = CryptoService.getHashHex(integrityPlaintext);

        // Sign the same hash value the server verifies.
        final signature = CryptoService.signData(privateKey, hashDigest);

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
        return;
      }

      // Step 3: send request
      await _sendDecision(action);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Authentication could not be completed. Try again."),
        ),
      );
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
                elevation: 4,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (displayTransaction.isEmpty && parseError == null)
                        const Text(
                          "Loading transaction details...",
                          style: TextStyle(color: Colors.grey),
                        )
                      else if (parseError == null) ...[
                        const Text(
                          "Amount",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatAmount(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          transaction["merchant_reference"]?.toString() ??
                              "Merchant reference unavailable",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF6F55A3),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        _detailRow(
                          "Transaction ID",
                          _shortId(transaction["id"]),
                        ),
                        _detailRow(
                          "QR Session",
                          _shortId(transaction["qr_session_id"]),
                        ),
                        _detailRow(
                          "Account",
                          _shortId(transaction["sender_account_id"]),
                        ),
                        _detailRow("Created", _formatCreatedAt()),
                      ],
                      if (parseError != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                parseError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
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
                  foregroundColor: const Color(0xFF6F55A3),
                  backgroundColor: Colors.white,
                  disabledForegroundColor: Colors.grey,
                  disabledBackgroundColor: const Color(0xFFE7E0EA),
                  elevation: 3,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
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
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFFF44336),
                  disabledForegroundColor: Colors.grey,
                  disabledBackgroundColor: const Color(0xFFE7E0EA),
                  elevation: 3,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
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
