import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/theme.dart';
import '../models/models.dart';

// ── Health Badge — matches web app exactly ────────────────────────────────────
class HealthBadge extends StatelessWidget {
  final String status;
  final bool small;
  final Color? color; // Added support for custom colors

  const HealthBadge(this.status, {super.key, this.small = false, this.color});

  @override
  Widget build(BuildContext context) {
    final displayColor = color ?? healthColor(status);
    final bg    = displayColor.withOpacity(0.1);
    final border= displayColor.withOpacity(0.3);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 8 : 10, vertical: small ? 3 : 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: small ? 6 : 7,
          height: small ? 6 : 7,
          decoration: BoxDecoration(color: displayColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(status,
            style: TextStyle(
                color: displayColor,
                fontSize: small ? 11 : 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Tree Photo ────────────────────────────────────────────────────────────────
class TreePhoto extends StatelessWidget {
  final String? url;
  final double size;
  final BorderRadius? radius;
  final double? width;
  final double? height;
  const TreePhoto({super.key, this.url, this.size = 56, this.radius,
    this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final br = radius ?? BorderRadius.circular(10);
    final w  = width  ?? size;
    final h  = height ?? size;
    if (url == null || url!.isEmpty) {
      return Container(
        width: w, height: h,
        decoration: BoxDecoration(
          color: kPrimary.withOpacity(0.08),
          borderRadius: br,
          border: Border.all(color: kBorder),
        ),
        child: Icon(Icons.park_outlined,
            color: kPrimary.withOpacity(0.4), size: size * 0.42),
      );
    }
    return ClipRRect(
      borderRadius: br,
      child: CachedNetworkImage(
        imageUrl: url!, width: w, height: h, fit: BoxFit.cover,
        placeholder: (_, __) => Shimmer.fromColors(
          baseColor: kMuted,
          highlightColor: Colors.white,
          child: Container(color: Colors.white, width: w, height: h),
        ),
        errorWidget: (_, __, ___) => Container(
          width: w, height: h,
          color: kPrimary.withOpacity(0.08),
          child: Icon(Icons.park_outlined,
              color: kPrimary.withOpacity(0.4), size: size * 0.42),
        ),
      ),
    );
  }
}

// ── Stats Card — matches web StatsCard exactly ────────────────────────────────
class StatsCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  const StatsCard({super.key, required this.title, required this.value,
    this.subtitle, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: kMutedFg, fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(value,
                    style: GoogleFonts.inter(
                        fontSize: 26, fontWeight: FontWeight.w700,
                        color: kForeground)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(
                          color: kMutedFg, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
        ]),
      ]),
    );
  }
}

// ── Tree List Item — matches web TreeCard ─────────────────────────────────────
class TreeListItem extends StatelessWidget {
  final TreeModel tree;
  final VoidCallback? onTap;
  const TreeListItem({super.key, required this.tree, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Row(children: [
          TreePhoto(url: tree.photoUrl, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tree.commonName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14,
                        color: kForeground),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (tree.scientificName != null && tree.scientificName!.isNotEmpty)
                  Text(tree.scientificName!,
                      style: const TextStyle(
                          fontSize: 12, color: kMutedFg,
                          fontStyle: FontStyle.italic),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(children: [
                  if (tree.barangay != null) ...[
                    const Icon(Icons.location_on_outlined,
                        size: 11, color: kMutedFg),
                    const SizedBox(width: 2),
                    Flexible(child: Text(tree.barangay!,
                        style: const TextStyle(
                            fontSize: 11, color: kMutedFg),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                  ],
                  if (tree.dbhCm != null)
                    Text('DBH ${tree.dbhCm!.toStringAsFixed(0)} cm',
                        style: const TextStyle(fontSize: 11, color: kMutedFg)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            HealthBadge(tree.healthStatus, small: true),
            const SizedBox(height: 4),
            const Icon(Icons.chevron_right, size: 16, color: kMutedFg),
          ]),
        ]),
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionHeader(this.title, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
      child: Row(children: [
        Text(title,
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w700,
                color: kForeground)),
        const Spacer(),
        if (action != null) action!,
      ]),
    );
  }
}

// ── Loading shimmer ───────────────────────────────────────────────────────────
class LoadingList extends StatelessWidget {
  final int count;
  const LoadingList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: kMuted,
      highlightColor: Colors.white,
      child: Column(
        children: List.generate(count, (_) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 76,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14)),
        )),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final String message;
  final String? subtitle;
  final IconData icon;
  final Widget? action;
  const EmptyState({super.key, required this.message, this.subtitle,
    this.icon = Icons.park_outlined, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: kMutedFg.withOpacity(0.4)),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: kForeground,
                  fontSize: 15, fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMutedFg, fontSize: 13)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}
