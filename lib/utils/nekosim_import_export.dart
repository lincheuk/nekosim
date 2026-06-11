import 'dart:convert';

import '../models/nekosim_asset.dart';

/// JSON / CSV import-export for NekoSim assets.
///
/// Accepts both NekoSim's own export format and legacy SimJiang exports
/// (san-sim-export v2: number/operator/expireDate/eid/smdp/activationCode...).
class NekoSimImportExport {
  static const List<String> csvHeader = [
    'id',
    'phoneNumber',
    'countryCode',
    'countryName',
    'operatorName',
    'iccid',
    'eid',
    'smdpAddress',
    'activationCode',
    'expireDate',
    'startDate',
    'renewalCycleDays',
    'balanceNote',
    'note',
    'linkedProfileIccid',
    'source',
  ];

  // -------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------

  static String exportJson(List<NekoSimAsset> assets) {
    return const JsonEncoder.withIndent('  ').convert({
      'type': 'nekosim-export',
      'version': 1,
      'count': assets.length,
      'records': assets.map(_assetToJson).toList(),
    });
  }

  static String exportCsv(List<NekoSimAsset> assets) {
    final buf = StringBuffer()..writeln(_csvLine(csvHeader));
    for (final a in assets) {
      final m = _assetToJson(a);
      buf.writeln(_csvLine(csvHeader.map((k) => '${m[k] ?? ''}').toList()));
    }
    return buf.toString();
  }

  static Map<String, dynamic> _assetToJson(NekoSimAsset a) => {
        'id': a.id,
        'phoneNumber': a.phoneNumber,
        'countryCode': a.countryCode,
        'countryName': a.countryName,
        'operatorName': a.operatorName,
        'iccid': a.iccid,
        'eid': a.eid,
        'smdpAddress': a.smdpAddress,
        'activationCode': a.activationCode,
        'expireDate': _fmtDate(a.expireDate),
        'startDate': _fmtDate(a.startDate),
        'renewalCycleDays': a.renewalCycleDays,
        'balanceNote': a.balanceNote,
        'note': a.note,
        'linkedProfileIccid': a.linkedProfileIccid,
        'source': a.source,
      };

  static String _fmtDate(DateTime? d) => d == null
      ? ''
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _csvEscape(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  static String _csvLine(List<String> values) =>
      values.map(_csvEscape).join(',');

  // -------------------------------------------------------------------
  // Import
  // -------------------------------------------------------------------

  /// Parse JSON first, fall back to CSV. Returns empty list when nothing
  /// could be recognized.
  static List<NekoSimAsset> parseAny(String text) {
    final fromJson = _parseJson(text);
    if (fromJson.isNotEmpty) return fromJson;
    return _parseCsv(text);
  }

  static List<NekoSimAsset> _parseJson(String text) {
    try {
      final trimmed = text.trim();
      dynamic root = jsonDecode(trimmed);
      List<dynamic> records;
      if (root is List) {
        records = root;
      } else if (root is Map && root['records'] is List) {
        records = root['records'] as List;
      } else {
        return const [];
      }
      return records
          .whereType<Map>()
          .map((m) => _recordFromMap(m.cast<String, dynamic>()))
          .whereType<NekoSimAsset>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<NekoSimAsset> _parseCsv(String text) {
    try {
      final rows = _parseCsvRows(text);
      if (rows.length < 2) return const [];
      final header = rows.first.map((h) => h.trim()).toList();
      final out = <NekoSimAsset>[];
      for (final vals in rows.skip(1)) {
        final map = <String, dynamic>{};
        for (var i = 0; i < header.length && i < vals.length; i++) {
          map[header[i]] = vals[i];
        }
        final asset = _recordFromMap(map);
        if (asset != null) out.add(asset);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Full-text CSV tokenizer (RFC 4180 style): quoted fields may contain
  /// commas, escaped quotes ("") and newlines, so rows cannot be split on
  /// line breaks up front.
  static List<List<String>> _parseCsvRows(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final sb = StringBuffer();
    var quoted = false;

    void endField() {
      row.add(sb.toString());
      sb.clear();
    }

    void endRow() {
      endField();
      if (row.length > 1 || row.first.trim().isNotEmpty) rows.add(row);
      row = <String>[];
    }

    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          sb.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == ',') {
        endField();
      } else if (ch == '\r') {
        if (i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
      } else if (ch == '\n') {
        endRow();
      } else {
        sb.write(ch);
      }
      i++;
    }
    if (sb.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  /// Maps both NekoSim fields and legacy SimJiang fields.
  static NekoSimAsset? _recordFromMap(Map<String, dynamic> m) {
    String s(List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
      }
      return '';
    }

    final phone = s(['phoneNumber', 'number']);
    final iccid = s(['iccid']);
    final activation = s(['activationCode']);
    final smdp = s(['smdpAddress', 'smdp']);
    if (phone.isEmpty && iccid.isEmpty && activation.isEmpty && smdp.isEmpty) {
      return null;
    }

    DateTime? date(List<String> keys) {
      final raw = s(keys);
      if (raw.isEmpty) return null;
      return DateTime.tryParse(raw.length > 10 ? raw.substring(0, 10) : raw);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = s(['id']).isNotEmpty ? s(['id']) : '$now-${phone.isNotEmpty ? phone : iccid}';
    return NekoSimAsset(
      id: id,
      phoneNumber: phone,
      countryCode: s(['countryCode']),
      countryName: s(['countryName']),
      operatorName: s(['operatorName', 'operator']),
      iccid: iccid,
      eid: s(['eid']),
      smdpAddress: smdp,
      activationCode: activation,
      expireDate: date(['expireDate']),
      startDate: date(['startDate']),
      renewalCycleDays: int.tryParse(s(['renewalCycleDays', 'cycleDays'])) ?? 30,
      balanceNote: s(['balanceNote', 'balance']),
      note: s(['note']),
      linkedProfileIccid: s(['linkedProfileIccid']),
      source: s(['source']).isNotEmpty ? s(['source']) : 'imported',
      createdAt: now,
      updatedAt: now,
    );
  }
}
