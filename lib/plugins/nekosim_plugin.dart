import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'plugin_base.dart';
import '../models/euicc_profile.dart';
import '../models/profile_card_bottom_data.dart';
import '../services/nekosim_asset_service.dart';

/// Bridges NekoSim assets into the host profile pipeline.
///
/// - onProfilesLoaded: silently refresh linked assets (operator / eid backfill)
/// - isMatch + getProfileCardBottomData: show asset info (phone number,
///   renewal date) directly on the eSIM profile card
class NekoSimPlugin extends ProfilePlugin {
  final NekoSimAssetService _service = NekoSimAssetService();

  @override
  String get id => 'nekosim';

  @override
  String get name => 'NekoSim Assets';

  @override
  bool isMatch(EuiccProfile profile) {
    return _service.isCacheWarm && _service.cachedByIccid(profile.iccid) != null;
  }

  @override
  Future<void> onProfilesLoaded(
    String eid,
    List<EuiccProfile> profiles, {
    VoidCallback? onUpdate,
  }) async {
    await _service.init();
    await _service.syncFromProfiles(eid, profiles);
    onUpdate?.call();
  }

  @override
  ProfileCardBottomData? getProfileCardBottomData(EuiccProfile profile) {
    final asset = _service.cachedByIccid(profile.iccid);
    if (asset == null) return null;
    final expiry = asset.expireDate;
    final days = asset.daysLeft;
    String? lineExpiry;
    if (expiry != null) {
      final dateStr = DateFormat('yyyy-MM-dd').format(expiry);
      lineExpiry = days == null
          ? dateStr
          : days < 0
              ? '$dateStr (expired)'
              : '$dateStr (${days}d left)';
    }
    final data = ProfileCardBottomData(
      themeColor: asset.isExpired
          ? Colors.red
          : asset.isDueSoon
              ? Colors.orange
              : Colors.teal,
      phoneNumber: asset.phoneNumber.isNotEmpty ? asset.phoneNumber : null,
      lineExpiry: lineExpiry,
      balance: asset.balanceNote.isNotEmpty ? asset.balanceNote : null,
    );
    return data.isEmpty ? null : data;
  }
}
