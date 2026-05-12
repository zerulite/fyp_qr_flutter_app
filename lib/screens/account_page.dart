import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Map<String, dynamic>? accountData;
  List<dynamic> cards = [];

  bool isLoading = true;
  int currentCardIndex = 0;

  final PageController _pageController = PageController(viewportFraction: 0.85);

  @override
  void initState() {
    super.initState();
    fetchAll();
  }

  Future<void> fetchAll() async {
    setState(() => isLoading = true);

    try {
      final results = await Future.wait([fetchAccount(), fetchCards()]);

      setState(() {
        accountData = results[0] as Map<String, dynamic>;
        cards = results[1] as List<dynamic>;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint("Error: $e");
    }
  }

  Future<Map<String, dynamic>> fetchAccount() async {
    final secureStorage = const FlutterSecureStorage();
    final token = await secureStorage.read(key: 'token');

    final res = await http.get(
      Uri.parse("https://fyp-bank-backend.onrender.com/api/account"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    } else {
      throw Exception("Failed to load account");
    }
  }

  Future<List<dynamic>> fetchCards() async {
    final secureStorage = const FlutterSecureStorage();
    final token = await secureStorage.read(key: 'token');

    final res = await http.get(
      Uri.parse("https://fyp-bank-backend.onrender.com/api/accounts/cards"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      return decoded['cards'] ?? [];
    } else {
      throw Exception("Failed to load cards");
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

    return Scaffold(
      appBar: AppBar(title: const Text("My Account")),
      body: RefreshIndicator(
        onRefresh: fetchAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildAccountSummary(),
              const SizedBox(height: 20),
              _buildCardCarousel(),
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

  Widget _buildCardCarousel() {
    if (cards.isEmpty) {
      return const Text("No cards available");
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Cards",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),

        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _pageController,
            itemCount: cards.length,
            onPageChanged: (index) {
              setState(() => currentCardIndex = index);
            },
            itemBuilder: (context, index) {
              final card = cards[index];
              final isActive = index == currentCardIndex;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: isActive ? 0 : 10,
                ),
                child: _cardWidget(card),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(cards.length, (index) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: currentCardIndex == index ? 10 : 6,
              height: currentCardIndex == index ? 10 : 6,
              decoration: BoxDecoration(
                color: currentCardIndex == index
                    ? Colors.blueAccent
                    : Colors.grey,
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _cardWidget(Map<String, dynamic> card) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.black87, Colors.black54],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 6),
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
          const Spacer(),
          Text(
            "**** **** **** ${card['card_last4']}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
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
