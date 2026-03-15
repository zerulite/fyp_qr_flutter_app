import 'package:flutter/material.dart';

class TransactionField extends StatelessWidget {
  final String title;
  final dynamic value;

  const TransactionField(this.title, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    if (value == null) return const SizedBox();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              value.toString(),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
