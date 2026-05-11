import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/theme.dart';

class QrLabelsScreen extends StatefulWidget {
  const QrLabelsScreen({super.key});

  @override
  State<QrLabelsScreen> createState() => _QrLabelsScreenState();
}

class _QrLabelsScreenState extends State<QrLabelsScreen> {
  List<TreeModel> _trees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.getTrees(limit: 300);
      if (mounted) {
        setState(() {
          _trees = data.map((j) => TreeModel.fromJson(j)).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('QR Labels')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'QR labels are generated from tree records. Use the web Reports page for print-ready sheets.',
                  style: TextStyle(color: kMutedFg, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ..._trees.map((tree) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.qr_code_2_rounded, color: kPrimary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tree.commonName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900)),
                                Text(tree.scientificName ?? 'Tree #${tree.id}',
                                    style: const TextStyle(
                                        color: kMutedFg, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
    );
  }
}
