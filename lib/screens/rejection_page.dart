import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login_page.dart';
import 'package:intl/intl.dart';

class RejectionPage extends StatelessWidget {
  final Map<String, dynamic> transaction;

  const RejectionPage({super.key, required this.transaction});

  Future<void> _logout(BuildContext context) async {
    final secureStorage = FlutterSecureStorage();
    await secureStorage.write(key: 'loggedIn', value: 'false');
    await secureStorage.delete(key: 'token');

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Logout"),
        content: const Text(
          "Are you sure you want to logout? You will need to log in again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Logout"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _logout(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Payment Rejected"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 30),

            const Icon(Icons.cancel_outlined, color: Colors.red, size: 100),

            const SizedBox(height: 20),

            const Text(
              "Transaction Rejected",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 30),

            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Message
                    Text(
                      transaction["message"] ?? "Transaction Rejected",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    // Status
                    Row(
                      children: [
                        const Text(
                          "Status: ",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          transaction["status"] ?? "Rejected",
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),

                    // Transaction ID
                    Text(
                      "Transaction ID: ${transaction["transaction_id"] ?? ""}",
                      style: const TextStyle(color: Colors.grey),
                    ),

                    const SizedBox(height: 10),

                    // QR Session ID
                    Text(
                      "QR Session ID: ${transaction["qr_session_id"] ?? ""}",
                      style: const TextStyle(color: Colors.grey),
                    ),

                    const SizedBox(height: 20),

                    // Optional: show balance if backend still returns it
                    if (transaction["remaining_balance"] != null) ...[
                      Text(
                        "Remaining Balance",
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        NumberFormat('#,##0.00').format(
                          (transaction["remaining_balance"] as num? ?? 0)
                              .toDouble(),
                        ),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
