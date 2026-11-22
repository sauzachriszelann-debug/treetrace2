import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'public_tree_profile_screen.dart';

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

  void _showLabel(TreeModel tree) {
    const webBase = String.fromEnvironment('TREETRACE_PUBLIC_WEB_URL');
    final path = '/public/tree/${tree.id}';
    final base = Uri.tryParse(webBase);
    final payload = base != null && base.hasAuthority &&
        (base.scheme == 'https' || base.scheme == 'http')
        ? base.resolve(path).toString() : path;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: kCard,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('TreeTrace', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kPrimary)),
          const SizedBox(height: 12),
          Text(tree.commonName, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (tree.scientificName?.isNotEmpty == true)
            Text(tree.scientificName!, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: kMutedFg)),
          Text('Tree #${tree.id}', style: const TextStyle(fontSize: 12, color: kMutedFg)),
          const SizedBox(height: 16),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240),
            child: AspectRatio(aspectRatio: 1, child: QrImageView(
              data: payload, backgroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              semanticsLabel: 'QR code for ${tree.commonName}, tree ${tree.id}',
            ))),
          const SizedBox(height: 12),
          const Text('Scan this code using TreeTrace to view the tree profile.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kMutedFg)),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('View public profile'),
            onPressed: () {
              Navigator.pop(sheetContext);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PublicTreeProfileScreen(treeId: tree.id)));
            },
          )),
          TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Close')),
        ]),
      ),
    );
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
                  'Tap a tree to view its QR code. Use the web Reports page for print-ready sheets.',
                  style: TextStyle(color: kMutedFg, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ..._trees.map((tree) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: kCard,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kBorder)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _showLabel(tree),
                      child: Container(
                      padding: const EdgeInsets.all(12),
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
                          const Icon(Icons.chevron_right, color: kMutedFg),
                        ],
                      ),
                    ))))),
              ],
            ),
    );
  }
}
