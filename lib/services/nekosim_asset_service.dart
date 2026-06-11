import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import 'nekosim_cloud_service.dart';
import 'profile_metadata_service.dart';
import 'tag_notification_service.dart';
import '../models/euicc_profile.dart';
import '../models/nekosim_asset.dart';

/// Lightweight status of the eUICC profile linked to an asset.
class LinkedProfileStatus {
  final String iccid;
  final bool enabled;
  final DateTime lastSeen;
  const LinkedProfileStatus({
    required this.iccid,
    required this.enabled,
    required this.lastSeen,
  });
}

/// Single source of truth for NekoSim assets.
///
/// ChangeNotifier so UI (assets tab, profile cards) can react to changes
/// from either direction: asset edits or profile discovery.
class NekoSimAssetService extends ChangeNotifier {
  static final NekoSimAssetService _instance = NekoSimAssetService._internal();
  factory NekoSimAssetService() => _instance;
  NekoSimAssetService._internal();

  static final Logger _log = Logger('NekoSimAssetService');

  bool _tableEnsured = false;

  /// In-memory cache for synchronous lookups (plugin card hooks are sync).
  final Map<String, NekoSimAsset> _byIccid = {};
  List<NekoSimAsset> _all = const [];
  bool _cacheWarm = false;

  Future<Database> get _db async => DatabaseService().database;

  /// Call once at startup (cheap, idempotent).
  Future<void> init() async {
    await ensureTable();
    await _refreshCache(notify: false);
  }

  Future<void> ensureTable() async {
    if (_tableEnsured) return;
    final db = await _db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS nekosim_assets (
        id TEXT PRIMARY KEY,
        phoneNumber TEXT,
        countryCode TEXT,
        countryName TEXT,
        operatorName TEXT,
        iccid TEXT,
        eid TEXT,
        smdpAddress TEXT,
        activationCode TEXT,
        expireDate INTEGER,
        startDate INTEGER,
        renewalCycleDays INTEGER DEFAULT 30,
        balanceNote TEXT,
        note TEXT,
        linkedProfileIccid TEXT,
        source TEXT,
        createdAt INTEGER,
        updatedAt INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_nekosim_assets_expireDate ON nekosim_assets(expireDate)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_nekosim_assets_iccid ON nekosim_assets(iccid)',
    );
    _tableEnsured = true;
  }

  Future<void> _refreshCache({bool notify = true}) async {
    await ensureTable();
    final rows = await (await _db).query(
      'nekosim_assets',
      orderBy: 'expireDate IS NULL, expireDate ASC, updatedAt DESC',
    );
    _all = rows.map(NekoSimAsset.fromMap).toList(growable: false);
    _byIccid.clear();
    for (final a in _all) {
      if (a.linkedProfileIccid.isNotEmpty) _byIccid[a.linkedProfileIccid] = a;
      if (a.iccid.isNotEmpty) _byIccid.putIfAbsent(a.iccid, () => a);
    }
    _cacheWarm = true;
    if (notify) notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Synchronous cache access (for plugin hooks: isMatch / card bottom data)
  // ---------------------------------------------------------------------

  bool get isCacheWarm => _cacheWarm;
  List<NekoSimAsset> get cachedAssets => _all;
  NekoSimAsset? cachedByIccid(String iccid) => _byIccid[iccid];

  // ---------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------

  Future<List<NekoSimAsset>> getAll() async {
    if (!_cacheWarm) await _refreshCache(notify: false);
    return _all;
  }

  Future<NekoSimAsset?> getById(String id) async {
    final list = await getAll();
    for (final a in list) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<NekoSimAsset?> getByLinkedProfileIccid(String iccid) async {
    if (!_cacheWarm) await _refreshCache(notify: false);
    return _byIccid[iccid];
  }

  /// Status of linked profiles, joined from profile_metadata.
  /// Key: iccid. Missing key = profile no longer seen on any reader.
  Future<Map<String, LinkedProfileStatus>> getLinkedStatuses() async {
    final iccids = _all
        .map((a) => a.linkedProfileIccid.isNotEmpty ? a.linkedProfileIccid : a.iccid)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (iccids.isEmpty) return const {};
    final placeholders = List.filled(iccids.length, '?').join(',');
    final rows = await (await _db).query(
      'profile_metadata',
      columns: ['iccid', 'enabled', 'lastSeen'],
      where: 'iccid IN ($placeholders)',
      whereArgs: iccids,
    );
    return {
      for (final r in rows)
        (r['iccid'] as String): LinkedProfileStatus(
          iccid: r['iccid'] as String,
          enabled: r['enabled'] == 1,
          lastSeen: DateTime.fromMillisecondsSinceEpoch(
            (r['lastSeen'] as int?) ?? 0,
          ),
        ),
    };
  }

  // ---------------------------------------------------------------------
  // Mutations — all funnel through upsert/delete so cache + reminders stay
  // consistent and listeners fire exactly once per change.
  // ---------------------------------------------------------------------

  Future<void> upsert(NekoSimAsset asset) async {
    await ensureTable();
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalized = asset.copyWith(updatedAt: now);
    await (await _db).insert(
      'nekosim_assets',
      normalized.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _syncReminder(normalized);
    await _refreshCache();
    // Fire-and-forget cloud auto sync (no await on network).
    // ignore: unawaited_futures
    NekoSimCloudService().maybeAutoSync(_all);
  }

  Future<void> delete(String id) async {
    await ensureTable();
    final existing = await getById(id);
    await (await _db).delete('nekosim_assets', where: 'id = ?', whereArgs: [id]);
    if (existing != null && existing.expireDate != null) {
      try {
        await TagNotificationService().deleteNotification(
          _reminderText(existing),
          existing.expireDate!,
        );
      } catch (e) {
        _log.fine('Reminder cleanup skipped: $e');
      }
    }
    await _refreshCache();
    // ignore: unawaited_futures
    NekoSimCloudService().maybeAutoSync(_all);
  }

  Future<NekoSimAsset> renew(NekoSimAsset asset, int days) async {
    // Remove the old reminder before moving the date.
    if (asset.expireDate != null) {
      try {
        await TagNotificationService().deleteNotification(
          _reminderText(asset),
          asset.expireDate!,
        );
      } catch (_) {}
    }
    final base = asset.expireDate ?? DateTime.now();
    final renewed = asset.copyWith(expireDate: base.add(Duration(days: days)));
    await upsert(renewed);
    return renewed;
  }

  // ---------------------------------------------------------------------
  // Reminder bridge: reuse the host app's scheduled_notifications pipeline
  // instead of inventing a parallel reminder system.
  // ---------------------------------------------------------------------

  String _reminderText(NekoSimAsset asset) {
    final title = asset.operatorName.isNotEmpty
        ? asset.operatorName
        : asset.phoneNumber.isNotEmpty
            ? asset.phoneNumber
            : asset.iccid.isNotEmpty
                ? asset.iccid
                : asset.id;
    return 'NekoSim renewal: $title';
  }

  Future<void> _syncReminder(NekoSimAsset asset) async {
    if (asset.expireDate == null) return;
    if (!asset.expireDate!.isAfter(DateTime.now())) return;
    try {
      await TagNotificationService().upsertNotification(
        ScheduledNotification(
          text: _reminderText(asset),
          scheduledDate: asset.expireDate!,
          iccid: asset.linkedProfileIccid.isNotEmpty
              ? asset.linkedProfileIccid
              : asset.iccid,
          lastUpdated: DateTime.now(),
          eid: asset.eid.isNotEmpty ? asset.eid : null,
        ),
      );
    } catch (e) {
      _log.warning('Failed to sync renewal reminder: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Profile-side integration
  // ---------------------------------------------------------------------

  Future<NekoSimAsset> createFromProfile(EuiccProfile profile, {String? eid}) async {
    final existing = await getByLinkedProfileIccid(profile.iccid);
    final now = DateTime.now().millisecondsSinceEpoch;
    final asset = (existing ?? NekoSimAsset.empty()).copyWith(
      iccid: profile.iccid,
      linkedProfileIccid: profile.iccid,
      eid: (eid != null && eid.isNotEmpty) ? eid : existing?.eid ?? '',
      countryCode: profile.flag,
      operatorName: profile.displayName,
      smdpAddress: profile.smdpAddress ?? existing?.smdpAddress ?? '',
      note: existing?.note.isNotEmpty == true
          ? existing!.note
          : 'Linked from installed eSIM profile',
      source: 'nekoko_profile',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await upsert(asset);
    return asset;
  }

  Future<NekoSimAsset> createFromProfileMetadata(ProfileMetadata profile) async {
    final existing = await getByLinkedProfileIccid(profile.iccid);
    final now = DateTime.now().millisecondsSinceEpoch;
    final asset = (existing ?? NekoSimAsset.empty()).copyWith(
      iccid: profile.iccid,
      linkedProfileIccid: profile.iccid,
      eid: profile.eid ?? existing?.eid ?? '',
      countryCode: profile.flag,
      operatorName: profile.displayName,
      note: existing?.note.isNotEmpty == true
          ? existing!.note
          : 'Linked from profile metadata',
      source: 'profile_metadata',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await upsert(asset);
    return asset;
  }

  /// Called when profiles load on a reader: quietly refresh linked assets
  /// (operator rename, eid backfill) without prompting.
  Future<void> syncFromProfiles(String? eid, List<EuiccProfile> profiles) async {
    if (!_cacheWarm) await _refreshCache(notify: false);
    var changed = false;
    for (final p in profiles) {
      final asset = _byIccid[p.iccid];
      if (asset == null) continue;
      final newOperator = p.displayName;
      final newEid = (eid != null && eid.isNotEmpty) ? eid : asset.eid;
      if (asset.operatorName != newOperator || asset.eid != newEid) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final updated = asset.copyWith(
          operatorName: newOperator,
          eid: newEid,
          updatedAt: now,
        );
        await (await _db).insert(
          'nekosim_assets',
          updated.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        changed = true;
      }
    }
    if (changed) await _refreshCache();
  }

  // ---------------------------------------------------------------------
  // LPA import
  // ---------------------------------------------------------------------

  Future<NekoSimAsset> createFromLpa(String lpaCode) async {
    final parsed = parseLpa(lpaCode);
    final asset = NekoSimAsset.empty().copyWith(
      smdpAddress: parsed.$1,
      activationCode: parsed.$2,
      note: lpaCode,
      source: 'lpa',
    );
    await upsert(asset);
    return asset;
  }

  (String, String) parseLpa(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return ('', '');
    final normalized = text.replaceFirst(RegExp(r'^lpa:', caseSensitive: false), 'LPA:');
    final parts = normalized.split(r'$');
    if (parts.length >= 3 && parts.first.toUpperCase().startsWith('LPA:')) {
      return (parts[1], parts.sublist(2).join(r'$'));
    }
    _log.fine('Could not parse as full LPA string, storing as activation code');
    return ('', text);
  }
}
