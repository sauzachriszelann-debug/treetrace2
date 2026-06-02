import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/theme.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

class TreeDetailScreen extends StatefulWidget {
  final int treeId;
  const TreeDetailScreen({super.key, required this.treeId});
  @override
  State<TreeDetailScreen> createState() => _TreeDetailScreenState();
}

class _TreeDetailScreenState extends State<TreeDetailScreen> {
  TreeModel? _tree;
  List<HealthLogModel> _logs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final t = await api.getPublicTree(widget.treeId.toString());
      List<dynamic> l = [];
      try {
        l = await api.getTreeHealthLogs(widget.treeId);
      } catch (_) {}
      setState(() {
        _tree = TreeModel.fromJson(t);
        _logs = l.map((j) => HealthLogModel.fromJson(j)).toList();
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(
      appBar: AppBar(),
      body: const Center(child: CircularProgressIndicator(color: kPrimary)),
    );
    if (_tree == null) return Scaffold(
      appBar: AppBar(),
      body: const EmptyState(message: 'Tree not found'),
    );

    final tree = _tree!;
    final role = context.read<AuthProvider>().user?.role;
    final canManage = role != 'citizen';
    final canDeleteTree = role == 'admin';
    return Scaffold(
      body: CustomScrollView(slivers: [
        // ── Photo / header ────────────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: tree.photoUrl != null ? 260 : 120,
          pinned: true,
          backgroundColor: kSidebarBg,
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            title: Text(tree.commonName,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w700)),
            background: tree.photoUrl != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.network(tree.photoUrl!, fit: BoxFit.cover),
                    Container(decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent,
                          Colors.black.withOpacity(0.65)],
                      ),
                    )),
                  ])
                : Container(color: kSidebarBg),
          ),
        ),

        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name + health badge
              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tree.commonName, style: GoogleFonts.inter(
                        fontSize: 22, fontWeight: FontWeight.w800,
                        color: kForeground)),
                    if (tree.scientificName != null)
                      Text(tree.scientificName!,
                          style: const TextStyle(
                              fontSize: 14, color: kMutedFg,
                              fontStyle: FontStyle.italic)),
                    Text('ID: ${tree.id}',
                        style: const TextStyle(
                            fontSize: 12, color: kMutedFg)),
                  ],
                )),
                HealthBadge(tree.healthStatus),
              ]),
              if (tree.isProtected || const ['CR', 'EN', 'VU'].contains(tree.statusCode)) ...[
                const SizedBox(height: 14),
                _ConservationWarning(tree: tree),
              ],
              if (canManage) ...[
                const SizedBox(height: 14),
                _buildManagementActions(canDeleteTree),
              ],
              const SizedBox(height: 16),

              // Details card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kBorder),
                ),
                child: Column(children: [
                  _infoRow(Icons.location_on_outlined, 'Barangay',
                      tree.barangay),
                  _infoRow(Icons.location_city_outlined, 'City',
                      tree.city),
                  _infoRow(Icons.straighten, 'DBH',
                      tree.dbhCm != null
                          ? '${tree.dbhCm!.toStringAsFixed(1)} cm' : null),
                  _infoRow(Icons.height, 'Height',
                      tree.heightM != null
                          ? '${tree.heightM!.toStringAsFixed(1)} m' : null),
                  _infoRow(Icons.eco_outlined, 'Carbon Stock',
                      tree.carbonKg != null
                          ? '${tree.carbonKg!.toStringAsFixed(2)} kg' : null),
                  _infoRow(Icons.gps_fixed, 'GPS',
                      tree.lat != null
                          ? '${tree.lat!.toStringAsFixed(5)}, ${tree.lng!.toStringAsFixed(5)}'
                          : null),
                  if (tree.notes != null && tree.notes!.isNotEmpty) ...[
                    const Divider(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(tree.notes!,
                          style: const TextStyle(
                              fontSize: 13, color: kForeground,
                              height: 1.5)),
                    ),
                  ],
                ]),
              ),

              // Health logs
              SectionHeader('Health History',
                action: canManage
                    ? OutlinedButton.icon(
                        onPressed: _showAddHealthLogSheet,
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('Add'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: kPrimary,
                          side: const BorderSide(color: kBorder),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      )
                    : Text('${_logs.length} records',
                        style: const TextStyle(fontSize: 12, color: kMutedFg))),

              if (_logs.isEmpty)
                const EmptyState(message: 'No health logs yet',
                    icon: Icons.history_outlined)
              else
                ..._logs.map((log) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: healthColor(log.condition).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        log.condition == 'Healthy'
                            ? Icons.check_circle_outline
                            : log.condition == 'Fair'
                                ? Icons.warning_amber_outlined
                                : Icons.cancel_outlined,
                        color: healthColor(log.condition), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          HealthBadge(log.condition, small: true),
                          const Spacer(),
                          Text(log.assessedDate,
                              style: const TextStyle(
                                  fontSize: 11, color: kMutedFg)),
                        ]),
                        if (log.notes != null && log.notes!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(log.notes!,
                              style: const TextStyle(
                                  fontSize: 12, color: kMutedFg)),
                        ],
                        if (log.dbhCm != null)
                          Text('DBH: ${log.dbhCm!.toStringAsFixed(1)} cm'
                              '${log.heightM != null ? '  ·  H: ${log.heightM!.toStringAsFixed(1)} m' : ''}',
                              style: const TextStyle(
                                  fontSize: 11, color: kMutedFg)),
                      ],
                    )),
                    if (canManage)
                      IconButton(
                        tooltip: 'Delete log',
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: kPoor),
                        onPressed: () => _deleteHealthLog(log.id),
                      ),
                  ]),
                )),
              const SizedBox(height: 24),
            ],
          ),
        )),
      ]),
    );
  }

  Widget _buildManagementActions(bool canDeleteTree) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ActionTile(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onTap: _showEditTreeSheet,
            ),
          ),
          _ActionDivider(),
          Expanded(
            child: _ActionTile(
              icon: Icons.monitor_heart_outlined,
              label: 'Health Log',
              onTap: _showAddHealthLogSheet,
            ),
          ),
          if (canDeleteTree) ...[
            _ActionDivider(),
            Expanded(
              child: _ActionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                color: kPoor,
                onTap: _deleteTree,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showAddHealthLogSheet() async {
    final tree = _tree;
    if (tree == null) return;
    final conditionCtrl = ValueNotifier<String>(tree.healthStatus);
    final dbhCtrl = TextEditingController(text: tree.dbhCm?.toString() ?? '');
    final heightCtrl =
        TextEditingController(text: tree.heightM?.toString() ?? '');
    final notesCtrl = TextEditingController();
    var queuedOffline = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: SafeArea(
          child: ValueListenableBuilder<String>(
            valueListenable: conditionCtrl,
            builder: (_, condition, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Add Health Log',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: condition,
                  decoration: const InputDecoration(
                    labelText: 'Condition',
                    prefixIcon: Icon(Icons.favorite_outline_rounded),
                  ),
                  items: ['Healthy', 'Fair', 'Poor']
                      .map((item) =>
                          DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) conditionCtrl.value = value;
                  },
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: dbhCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'DBH (cm)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: heightCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Height (m)'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final now = DateTime.now();
                      final date =
                          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                      final payload = <String, dynamic>{
                        'tree_id': tree.id,
                        'condition': conditionCtrl.value,
                        'assessed_date': date,
                        'dbh_cm': double.tryParse(dbhCtrl.text.trim()),
                        'height_m': double.tryParse(heightCtrl.text.trim()),
                        'notes': notesCtrl.text.trim().isEmpty
                            ? null
                            : notesCtrl.text.trim(),
                      };
                      if (await api.isOnline()) {
                        await api.createHealthLog(payload);
                      } else {
                        await api.queueOfflineAction(
                          'CREATE_HEALTH_LOG',
                          payload,
                        );
                        queuedOffline = true;
                      }
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext, true);
                      }
                    } catch (e) {
                      final errorText = e.toString().toLowerCase();
                      final shouldQueue = errorText.contains('connection') ||
                          errorText.contains('failed host lookup') ||
                          errorText.contains('socketexception');
                      if (shouldQueue) {
                        final now = DateTime.now();
                        final date =
                            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                        await api.queueOfflineAction(
                          'CREATE_HEALTH_LOG',
                          <String, dynamic>{
                            'tree_id': tree.id,
                            'condition': conditionCtrl.value,
                            'assessed_date': date,
                            'dbh_cm': double.tryParse(dbhCtrl.text.trim()),
                            'height_m': double.tryParse(heightCtrl.text.trim()),
                            'notes': notesCtrl.text.trim().isEmpty
                                ? null
                                : notesCtrl.text.trim(),
                          },
                        );
                        queuedOffline = true;
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext, true);
                        }
                        return;
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Could not save health log: $e'),
                          backgroundColor: kPoor,
                        ));
                      }
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Health Log'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      if (!queuedOffline) {
        await _load();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(queuedOffline
              ? 'Health log saved offline. Review it in Field Sync before uploading.'
              : 'Health log saved.'),
          backgroundColor: queuedOffline ? kFair : kHealthy,
        ));
      }
    }
  }

  Future<void> _showEditTreeSheet() async {
    final tree = _tree;
    if (tree == null) return;
    final nameCtrl = TextEditingController(text: tree.commonName);
    final sciCtrl = TextEditingController(text: tree.scientificName ?? '');
    final barangayCtrl = TextEditingController(text: tree.barangay ?? '');
    final dbhCtrl = TextEditingController(text: tree.dbhCm?.toString() ?? '');
    final heightCtrl =
        TextEditingController(text: tree.heightM?.toString() ?? '');
    final latCtrl = TextEditingController(text: tree.lat?.toString() ?? '');
    final lngCtrl = TextEditingController(text: tree.lng?.toString() ?? '');
    final notesCtrl = TextEditingController(text: tree.notes ?? '');
    final healthCtrl = ValueNotifier<String>(tree.healthStatus);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: ValueListenableBuilder<String>(
              valueListenable: healthCtrl,
              builder: (_, health, __) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Edit Tree',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Common Name'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: sciCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Scientific Name'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: health,
                    decoration: const InputDecoration(labelText: 'Health'),
                    items: ['Healthy', 'Fair', 'Poor']
                        .map((item) =>
                            DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) healthCtrl.value = value;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: barangayCtrl,
                    decoration: const InputDecoration(labelText: 'Barangay'),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: dbhCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'DBH'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: heightCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Height'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: latCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: const InputDecoration(labelText: 'Latitude'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: lngCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration:
                            const InputDecoration(labelText: 'Longitude'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      try {
                        await api.updateTree(tree.id, {
                          'common_name': nameCtrl.text.trim(),
                          'scientific_name': sciCtrl.text.trim().isEmpty
                              ? null
                              : sciCtrl.text.trim(),
                          'health_status': healthCtrl.value,
                          'barangay': barangayCtrl.text.trim().isEmpty
                              ? null
                              : barangayCtrl.text.trim(),
                          'dbh_cm': double.tryParse(dbhCtrl.text.trim()),
                          'height_m': double.tryParse(heightCtrl.text.trim()),
                          'lat': double.tryParse(latCtrl.text.trim()),
                          'lng': double.tryParse(lngCtrl.text.trim()),
                          'notes': notesCtrl.text.trim().isEmpty
                              ? null
                              : notesCtrl.text.trim(),
                        });
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext, true);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Could not update tree: $e'),
                            backgroundColor: kPoor,
                          ));
                        }
                      }
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tree updated.'),
          backgroundColor: kHealthy,
        ));
      }
    }
  }

  Future<void> _deleteTree() async {
    final tree = _tree;
    if (tree == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Tree?'),
        content: Text('Delete ${tree.commonName}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPoor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await api.deleteTree(tree.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not delete tree: $e'),
          backgroundColor: kPoor,
        ));
      }
    }
  }

  Future<void> _deleteHealthLog(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Health Log?'),
        content: const Text('This health assessment will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPoor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await api.deleteHealthLog(id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Health log deleted.'),
          backgroundColor: kHealthy,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not delete health log: $e'),
          backgroundColor: kPoor,
        ));
      }
    }
  }

  Widget _infoRow(IconData icon, String label, String? value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 15, color: kMutedFg),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(
            fontSize: 13, color: kMutedFg, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(value, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: kForeground)),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = kPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConservationWarning extends StatelessWidget {
  final TreeModel tree;

  const _ConservationWarning({required this.tree});

  @override
  Widget build(BuildContext context) {
    final code = tree.statusCode;
    final critical = code == 'CR';
    final endangered = code == 'EN';
    final color = critical
        ? kPoor
        : endangered
            ? Colors.orange.shade800
            : Colors.amber.shade800;
    final bg = critical
        ? Colors.red.shade50
        : endangered
            ? Colors.orange.shade50
            : Colors.amber.shade50;
    final title = critical
        ? 'Do not cut: critically endangered'
        : endangered
            ? 'Protected species: cutting prohibited'
            : 'Vulnerable species: handle with care';
    final cuttingRule = tree.cuttingAllowed
        ? 'allowed only with proper permit review'
        : 'strictly prohibited without DENR clearance';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            critical || endangered
                ? Icons.shield_outlined
                : Icons.warning_amber_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  '${tree.commonName} is listed as ${tree.endangeredStatus}. '
                  'Cutting or transporting this tree is $cuttingRule.',
                  style: const TextStyle(
                      color: kForeground, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 34, color: kBorder);
  }
}
