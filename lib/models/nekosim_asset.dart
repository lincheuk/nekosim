class NekoSimAsset {
  final String id;
  final String phoneNumber;
  final String countryCode;
  final String countryName;
  final String operatorName;
  final String iccid;
  final String eid;
  final String smdpAddress;
  final String activationCode;
  final DateTime? expireDate;
  final DateTime? startDate;
  final int renewalCycleDays;
  final String balanceNote;
  final String note;
  final String linkedProfileIccid;
  final String source;
  final int createdAt;
  final int updatedAt;

  const NekoSimAsset({
    required this.id,
    this.phoneNumber = '',
    this.countryCode = '',
    this.countryName = '',
    this.operatorName = '',
    this.iccid = '',
    this.eid = '',
    this.smdpAddress = '',
    this.activationCode = '',
    this.expireDate,
    this.startDate,
    this.renewalCycleDays = 30,
    this.balanceNote = '',
    this.note = '',
    this.linkedProfileIccid = '',
    this.source = 'manual',
    required this.createdAt,
    required this.updatedAt,
  });

  factory NekoSimAsset.empty() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return NekoSimAsset(id: now.toString(), createdAt: now, updatedAt: now);
  }

  int? get daysLeft {
    if (expireDate == null) return null;
    final today = DateTime.now();
    final a = DateTime(today.year, today.month, today.day);
    final b = DateTime(expireDate!.year, expireDate!.month, expireDate!.day);
    return b.difference(a).inDays;
  }

  bool get isExpired => (daysLeft ?? 1) < 0;
  bool get isDueSoon => daysLeft != null && daysLeft! >= 0 && daysLeft! <= 7;

  NekoSimAsset copyWith({
    String? id,
    String? phoneNumber,
    String? countryCode,
    String? countryName,
    String? operatorName,
    String? iccid,
    String? eid,
    String? smdpAddress,
    String? activationCode,
    DateTime? expireDate,
    bool clearExpireDate = false,
    DateTime? startDate,
    bool clearStartDate = false,
    int? renewalCycleDays,
    String? balanceNote,
    String? note,
    String? linkedProfileIccid,
    String? source,
    int? createdAt,
    int? updatedAt,
  }) {
    return NekoSimAsset(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      operatorName: operatorName ?? this.operatorName,
      iccid: iccid ?? this.iccid,
      eid: eid ?? this.eid,
      smdpAddress: smdpAddress ?? this.smdpAddress,
      activationCode: activationCode ?? this.activationCode,
      expireDate: clearExpireDate ? null : (expireDate ?? this.expireDate),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      renewalCycleDays: renewalCycleDays ?? this.renewalCycleDays,
      balanceNote: balanceNote ?? this.balanceNote,
      note: note ?? this.note,
      linkedProfileIccid: linkedProfileIccid ?? this.linkedProfileIccid,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'phoneNumber': phoneNumber,
    'countryCode': countryCode,
    'countryName': countryName,
    'operatorName': operatorName,
    'iccid': iccid,
    'eid': eid,
    'smdpAddress': smdpAddress,
    'activationCode': activationCode,
    'expireDate': expireDate?.millisecondsSinceEpoch,
    'startDate': startDate?.millisecondsSinceEpoch,
    'renewalCycleDays': renewalCycleDays,
    'balanceNote': balanceNote,
    'note': note,
    'linkedProfileIccid': linkedProfileIccid,
    'source': source,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory NekoSimAsset.fromMap(Map<String, dynamic> map) {
    DateTime? dt(Object? value) {
      if (value == null) return null;
      final n = value is int ? value : int.tryParse(value.toString());
      if (n == null || n <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(n);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    return NekoSimAsset(
      id: (map['id'] ?? now.toString()).toString(),
      phoneNumber: (map['phoneNumber'] ?? '').toString(),
      countryCode: (map['countryCode'] ?? '').toString(),
      countryName: (map['countryName'] ?? '').toString(),
      operatorName: (map['operatorName'] ?? '').toString(),
      iccid: (map['iccid'] ?? '').toString(),
      eid: (map['eid'] ?? '').toString(),
      smdpAddress: (map['smdpAddress'] ?? '').toString(),
      activationCode: (map['activationCode'] ?? '').toString(),
      expireDate: dt(map['expireDate']),
      startDate: dt(map['startDate']),
      renewalCycleDays:
          int.tryParse((map['renewalCycleDays'] ?? '30').toString()) ?? 30,
      balanceNote: (map['balanceNote'] ?? '').toString(),
      note: (map['note'] ?? '').toString(),
      linkedProfileIccid: (map['linkedProfileIccid'] ?? '').toString(),
      source: (map['source'] ?? 'manual').toString(),
      createdAt: int.tryParse((map['createdAt'] ?? now).toString()) ?? now,
      updatedAt: int.tryParse((map['updatedAt'] ?? now).toString()) ?? now,
    );
  }
}
