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
  final double? lat;
  final double? lng;
  final String? photoUrl;
  final String? qrCodeUrl;
  final String? notes;
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
    this.lat,
    this.lng,
    this.photoUrl,
    this.qrCodeUrl,
    this.notes,
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
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        photoUrl: j['photo_url'],
        qrCodeUrl: j['qr_code_url'],
        notes: j['notes'],
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

  UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isActive,
    required this.subscriptionPlan,
    required this.upgradeRequested,
    required this.aiIdentificationsToday,
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
      );

  UserModel copyWith({
    String? subscriptionPlan,
    bool? upgradeRequested,
    int? aiIdentificationsToday,
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
      );

  bool get isAdmin => role.toLowerCase().contains('admin');
  bool get isInstitutional => role == 'admin' || role == 'field_worker';
  bool get isPro => subscriptionPlan == 'pro';
}
