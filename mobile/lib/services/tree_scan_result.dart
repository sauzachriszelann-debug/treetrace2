import 'dart:io';

/// Reviewed results only; a missing measurement never becomes zero.
class TreeScanResult {
  final Map<String, dynamic>? species;
  final Map<String, dynamic>? dbh;
  final double? heightMeters;
  final Map<String, dynamic>? heightResult;
  final File? photo;
  final bool measurementSkipped;
  final bool saveRequested;
  final String? reviewedCommonName;
  final String? reviewedScientificName;
  final double? reviewedDbhCm;
  final double? reviewedHeightMeters;
  const TreeScanResult(
      {this.species,
      this.dbh,
      this.heightMeters,
      this.heightResult,
      this.photo,
      this.measurementSkipped = false,
      this.saveRequested = false,
      this.reviewedCommonName,
      this.reviewedScientificName,
      this.reviewedDbhCm,
      this.reviewedHeightMeters});

  bool get hasResults =>
      species != null ||
      dbh != null ||
      heightMeters != null ||
      photo != null ||
      (reviewedCommonName?.isNotEmpty ?? false) ||
      (reviewedScientificName?.isNotEmpty ?? false) ||
      reviewedDbhCm != null ||
      reviewedHeightMeters != null;
}
