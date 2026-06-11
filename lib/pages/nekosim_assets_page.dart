import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/nekosim_strings.dart';
import '../models/nekosim_asset.dart';
import '../services/nekosim_asset_service.dart';
import '../services/profile_metadata_service.dart';
import '../settings/app_settings.dart';
import '../theme/app_theme.dart';
import '../utils/nekosim_import_export.dart';
import '../widgets/lpa_text_editing_controller.dart';
import '../widgets/nekosim_glass.dart';
import '../widgets/styled_header_scaffold.dart';
import '../utils/nekosim_qr_import.dart';
import '../utils/platform_adapter_io.dart'
    if (dart.library.js_interop) '../utils/platform_adapter_web.dart';
import 'nekosim_cloud_page.dart';
import 'qr_scanner_page.dart';

enum _AssetFilter { all, dueSoon, expired, unlinked }

enum _AssetSort { expirySoon, expiryLate, recentUpdated }

class NekoSimAssetsPage extends StatefulWidget {
  const NekoSimAssetsPage({super.key});

  @override
  State<NekoSimAssetsPage> createState() => _NekoSimAssetsPageState();
}

class _NekoSimAssetsPageState extends State<NekoSimAssetsPage> {
  final _service = NekoSimAssetService();
  final _searchController = TextEditingController();
  Map<String, LinkedProfileStatus> _statuses = const {};
  String _query = '';
  _AssetFilter _filter = _AssetFilter.all;
  _AssetSort _sort = _AssetSort.expirySoon;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _service.init().then((_) => _loadStatuses());
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
      _loadStatuses();
    }
  }

  Future<void> _loadStatuses() async {
    final statuses = await _service.getLinkedStatuses();
    if (mounted) setState(() => _statuses = statuses);
  }

  Future<void> _refresh() async {
    await _service.init();
    await _loadStatuses();
  }

  List<NekoSimAsset> _visibleAssets() {
    final q = _query.trim().toLowerCase();
    final list = _service.cachedAssets.where((a) {
      switch (_filter) {
        case _AssetFilter.dueSoon:
          if (!a.isDueSoon) return false;
        case _AssetFilter.expired:
          if (!a.isExpired) return false;
        case _AssetFilter.unlinked:
          if (a.linkedProfileIccid.isNotEmpty) return false;
        case _AssetFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      return [
        a.operatorName,
        a.phoneNumber,
        a.countryName,
        a.countryCode,
        a.iccid,
        a.eid,
        a.smdpAddress,
        a.balanceNote,
        a.note,
      ].any((f) => f.toLowerCase().contains(q));
    }).toList();

    int byExpiry(NekoSimAsset a, NekoSimAsset b, {required bool ascending}) {
      final da = a.expireDate;
      final db = b.expireDate;
      if (da == null && db == null) return b.updatedAt.compareTo(a.updatedAt);
      if (da == null) return 1; // no expiry sorts last either way
      if (db == null) return -1;
      final cmp = ascending ? da.compareTo(db) : db.compareTo(da);
      return cmp != 0 ? cmp : b.updatedAt.compareTo(a.updatedAt);
    }

    switch (_sort) {
      case _AssetSort.expirySoon:
        list.sort((a, b) => byExpiry(a, b, ascending: true));
      case _AssetSort.expiryLate:
        list.sort((a, b) => byExpiry(a, b, ascending: false));
      case _AssetSort.recentUpdated:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return list;
  }

  Future<void> _edit([NekoSimAsset? asset]) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NekoSimAssetEditPage(asset: asset ?? NekoSimAsset.empty()),
      ),
    );
  }

  Future<void> _importLpa() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => const _LpaImportDialog(),
    );
    if (value == null || value.trim().isEmpty) return;
    await _service.createFromLpa(value);
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(NekoSimStrings.of(context).copied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportData(bool csv) async {
    final t = NekoSimStrings.of(context);
    final assets = await _service.getAll();
    final content = csv
        ? NekoSimImportExport.exportCsv(assets)
        : NekoSimImportExport.exportJson(assets);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(csv ? t.exportCsv : t.exportJson),
        content: SizedBox(
          width: double.maxFinite,
          height: 280,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.copied), duration: const Duration(seconds: 2)),
              );
            },
            child: Text(t.copy),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        ],
      ),
    );
  }

  Future<void> _importData() async {
    final t = NekoSimStrings.of(context);
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.importData),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.importHint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              minLines: 6,
              maxLines: 10,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(t.import)),
        ],
      ),
    );
    if (value == null || value.trim().isEmpty) return;
    final records = NekoSimImportExport.parseAny(value);
    if (!mounted) return;
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.importFailed)),
      );
      return;
    }
    for (final r in records) {
      await _service.upsert(r);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.importedCount(records.length))),
      );
    }
  }

  Future<void> _confirmDelete(NekoSimAsset asset) async {
    final t = NekoSimStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.deleteAssetQ),
        content: Text(asset.displayTitle),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.delete)),
        ],
      ),
    );
    if (ok == true) {
      await _service.delete(asset.id);
    }
  }

  Widget _buildToolbar(NekoSimStrings t) {
    final theme = Theme.of(context);
    final filters = [
      (_AssetFilter.all, t.filterAll),
      (_AssetFilter.dueSoon, t.filterDueSoon),
      (_AssetFilter.expired, t.filterExpired),
      (_AssetFilter.unlinked, t.filterUnlinked),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GlassSurface(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: t.searchAssets,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          for (final (value, label) in filters) ...[
                            ChoiceChip(
                              label: Text(label),
                              selected: _filter == value,
                              visualDensity: VisualDensity.compact,
                              side: BorderSide(
                                color: theme.dividerColor
                                    .withValues(alpha: 0.2),
                              ),
                              onSelected: (_) =>
                                  setState(() => _filter = value),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<_AssetSort>(
                    icon: const Icon(Icons.sort_rounded),
                    initialValue: _sort,
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (context) => [
                      CheckedPopupMenuItem(
                        value: _AssetSort.expirySoon,
                        checked: _sort == _AssetSort.expirySoon,
                        child: Text(t.sortExpirySoon),
                      ),
                      CheckedPopupMenuItem(
                        value: _AssetSort.expiryLate,
                        checked: _sort == _AssetSort.expiryLate,
                        child: Text(t.sortExpiryLate),
                      ),
                      CheckedPopupMenuItem(
                        value: _AssetSort.recentUpdated,
                        checked: _sort == _AssetSort.recentUpdated,
                        child: Text(t.sortRecentUpdated),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = NekoSimStrings.of(context);
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: AppBar(
          leadingWidth: 200,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: Row(
              children: [
                Image.asset(AppSettings().logoAsset, height: 24),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppSettings().appName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                          height: 0.9,
                        ),
                      ),
                      Text(
                        t.tabAssets,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          actions: [
          IconButton(
            tooltip: t.importLpa,
            onPressed: _importLpa,
            icon: const Icon(Icons.qr_code_2_rounded),
          ),
          IconButton(
            tooltip: t.addAsset,
            onPressed: () => _edit(),
            icon: const Icon(Icons.add_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'cloud':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NekoSimCloudPage()),
                  );
                  break;
                case 'export_json':
                  _exportData(false);
                  break;
                case 'export_csv':
                  _exportData(true);
                  break;
                case 'import':
                  _importData();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'cloud',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(t.cloudReminders),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'export_json',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.data_object_rounded),
                  title: Text(t.exportJson),
                ),
              ),
              PopupMenuItem(
                value: 'export_csv',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.table_chart_outlined),
                  title: Text(t.exportCsv),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_rounded),
                  title: Text(t.importData),
                ),
              ),
            ],
          ),
          ],
        ),
      ),
      body: GlassAmbientBackground(
        child: Builder(
        builder: (context) {
          if (!_service.isCacheWarm) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = _service.cachedAssets;
          if (all.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                  Icon(Icons.sim_card_outlined, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(t.noAssets, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(t.noAssetsHint, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                ],
              ),
            );
          }
          final assets = _visibleAssets();
          return Column(
            children: [
              _buildToolbar(t),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: assets.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                            Icon(Icons.search_off_rounded, size: 48, color: theme.colorScheme.outline),
                            const SizedBox(height: 12),
                            Text(t.noMatches, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          itemCount: assets.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final asset = assets[index];
                            final linkedKey = asset.linkedProfileIccid.isNotEmpty
                                ? asset.linkedProfileIccid
                                : asset.iccid;
                            return _AssetCard(
                              asset: asset,
                              linkedStatus: linkedKey.isEmpty ? null : _statuses[linkedKey],
                              hasLink: linkedKey.isNotEmpty,
                              onTap: () => _edit(asset),
                              onRenew: (days) async {
                                await _service.renew(asset, days);
                              },
                              onCopy: _copyToClipboard,
                              onDelete: () => _confirmDelete(asset),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}

extension on NekoSimAsset {
  String get displayTitle {
    if (operatorName.isNotEmpty) return operatorName;
    if (phoneNumber.isNotEmpty) return phoneNumber;
    if (iccid.isNotEmpty) return 'ICCID $iccid';
    if (smdpAddress.isNotEmpty) return smdpAddress;
    return 'NekoSim Asset';
  }

  String get subtitle {
    final parts = <String>[];
    if (countryName.isNotEmpty) parts.add(countryName);
    if (countryCode.isNotEmpty && phoneNumber.isNotEmpty) parts.add('$countryCode $phoneNumber');
    if (iccid.isNotEmpty) parts.add('ICCID $iccid');
    if (eid.isNotEmpty) parts.add('EID $eid');
    return parts.join(' · ');
  }

  /// Activation string for clipboard: full LPA when SM-DP+ is known,
  /// otherwise the raw activation code. Empty when neither exists.
  String get lpaCode {
    if (smdpAddress.isNotEmpty) return 'LPA:1\$$smdpAddress\$$activationCode';
    return activationCode;
  }
}

class _AssetCard extends StatelessWidget {
  static const renewSteps = [7, 30, 90, 180, 365];

  final NekoSimAsset asset;
  final LinkedProfileStatus? linkedStatus;
  final bool hasLink;
  final VoidCallback onTap;
  final ValueChanged<int> onRenew;
  final ValueChanged<String> onCopy;
  final VoidCallback onDelete;

  const _AssetCard({
    required this.asset,
    required this.onTap,
    required this.onRenew,
    required this.onCopy,
    required this.onDelete,
    this.linkedStatus,
    this.hasLink = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = NekoSimStrings.of(context);
    final days = asset.daysLeft;
    final statusColor = asset.isExpired
        ? theme.colorScheme.error
        : asset.isDueSoon
            ? Colors.orange
            : theme.colorScheme.primary;
    final status = days == null
        ? t.noExpiry
        : days < 0
            ? t.expiredDays(-days)
            : t.dueInDays(days);

    return GlassCard(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: statusColor.withValues(alpha: 0.12),
                    child: Icon(Icons.sim_card_rounded, color: statusColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(asset.displayTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        if (asset.subtitle.isNotEmpty)
                          Text(asset.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Chip(label: Text(status), visualDensity: VisualDensity.compact),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'copy_number':
                          onCopy(asset.phoneNumber);
                          break;
                        case 'copy_iccid':
                          onCopy(asset.iccid);
                          break;
                        case 'copy_lpa':
                          onCopy(asset.lpaCode);
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'copy_number',
                        enabled: asset.phoneNumber.isNotEmpty,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.phone_rounded),
                          title: Text(t.copyNumber),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'copy_iccid',
                        enabled: asset.iccid.isNotEmpty,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.credit_card_rounded),
                          title: Text(t.copyIccid),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'copy_lpa',
                        enabled: asset.lpaCode.isNotEmpty,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.qr_code_2_rounded),
                          title: Text(t.copyLpa),
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                          title: Text(t.delete),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (asset.balanceNote.isNotEmpty || asset.note.isNotEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text([asset.balanceNote, asset.note].where((e) => e.isNotEmpty).join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
              ],
              if (hasLink) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      linkedStatus == null
                          ? Icons.link_off_rounded
                          : linkedStatus!.enabled
                              ? Icons.check_circle_rounded
                              : Icons.pause_circle_outline_rounded,
                      size: 16,
                      color: linkedStatus == null
                          ? theme.colorScheme.outline
                          : linkedStatus!.enabled
                              ? Colors.green
                              : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        linkedStatus == null
                            ? t.profileNotSeen
                            : '${linkedStatus!.enabled ? t.profileEnabled : t.profileDisabled} · ${t.lastSeen(_fmtLastSeen(t, linkedStatus!.lastSeen))}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final step in renewSteps)
                    ActionChip(
                      label: Text('+${step}d'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onRenew(step),
                    ),
                ],
              ),
            ],
          ),
        ),
    );
  }

  static String _fmtLastSeen(NekoSimStrings t, DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return t.timeUnknown;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return t.timeJustNow;
    if (diff.inHours < 1) return t.timeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return t.timeHoursAgo(diff.inHours);
    return t.timeDaysAgo(diff.inDays);
  }
}

/// LPA import dialog: paste / scan QR / decode from image, with a live
/// parse preview. Pops with the raw LPA text to import.
class _LpaImportDialog extends StatefulWidget {
  const _LpaImportDialog();

  @override
  State<_LpaImportDialog> createState() => _LpaImportDialogState();
}

class _LpaImportDialogState extends State<_LpaImportDialog> {
  final _controller = LpaTextEditingController();
  bool _decoding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty && mounted) {
      setState(() => _controller.text = text);
    }
  }

  Future<void> _scanQr() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerPage()),
    );
    if (code != null && mounted) {
      setState(() => _controller.text = code);
    }
  }

  Future<void> _pickImage() async {
    final t = NekoSimStrings.of(context);
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _decoding = true);
    final code = await decodeQrFromImagePath(path);
    if (!mounted) return;
    setState(() {
      _decoding = false;
      if (code != null) _controller.text = code;
    });
    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.noQrInImage)),
      );
    }
  }

  Widget _preview(ThemeData theme, NekoSimStrings t) {
    final text = _controller.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final (smdp, code) = NekoSimAssetService().parseLpa(text);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return Container(
      width: double.maxFinite,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (smdp.isNotEmpty)
            Text('SM-DP+: $smdp', style: mono, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (code.isNotEmpty)
            Text('${t.activationCode}: $code', style: mono, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = NekoSimStrings.of(context);
    final theme = Theme.of(context);
    final canScan = !PlatformX.isWindows && !PlatformX.isLinux;
    return AlertDialog(
      title: Text(t.importLpa),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            style: AppTheme.mono(const TextStyle(fontSize: 13)),
            decoration: InputDecoration(
              hintText: r'LPA:1$SM-DP+$ActivationCode',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                tooltip: t.pasteClipboard,
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _decoding ? null : _pasteClipboard,
              ),
              IconButton(
                tooltip: t.fromImage,
                icon: const Icon(Icons.image_outlined),
                onPressed: _decoding ? null : _pickImage,
              ),
              if (canScan)
                IconButton(
                  tooltip: t.scanQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  onPressed: _decoding ? null : _scanQr,
                ),
              if (_decoding) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          _preview(theme, t),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _controller.text),
          child: Text(t.import),
        ),
      ],
    );
  }
}

class NekoSimAssetEditPage extends StatefulWidget {
  final NekoSimAsset asset;
  const NekoSimAssetEditPage({super.key, required this.asset});

  @override
  State<NekoSimAssetEditPage> createState() => _NekoSimAssetEditPageState();
}

class _NekoSimAssetEditPageState extends State<NekoSimAssetEditPage> {
  late NekoSimAsset _asset;
  late final TextEditingController _phone;
  late final TextEditingController _countryCode;
  late final TextEditingController _countryName;
  late final TextEditingController _operator;
  late final TextEditingController _iccid;
  late final TextEditingController _eid;
  late final TextEditingController _smdp;
  late final TextEditingController _activation;
  late final TextEditingController _expire;
  late final TextEditingController _cycle;
  late final TextEditingController _balance;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _asset = widget.asset;
    _phone = TextEditingController(text: _asset.phoneNumber);
    _countryCode = TextEditingController(text: _asset.countryCode);
    _countryName = TextEditingController(text: _asset.countryName);
    _operator = TextEditingController(text: _asset.operatorName);
    _iccid = TextEditingController(text: _asset.iccid);
    _eid = TextEditingController(text: _asset.eid);
    _smdp = TextEditingController(text: _asset.smdpAddress);
    _activation = TextEditingController(text: _asset.activationCode);
    _expire = TextEditingController(text: _formatDate(_asset.expireDate));
    _cycle = TextEditingController(text: '${_asset.renewalCycleDays}');
    _balance = TextEditingController(text: _asset.balanceNote);
    _note = TextEditingController(text: _asset.note);
  }

  @override
  void dispose() {
    for (final c in [_phone, _countryCode, _countryName, _operator, _iccid, _eid, _smdp, _activation, _expire, _cycle, _balance, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseDate(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    return DateTime.tryParse(t);
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _parseDate(_expire.text) ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null) {
      setState(() => _expire.text = _formatDate(picked));
    }
  }

  Future<void> _linkProfile() async {
    final t = NekoSimStrings.of(context);
    final service = await ProfileMetadataService.getInstance();
    final profiles = await service.getAllProfiles();
    if (!mounted) return;
    if (profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.noDiscoveredProfiles)),
      );
      return;
    }
    final picked = await showDialog<ProfileMetadata>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.linkInstalledProfile),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: profiles.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = profiles[index];
              return ListTile(
                leading: const Icon(Icons.sim_card_rounded),
                title: Text(p.displayName),
                subtitle: Text([
                  p.iccid,
                  if (p.eid != null && p.eid!.isNotEmpty) 'EID ${p.eid}',
                ].join(' · ')),
                onTap: () => Navigator.pop(context, p),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _asset = _asset.copyWith(linkedProfileIccid: picked.iccid, source: 'profile_metadata');
      _iccid.text = picked.iccid;
      _eid.text = picked.eid ?? _eid.text;
      _operator.text = picked.displayName;
      _countryCode.text = picked.flag;
    });
  }

  Future<void> _save() async {
    final saved = _asset.copyWith(
      phoneNumber: _phone.text.trim(),
      countryCode: _countryCode.text.trim(),
      countryName: _countryName.text.trim(),
      operatorName: _operator.text.trim(),
      iccid: _iccid.text.trim(),
      eid: _eid.text.trim(),
      smdpAddress: _smdp.text.trim(),
      activationCode: _activation.text.trim(),
      expireDate: _parseDate(_expire.text),
      clearExpireDate: _expire.text.trim().isEmpty,
      renewalCycleDays: int.tryParse(_cycle.text.trim()) ?? _asset.renewalCycleDays,
      balanceNote: _balance.text.trim(),
      note: _note.text.trim(),
    );
    await NekoSimAssetService().upsert(saved);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = NekoSimStrings.of(context);
    return StyledHeaderScaffold(
      title: t.simAsset,
      actions: [TextButton(onPressed: _save, child: Text(t.save))],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            onTap: _linkProfile,
            child: ListTile(
              leading: const Icon(Icons.link_rounded),
              title: Text(t.linkedProfile),
              subtitle: Text(
                _asset.linkedProfileIccid.isEmpty
                    ? t.notLinked
                    : _asset.linkedProfileIccid,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          const SizedBox(height: 12),
          _field(_operator, t.operator, Icons.business_rounded),
          _field(_phone, t.phoneNumber, Icons.phone_rounded, keyboard: TextInputType.phone),
          Row(
            children: [
              Expanded(child: _field(_countryCode, t.countryCode, Icons.add_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _field(_countryName, t.countryRegion, Icons.flag_rounded)),
            ],
          ),
          _field(
            _expire,
            t.expiryDate,
            Icons.event_rounded,
            keyboard: TextInputType.datetime,
            suffix: IconButton(
              icon: const Icon(Icons.calendar_month_rounded),
              onPressed: _pickExpiryDate,
            ),
          ),
          _field(_cycle, t.renewCycleDays, Icons.autorenew_rounded,
              keyboard: TextInputType.number),
          _field(_balance, t.balanceNote, Icons.account_balance_wallet_outlined),
          _field(_iccid, 'ICCID', Icons.credit_card_rounded, mono: true),
          _field(_eid, 'EID', Icons.memory_rounded, mono: true),
          _field(_smdp, 'SM-DP+', Icons.dns_rounded, mono: true),
          _field(_activation, t.activationCode, Icons.key_rounded, mono: true),
          _field(_note, t.note, Icons.notes_rounded, minLines: 3, maxLines: 6),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    int minLines = 1,
    int maxLines = 1,
    bool mono = false,
    Widget? suffix,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        minLines: minLines,
        maxLines: maxLines,
        style: mono ? AppTheme.mono(const TextStyle(fontSize: 14)) : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: suffix,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.35),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
