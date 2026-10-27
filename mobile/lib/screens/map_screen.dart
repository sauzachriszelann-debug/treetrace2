import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/theme.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import 'public_tree_profile_screen.dart';
import 'tree_detail_screen.dart';

/// Phase 12C.2 test seam: tests inject fixture loaders so no socket is ever
/// opened. Production call sites pass nothing and keep the public endpoint.
typedef MapTreeLoader = Future<List<dynamic>> Function();

class MapScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final int refreshKey;
  final MapTreeLoader? treeLoader;
  const MapScreen(
      {super.key, this.onBack, this.refreshKey = 0, this.treeLoader});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<TreeModel> _trees = [];
  bool _loading = true;
  bool _loadError = false;
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
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final data = await (widget.treeLoader ?? api.getPublicTrees)();
      setState(() {
        _trees = data.map((j) => TreeModel.fromJson(j))
            .where((t) => t.lat != null && t.lng != null)
            .toList();
        _loading = false;
      });
      _frameMarkers();
    } catch (_) {
      // Phase 12C.2: a failed fetch is surfaced with a clear message and a
      // Retry instead of silently rendering an empty map.
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  /// Phase 12C.5 (C): frame all loaded markers so records outside the
  /// hardcoded default center remain visible. Empty data keeps the default
  /// center/zoom as the fallback view.
  void _frameMarkers() {
    if (!mounted || _trees.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _trees.isEmpty) return;
      final lats = _trees.map((t) => t.lat!).toList();
      final lngs = _trees.map((t) => t.lng!).toList();
      final bounds = LatLngBounds(
        LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
        LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
      );
      _mapController.fitCamera(CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(48, 200, 48, 150),
        maxZoom: 16,
      ));
    });
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
          if (_loading)
            const Center(child: CircularProgressIndicator(color: kPrimary))
          else if (_loadError)
            _buildLoadError()
          else
              FlutterMap(
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
                          key: ValueKey('map-marker-${tree.id}'),
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
          if (!_loading && !_loadError) _buildFloatingLegend(),

          // Phase 12C.5 (A): always-visible tile credit. flutter_map's
          // attribution layer did not paint on the test device (verified on
          // Realme RMX3363), so the required OSM/Esri credit is rendered
          // directly in the screen's own stack.
          if (!_loading && !_loadError)
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 4),
                  ],
                ),
                child: Text(
                  _isSatellite
                      ? '© OpenStreetMap · Imagery © Esri, Maxar, Earthstar Geographics'
                      : '© OpenStreetMap contributors',
                  style: const TextStyle(
                      color: kForeground,
                      fontSize: 9,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Phase 12C.2: honest failure state with an explicit Retry action.
  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 44, color: kMutedFg.withOpacity(0.6)),
            const SizedBox(height: 12),
            const Text(
              'Cannot load the map right now.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Tree markers could not be fetched from the server. '
              'Check the connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, color: kMutedFg.withOpacity(0.9)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
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
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          HealthBadge(tree.healthStatus, small: true),
                          if ((tree.barangay ?? '').isNotEmpty)
                            _MapInfoPill(Icons.location_on_outlined,
                                tree.barangay!),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if ((tree.barangay ?? '').isNotEmpty) tree.barangay,
                      if ((tree.city ?? '').isNotEmpty) tree.city,
                      if ((tree.province ?? '').isNotEmpty) tree.province,
                    ].whereType<String>().join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${tree.lat?.toStringAsFixed(4)}, ${tree.lng?.toStringAsFixed(4)}',
                    style: const TextStyle(color: kMutedFg, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final role = context.read<AuthProvider>().user?.role;
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => role == 'citizen'
                          ? PublicTreeProfileScreen(treeId: tree.id)
                          : TreeDetailScreen(treeId: tree.id),
                    ),
                  );
                  if (changed == true) _load();
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

class _MapInfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MapInfoPill(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: kMutedFg),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 145),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: kMutedFg, fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
