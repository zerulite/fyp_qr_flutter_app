import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Map<String, dynamic>? accountData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchAccount();
  }

  Future<void> fetchAccount() async {
    try {
      final res = await http.get(
        Uri.parse("https://your-api.com/api/account"),
        headers: {"Authorization": "Bearer YOUR_TOKEN"},
      );

      if (res.statusCode == 200) {
        setState(() {
          accountData = jsonDecode(res.body);
          isLoading = false;
        });
      } else {
        throw Exception("Failed to load account");
      }
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint("Error: $e");
    }
  }

  String formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (accountData == null) {
      return const Scaffold(
        body: Center(child: Text("Failed to load account")),
      );
    }

    final lastAccess = accountData!['last_access_record'] ?? {};
    final cards = accountData!['cards'] ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text("My Account")),
      body: RefreshIndicator(
        onRefresh: fetchAccount,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildAccountSummary(),
              const SizedBox(height: 20),
              _buildCards(cards),
              const SizedBox(height: 20),
              _buildLastAccess(lastAccess),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.blueAccent, Colors.indigo],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Balance", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            "\$${accountData!['balance'].toStringAsFixed(2)}",
            style: const TextStyle(
              fontSize: 28,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Acc: ${accountData!['account_number']}",
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildCards(List cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Cards",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        if (cards.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text("No cards available"),
          )
        else
          ...cards.map((card) => _cardWidget(card)).toList(),
      ],
    );
  }

  Widget _cardWidget(Map<String, dynamic> card) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.black87, Colors.black54],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card['card_name'],
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Text(
            "**** **** **** ${card['card_last4']}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Expiry: ${card['expiry_date']}",
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                card['status'],
                style: TextStyle(
                  color: card['status'] == "ACTIVE"
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLastAccess(Map<String, dynamic> lastAccess) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Last Activity",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text("Last Login: ${formatDate(lastAccess['last_login_at'] ?? '-')}"),
          Text(
            "Last Approval: ${formatDate(lastAccess['last_approval_at'] ?? '-')}",
          ),
          Text("Device: ${lastAccess['last_seen_device'] ?? '-'}"),
        ],
      ),
    );
  }
}
