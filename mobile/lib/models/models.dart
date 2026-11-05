// ── Tree Model ────────────────────────────────────────────────────────────────
class TreeModel {
  final int id;
  final String commonName;
  final String? scientificName;
  final double? dbhCm;
  final double? heightM;
  final double? carbonKg;
  final String healthStatus;
  final String? barangay;
  final String? city;
  final String? province;
  final double? lat;
  final double? lng;
  final String? photoUrl;
  final String? qrCodeUrl;
  final String? notes;
  final String endangeredStatus;
  final String statusCode;
  final bool isProtected;
  final bool cuttingAllowed;
  final DateTime? createdAt;

  TreeModel({
    required this.id,
    required this.commonName,
    this.scientificName,
    this.dbhCm,
    this.heightM,
    this.carbonKg,
    required this.healthStatus,
    this.barangay,
    this.city,
    this.province,
    this.lat,
    this.lng,
    this.photoUrl,
    this.qrCodeUrl,
    this.notes,
    this.endangeredStatus = 'Not Listed',
    this.statusCode = 'NL',
    this.isProtected = false,
    this.cuttingAllowed = true,
    this.createdAt,
  });

  factory TreeModel.fromJson(Map<String, dynamic> j) => TreeModel(
        id: j['id'],
        commonName: j['common_name'] ?? '',
        scientificName: j['scientific_name'],
        dbhCm: (j['dbh_cm'] as num?)?.toDouble(),
        heightM: (j['height_m'] as num?)?.toDouble(),
        carbonKg: (j['carbon_kg'] as num?)?.toDouble(),
        healthStatus: j['health_status'] ?? 'Healthy',
        barangay: j['barangay'],
        city: j['city'],
        province: j['province'],
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        photoUrl: j['photo_url'],
        qrCodeUrl: j['qr_code_url'],
        notes: j['notes'],
        endangeredStatus: j['endangered_status'] ?? 'Not Listed',
        statusCode: j['status_code'] ?? 'NL',
        isProtected: j['protected'] == true,
        cuttingAllowed: j['cutting_allowed'] != false,
        createdAt:
            j['created_at'] != null ? DateTime.tryParse(j['created_at']) : null,
      );

  Map<String, dynamic> toJson() => {
        'common_name': commonName,
        'scientific_name': scientificName,
        'dbh_cm': dbhCm,
        'height_m': heightM,
        'health_status': healthStatus,
        'barangay': barangay,
        'city': city,
        'province': province,
        'lat': lat,
        'lng': lng,
        'photo_url': photoUrl,
        'notes': notes,
      };
}

// ── Health Log Model ──────────────────────────────────────────────────────────
class HealthLogModel {
  final int id;
  final int treeId;
  final String condition;
  final String? notes;
  final String assessedDate;
  final double? dbhCm;
  final double? heightM;
  final String? photoUrl;
  final String? assessedBy;
  final String? treeCommonName;

  HealthLogModel({
    required this.id,
    required this.treeId,
    required this.condition,
    this.notes,
    required this.assessedDate,
    this.dbhCm,
    this.heightM,
    this.photoUrl,
    this.assessedBy,
    this.treeCommonName,
  });

  factory HealthLogModel.fromJson(Map<String, dynamic> j) => HealthLogModel(
        id: j['id'],
        treeId: j['tree_id'],
        condition: j['condition'] ?? 'Healthy',
        notes: j['notes'],
        assessedDate: j['assessed_date'] ?? '',
        dbhCm: (j['dbh_cm'] as num?)?.toDouble(),
        heightM: (j['height_m'] as num?)?.toDouble(),
        photoUrl: j['photo_url'],
        assessedBy: j['assessed_by'],
        treeCommonName: j['tree_common_name'],
      );
}

// ── User Model ────────────────────────────────────────────────────────────────
class UserModel {
  final int id;
  final String fullName;
  final String email;
  final String role;
  final bool isActive;
  final String subscriptionPlan;
  final bool upgradeRequested;
  final int aiIdentificationsToday;
  final int unknownSubmissionsToday;

  UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isActive,
    required this.subscriptionPlan,
    required this.upgradeRequested,
    required this.aiIdentificationsToday,
    required this.unknownSubmissionsToday,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id: j['id'],
        fullName: j['full_name'] ?? '',
        email: j['email'] ?? '',
        role: j['role'] ?? 'field_worker',
        isActive: j['is_active'] ?? true,
        subscriptionPlan: j['subscription_plan'] ?? 'free',
        upgradeRequested: j['upgrade_requested'] ?? false,
        aiIdentificationsToday: j['ai_identifications_today'] ?? 0,
        unknownSubmissionsToday: j['unknown_submissions_today'] ?? 0,
      );

  UserModel copyWith({
    String? subscriptionPlan,
    bool? upgradeRequested,
    int? aiIdentificationsToday,
    int? unknownSubmissionsToday,
  }) =>
      UserModel(
        id: id,
        fullName: fullName,
        email: email,
        role: role,
        isActive: isActive,
        subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
        upgradeRequested: upgradeRequested ?? this.upgradeRequested,
        aiIdentificationsToday:
            aiIdentificationsToday ?? this.aiIdentificationsToday,
        unknownSubmissionsToday:
            unknownSubmissionsToday ?? this.unknownSubmissionsToday,
      );

  bool get isAdmin => role.toLowerCase().contains('admin');
  bool get isInstitutional => role == 'admin' || role == 'field_worker';
  bool get isPro => subscriptionPlan == 'pro';
  bool get isEnterprise => subscriptionPlan == 'enterprise';
}

class UnknownSpeciesModel {
  final int id;
  final String? photoUrl;
  final String? barangay;
  final String? locationDescription;
  final String? possibleName;
  final String? identifiedAs;
  final String? reviewNotes;
  final String? submitterNotes;
  final String? submittedByName;
  final String? submittedByEmail;
  final String reviewStatus;
  final List<dynamic> aiCandidates;
  final bool reviewed;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UnknownSpeciesModel({
    required this.id,
    this.photoUrl,
    this.barangay,
    this.locationDescription,
    this.possibleName,
    this.identifiedAs,
    this.reviewNotes,
    this.submitterNotes,
    this.submittedByName,
    this.submittedByEmail,
    this.reviewStatus = 'pending',
    this.aiCandidates = const [],
    required this.reviewed,
    this.createdAt,
    this.updatedAt,
  });

  factory UnknownSpeciesModel.fromJson(Map<String, dynamic> j) =>
      UnknownSpeciesModel(
        id: j['id'],
        photoUrl: j['photo_url'],
        barangay: j['barangay'],
        locationDescription: j['location_description'],
        possibleName: j['possible_name'],
        identifiedAs: j['identified_as'],
        reviewNotes: j['review_notes'],
        submitterNotes: j['submitter_notes'],
        submittedByName: j['submitted_by_name'],
        submittedByEmail: j['submitted_by_email'],
        reviewStatus: j['review_status'] ??
            (j['reviewed'] == true
                ? (j['identified_as'] == null || j['identified_as'] == ''
                    ? 'closed'
                    : 'identified')
                : 'pending'),
        aiCandidates: j['ai_candidates'] is List
            ? List<dynamic>.from(j['ai_candidates'] as List)
            : const [],
        reviewed: j['reviewed'] == true,
        createdAt:
            j['created_at'] != null ? DateTime.tryParse(j['created_at']) : null,
        updatedAt:
            j['updated_at'] != null ? DateTime.tryParse(j['updated_at']) : null,
      );
}

class TreeSubmissionModel {
  final int id;
  final String status;
  final String? source;
  final String? commonName;
  final String? scientificName;
  final double? dbhCm;
  final double? heightM;
  final String? healthStatus;
  final String? barangay;
  final String? city;
  final String? province;
  final double? lat;
  final double? lng;
  final String? photoUrl;
  final String? dateRecorded;
  final String? notes;
  final List<dynamic> aiCandidates;
  final Map<String, dynamic>? reviewOverrides;
  final String? reviewedByName;
  final String? reviewReason;
  final DateTime? reviewedAt;
  final int? approvedTreeId;
  final int? sourceUnknownSpeciesId;
  final String? submittedByName;
  final String? submittedByEmail;
  final DateTime? createdAt;

  const TreeSubmissionModel({
    required this.id,
    required this.status,
    this.source,
    this.commonName,
    this.scientificName,
    this.dbhCm,
    this.heightM,
    this.healthStatus,
    this.barangay,
    this.city,
    this.province,
    this.lat,
    this.lng,
    this.photoUrl,
    this.dateRecorded,
    this.notes,
    this.aiCandidates = const [],
    this.reviewOverrides,
    this.reviewedByName,
    this.reviewReason,
    this.reviewedAt,
    this.approvedTreeId,
    this.sourceUnknownSpeciesId,
    this.submittedByName,
    this.submittedByEmail,
    this.createdAt,
  });

  factory TreeSubmissionModel.fromJson(Map<String, dynamic> json) {
    final rawOverrides = json['review_overrides'];
    return TreeSubmissionModel(
      id: (json['id'] as num).toInt(),
      status: '${json['status'] ?? json['review_status'] ?? 'pending'}',
      source: json['source']?.toString(),
      commonName: json['common_name']?.toString(),
      scientificName: json['scientific_name']?.toString(),
      dbhCm: (json['dbh_cm'] as num?)?.toDouble(),
      heightM: (json['height_m'] as num?)?.toDouble(),
      healthStatus: json['health_status']?.toString(),
      barangay: json['barangay']?.toString(),
      city: json['city']?.toString(),
      province: json['province']?.toString(),
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      photoUrl: json['photo_url']?.toString(),
      dateRecorded: json['date_recorded']?.toString(),
      notes: json['notes']?.toString(),
      aiCandidates: json['ai_candidates'] is List
          ? List<dynamic>.from(json['ai_candidates'] as List)
          : const [],
      reviewOverrides:
          rawOverrides is Map ? Map<String, dynamic>.from(rawOverrides) : null,
      reviewedByName: json['reviewed_by_name']?.toString(),
      reviewReason: json['review_reason']?.toString(),
      reviewedAt: json['reviewed_at'] is String
          ? DateTime.tryParse(json['reviewed_at'] as String)
          : null,
      approvedTreeId: (json['approved_tree_id'] as num?)?.toInt(),
      sourceUnknownSpeciesId:
          (json['source_unknown_species_id'] as num?)?.toInt(),
      submittedByName: json['submitted_by_name']?.toString(),
      submittedByEmail: json['submitted_by_email']?.toString(),
      createdAt: json['created_at'] is String
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

class PlantingRecommendationModel {
  final int id;
  final String speciesName;
  final String? scientificName;
  final String? barangay;
  final String? reason;
  final String? photoUrl;
  final String status;
  final bool planted;
  final DateTime? createdAt;

  PlantingRecommendationModel({
    required this.id,
    required this.speciesName,
    this.scientificName,
    this.barangay,
    this.reason,
    this.photoUrl,
    required this.status,
    required this.planted,
    this.createdAt,
  });

  factory PlantingRecommendationModel.fromJson(Map<String, dynamic> j) =>
      PlantingRecommendationModel(
        id: j['id'],
        speciesName: j['species_name'] ?? '',
        scientificName: j['scientific_name'],
        barangay: j['barangay'],
        reason: j['reason'],
        photoUrl: j['photo_url'],
        status: j['status'] ?? 'recommended',
        planted: j['planted'] == true,
        createdAt:
            j['created_at'] != null ? DateTime.tryParse(j['created_at']) : null,
      );
}
