import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../security/crypto_service.dart';
import '../security/screenshot_security_service.dart';

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
  final LocalAuthentication auth = LocalAuthentication();

  Set<String> revealedCards = {};
  Map<String, String> revealedCvvs = {};
  bool isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    fetchAll();
  }

  @override
  void dispose() {
    for (final _ in revealedCards) {
      ScreenshotSecurityService.disable();
    }
    _pageController.dispose();
    super.dispose();
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
      Uri.parse("https://fyp-bank-backend.onrender.com/api/account/cards"),
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

  Future<bool> _authenticate() async {
    try {
      final canCheck = await auth.canCheckBiometrics;
      final isSupported = await auth.isDeviceSupported();

      if (!canCheck || !isSupported) return false;

      setState(() => isAuthenticating = true);

      final result = await auth.authenticate(
        localizedReason: 'Authenticate to view card details',
        biometricOnly: false,
      );

      setState(() => isAuthenticating = false);
      return result;
    } catch (e) {
      setState(() => isAuthenticating = false);
      return false;
    }
  }

  String _cardRevealKey(Map<String, dynamic> card) {
    return (card['card_token'] ?? card['id'] ?? card['card_last4']).toString();
  }

  Future<String> _decryptCardCvv(Map<String, dynamic> card) async {
    final encryptedCvv = card['cvv_encrypted']?.toString();
    if (encryptedCvv == null || encryptedCvv.isEmpty) {
      throw Exception("Encrypted CVV is unavailable");
    }

    final secureStorage = const FlutterSecureStorage();
    final accountId = await secureStorage.read(key: 'lastUser');
    if (accountId == null || accountId.isEmpty) {
      throw Exception("No logged in user");
    }

    final privateKey = await CryptoService.getPrivateKey(accountId: accountId);
    if (privateKey == null) {
      throw Exception("Private key not found on this device");
    }

    final encryptedBytes = base64Decode(encryptedCvv);
    final cvv = CryptoService.decryptStringWithRSAOAEP(
      privateKey,
      encryptedBytes,
    );

    if (!RegExp(r'^\d{3}$').hasMatch(cvv)) {
      throw Exception("Invalid decrypted CVV");
    }

    return cvv;
  }

  Future<void> _handleReveal(Map<String, dynamic> card) async {
    final cardKey = _cardRevealKey(card);

    if (revealedCards.contains(cardKey)) {
      await _hideRevealedCard(cardKey);
      return;
    }

    final success = await _authenticate();
    if (!success) return;

    try {
      final cvv = await _decryptCardCvv(card);
      if (!mounted) return;

      await ScreenshotSecurityService.enable();
      if (!mounted) {
        await ScreenshotSecurityService.disable();
        return;
      }

      setState(() {
        revealedCvvs[cardKey] = cvv;
        revealedCards.add(cardKey);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Unable to reveal CVV.")));
      return;
    }

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        _hideRevealedCard(cardKey);
      }
    });
  }

  Future<void> _hideRevealedCard(String cardKey) async {
    var wasRevealed = false;

    if (mounted) {
      setState(() {
        wasRevealed = revealedCards.remove(cardKey);
        revealedCvvs.remove(cardKey);
      });
    }

    if (wasRevealed) {
      await ScreenshotSecurityService.disable();
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
    if (cards.isEmpty) return const Text("No cards available");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Cards",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),

        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _pageController,
            itemCount: cards.length,
            onPageChanged: (i) => setState(() => currentCardIndex = i),
            itemBuilder: (context, index) {
              final card = cards[index];

              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: _cardWidget(card),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cardWidget(Map<String, dynamic> card) {
    final cardKey = _cardRevealKey(card);
    final isRevealed = revealedCards.contains(cardKey);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.black87, Colors.black54],
        ),
        borderRadius: BorderRadius.circular(16),
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
            isRevealed
                ? card['card_number']
                : "**** **** **** ${card['card_last4']}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              letterSpacing: 2,
            ),
          ),

          if (isRevealed) ...[
            const SizedBox(height: 8),
            Text(
              "CVV: ${revealedCvvs[cardKey] ?? '---'}",
              style: const TextStyle(color: Colors.white),
            ),
          ],

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

          const SizedBox(height: 10),

          Align(
            alignment: Alignment.bottomRight,
            child: TextButton(
              onPressed: isAuthenticating
                  ? null
                  : () => _handleReveal(Map<String, dynamic>.from(card)),
              child: Text(
                isRevealed ? "Hide" : "Reveal",
                style: const TextStyle(color: Colors.white),
              ),
            ),
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
