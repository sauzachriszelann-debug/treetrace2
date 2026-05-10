import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import 'public_tree_profile_screen.dart';

class MapScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const MapScreen({super.key, this.onBack});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<TreeModel> _trees = [];
  bool _loading = true;
  String _filter = 'all';
  String _search = '';
  bool _isSatellite = false;
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  static const _center = LatLng(7.3047, 125.6856);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await api.getPublicTrees();
      setState(() {
        _trees = data.map((j) => TreeModel.fromJson(j))
            .where((t) => t.lat != null && t.lng != null)
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<TreeModel> get _filtered {
    Iterable<TreeModel> result = _filter == 'all'
        ? _trees
        : _trees.where((t) => t.healthStatus == _filter);

    final query = _search.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((tree) {
        final values = [
          tree.commonName,
          tree.scientificName ?? '',
          tree.barangay ?? '',
          tree.city ?? '',
          tree.healthStatus,
        ].join(' ').toLowerCase();
        return values.contains(query);
      });
    }

    return result.toList();
  }

  void _focusFirstSearchResult() {
    final matches = _filtered.where((tree) => tree.lat != null && tree.lng != null).toList();
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No mapped tree found for that search.')),
      );
      return;
    }

    final tree = matches.first;
    _mapController.move(LatLng(tree.lat!, tree.lng!), 17);
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Map Layer ──────────────────────────────────────────────────────
          _loading
              ? const Center(child: CircularProgressIndicator(color: kPrimary))
              : FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: _center,
                    initialZoom: 14,
                    minZoom: 2,
                    maxZoom: 22,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _isSatellite 
                        ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.treetrace.mobile',
                      maxNativeZoom: 19,
                    ),
                    MarkerLayer(
                      markers: _filtered.map((tree) {
                        final color = healthColor(tree.healthStatus);
                        return Marker(
                          point: LatLng(tree.lat!, tree.lng!),
                          width: 40, height: 40,
                          child: GestureDetector(
                            onTap: () => _showTreePopup(tree),
                            child: _buildModernMarker(color),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),

          // ── Top Controls (Search & Layer Toggle) ───────────────────────────
          _buildTopControls(),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _buildCircularButton(
                Icons.arrow_back_rounded,
                _handleBack,
              ),
            ),
          ),

          // ── Data Legend ────────────────────────────────────────────────────
          if (!_loading) _buildFloatingLegend(),
        ],
      ),
    );
  }

  Widget _buildModernMarker(Color color) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: color.withOpacity(0.3), shape: BoxShape.circle),
          ),
          Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 62),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: kMutedFg, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) => setState(() => _search = value),
                            onSubmitted: (_) => _focusFirstSearchResult(),
                            textInputAction: TextInputAction.search,
                            style: const TextStyle(color: kForeground, fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Search tree, species, barangay...',
                              hintStyle: TextStyle(
                                color: kMutedFg.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        if (_search.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: _load,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildCircularButton(
                  _isSatellite ? Icons.map_outlined : Icons.satellite_alt_rounded,
                  () => setState(() => _isSatellite = !_isSatellite),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['all', 'Healthy', 'Fair', 'Poor'].map((status) {
                  final isSelected = _filter == status;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _filter = status),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? kPrimary : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                        ),
                        child: Text(
                          status == 'all' ? 'All Trees' : status,
                          style: TextStyle(color: isSelected ? Colors.white : kForeground, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          color: kSidebarBg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildFloatingLegend() {
    return Positioned(
      bottom: 100, left: 0, right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _legendItem('Healthy', kHealthy),
              const SizedBox(width: 16),
              _legendItem('Fair', kFair),
              const SizedBox(width: 16),
              _legendItem('Poor', kPoor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kForeground)),
      ],
    );
  }

  void _showTreePopup(TreeModel tree) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            Row(
              children: [
                TreePhoto(url: tree.photoUrl, size: 70, radius: BorderRadius.circular(16)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tree.commonName, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(tree.scientificName ?? '', style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: kMutedFg)),
                      const SizedBox(height: 8),
                      HealthBadge(tree.healthStatus, small: true),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PublicTreeProfileScreen(treeId: tree.id)));
                },
                child: const Text('View Full Details', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
