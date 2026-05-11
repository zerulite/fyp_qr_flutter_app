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
  final TextEditingController searchController = TextEditingController();

  bool loading = true;
  String? error;
  List<dynamic> transactions = [];
  List<dynamic> filteredTransactions = [];
  DateTime? startDate;
  DateTime? endDate;
  String selectedStatus = "All";
  bool filtersExpanded = false;

  static const List<String> statusOptions = [
    "All",
    "Approved",
    "Rejected",
    "Pending",
  ];

  @override
  void initState() {
    super.initState();
    fetchTransactions();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> fetchTransactions() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final token = await secureStorage.read(key: 'token');

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
        filteredTransactions = transactions;
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

  DateTime? parseTransactionDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString()).toLocal();
    } catch (e) {
      return null;
    }
  }

  String formatFilterDate(DateTime? date) {
    if (date == null) return "Select date";
    return "${date.day}/${date.month}/${date.year}";
  }

  Future<void> pickDate({required bool isStartDate}) async {
    final now = DateTime.now();
    final initialDate = isStartDate
        ? startDate ?? endDate ?? now
        : endDate ?? startDate ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
    );

    if (picked == null) return;

    setState(() {
      if (isStartDate) {
        startDate = picked;
        if (endDate != null && picked.isAfter(endDate!)) {
          endDate = picked;
        }
      } else {
        endDate = picked;
        if (startDate != null && picked.isBefore(startDate!)) {
          startDate = picked;
        }
      }
    });
  }

  bool matchesSearch(Map<String, dynamic> tx, String query) {
    if (query.isEmpty) return true;

    final searchableText =
        [
              tx["merchant_reference"],
              tx["id"],
              tx["transaction_id"],
              tx["qr_session_id"],
              tx["status"],
              tx["amount"],
              tx["created_at"],
            ]
            .whereType<Object>()
            .map((value) => value.toString().toLowerCase())
            .join(" ");

    return searchableText.contains(query);
  }

  bool matchesDateRange(Map<String, dynamic> tx) {
    if (startDate == null && endDate == null) return true;

    final createdAt = parseTransactionDate(tx["created_at"]);
    if (createdAt == null) return false;

    final txDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final start = startDate == null
        ? null
        : DateTime(startDate!.year, startDate!.month, startDate!.day);
    final end = endDate == null
        ? null
        : DateTime(endDate!.year, endDate!.month, endDate!.day);

    if (start != null && txDate.isBefore(start)) return false;
    if (end != null && txDate.isAfter(end)) return false;

    return true;
  }

  bool matchesStatus(Map<String, dynamic> tx) {
    if (selectedStatus == "All") return true;

    final status = (tx["status"] ?? "").toString().toUpperCase();
    return status == selectedStatus.toUpperCase();
  }

  bool get hasActiveFilters =>
      searchController.text.trim().isNotEmpty ||
      startDate != null ||
      endDate != null ||
      selectedStatus != "All";

  void applyFilters() {
    final query = searchController.text.trim().toLowerCase();

    setState(() {
      filteredTransactions = transactions.where((transaction) {
        final tx = Map<String, dynamic>.from(transaction as Map);
        return matchesSearch(tx, query) &&
            matchesDateRange(tx) &&
            matchesStatus(tx);
      }).toList();
    });
  }

  void clearFilters() {
    searchController.clear();
    setState(() {
      startDate = null;
      endDate = null;
      selectedStatus = "All";
      filtersExpanded = false;
      filteredTransactions = transactions;
    });
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

  Widget buildDateButton({
    required String label,
    required DateTime? date,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: Colors.white,
          foregroundColor: Colors.blueGrey.shade800,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          side: BorderSide(color: Colors.blueGrey.shade100),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.calendar_today, size: 16),
        label: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500),
            ),
            Text(
              formatFilterDate(date),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildStatusChip(String status) {
    final isSelected = selectedStatus == status;

    return ChoiceChip(
      label: Text(status),
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(
        status == "All" ? Icons.list_alt : statusIcon(status),
        size: 16,
        color: isSelected ? Colors.white : statusColor(status),
      ),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.blueGrey.shade800,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      selectedColor: Colors.blue.shade700,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? Colors.blue.shade700 : Colors.blueGrey.shade100,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (_) {
        setState(() => selectedStatus = status);
      },
    );
  }

  Widget buildFilterSection() {
    final showFilterOptions = filtersExpanded || hasActiveFilters;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onTap: () => setState(() => filtersExpanded = true),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => applyFilters(),
            decoration: InputDecoration(
              hintText: "Search merchant, ID, amount",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: "Clear search",
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        searchController.clear();
                        setState(() {});
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.blueGrey.shade100),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.blue.shade600, width: 1.4),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                const SizedBox(height: 12),
                Row(
                  children: [
                    buildDateButton(
                      label: "Start",
                      date: startDate,
                      onPressed: () => pickDate(isStartDate: true),
                    ),
                    const SizedBox(width: 8),
                    buildDateButton(
                      label: "End",
                      date: endDate,
                      onPressed: () => pickDate(isStartDate: false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final status in statusOptions) ...[
                        buildStatusChip(status),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: applyFilters,
                        icon: const Icon(Icons.search),
                        label: const Text("Search"),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: hasActiveFilters ? clearFilters : null,
                      icon: const Icon(Icons.clear),
                      label: const Text("Clear"),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(94, 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            crossFadeState: showFilterOptions
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
          if (transactions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              "Showing ${filteredTransactions.length} of ${transactions.length} transactions",
              style: TextStyle(
                color: Colors.blueGrey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildTransactionCard(Map<String, dynamic> tx) {
    final amount = (tx["amount"] as num? ?? 0).toDouble();

    final status = (tx["status"] ?? "UNKNOWN").toString();

    final color = statusColor(status);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.blueGrey.shade100),
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
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withAlpha(24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon(status), size: 16, color: color),
                      const SizedBox(width: 4),
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Date
            Text(
              formatDate(tx["created_at"] ?? ""),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),

            const SizedBox(height: 10),

            // Transaction ID
            Text(
              "ID: ${tx["id"] ?? ""}",
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),

            const SizedBox(height: 12),

            // Amount
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tx["currency"] ?? "SGD",
                  style: TextStyle(
                    color: Colors.blueGrey.shade700,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Transaction History"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
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
          : Column(
              children: [
                buildFilterSection(),
                Expanded(
                  child: transactions.isEmpty
                      ? const Center(child: Text("No transactions found"))
                      : filteredTransactions.isEmpty
                      ? const Center(
                          child: Text("No matching transactions found"),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredTransactions.length,
                          itemBuilder: (context, index) {
                            final tx = Map<String, dynamic>.from(
                              filteredTransactions[index] as Map,
                            );

                            return buildTransactionCard(tx);
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
