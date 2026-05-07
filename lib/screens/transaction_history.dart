import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({super.key});

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  bool loading = true;
  String? error;
  List<dynamic> transactions = [];

  @override
  void initState() {
    super.initState();
    fetchTransactions();
  }

  Future<void> fetchTransactions() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final token = await secureStorage.read(key: 'token');
      print(token);

      if (token == null || token.isEmpty) {
        throw Exception("No token found");
      }

      final response = await http.get(
        Uri.parse(
          "https://fyp-bank-backend.onrender.com/api/account/transactions",
        ),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        transactions = (data["transactions"] as List?) ?? [];
      } else {
        throw Exception("Failed to load transactions");
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  String formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return "${dt.day}/${dt.month}/${dt.year} "
          "${dt.hour.toString().padLeft(2, '0')}:"
          "${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return raw;
    }
  }

  Color statusColor(String status) {
    switch (status.toUpperCase()) {
      case "APPROVED":
        return Colors.green;
      case "REJECTED":
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData statusIcon(String status) {
    switch (status.toUpperCase()) {
      case "APPROVED":
        return Icons.check_circle;
      case "REJECTED":
        return Icons.cancel;
      default:
        return Icons.hourglass_bottom;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Transaction History"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchTransactions,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            )
          : transactions.isEmpty
          ? const Center(child: Text("No transactions found"))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final tx = transactions[index];

                final amount = (tx["amount"] as num? ?? 0).toDouble();

                final status = (tx["status"] ?? "UNKNOWN").toString();

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Merchant + Status
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                tx["merchant_reference"] ?? "Unknown Merchant",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Icon(
                                  statusIcon(status),
                                  size: 18,
                                  color: statusColor(status),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor(status),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Date
                        Text(
                          formatDate(tx["created_at"] ?? ""),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Transaction ID
                        Text(
                          "ID: ${tx["id"] ?? ""}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Amount
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              tx["currency"] ?? "SGD",
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              NumberFormat('#,##0.00').format(amount),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
