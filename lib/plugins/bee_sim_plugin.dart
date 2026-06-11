import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../adapter/ble/bee_sim_adapter.dart';
import '../adapter/euicc_adapter.dart';
import '../models/euicc_profile.dart';
import '../utils/hex_utils.dart';
import '../widgets/profiles_screen/action_button.dart';
import 'plugin_base.dart';

/// Surfaces the BeeSIM firmware-update flow as a reader action.
///
/// The action is only shown when the connected reader is a [BeeSimAdapter].
/// On tap the plugin opens a modal log dialog, asks the adapter for its
/// current firmware state, posts that state to BeeSIM's upgrade-check
/// endpoint, and — if the server returns pending rows — streams them back
/// onto the device one by one. The wire format and signing scheme mirror the
/// BeeSIM web BLE client.
class BeeSimPlugin extends ProfilePlugin {
  static final Logger _log = Logger('BeeSimPlugin');

  // Pinned constants from the BeeSIM web client. They are not secrets — the
  // upstream JS bundle ships them to every browser — but they DO have to stay
  // in sync with the server's expectation.
  static const _apiBase = 'https://api.beeesim.com';
  static const _signSecret = 'Hz3wU92K2ion6Kaq';
  static const _upgradeKey = 'BEESIM_FW_UPGRADE';

  @override
  String get id => 'bee_sim';

  @override
  String get name => 'BeeSIM';

  @override
  bool isMatch(EuiccProfile profile) => false;

  @override
  List<Widget> buildReaderActions(
    BuildContext context,
    ReaderActionContext actionContext,
  ) {
    final adapter = actionContext.adapter;
    final source = actionContext.reader?.source;
    final beeAdapter = _resolveBeeAdapter(adapter, source);
    if (beeAdapter == null) return const <Widget>[];
    return <Widget>[
      ActionButton(
        icon: Icons.system_update_alt,
        label: 'Upgrade firmware',
        onPressed: () => _runFirmwareUpgrade(context, beeAdapter),
      ),
    ];
  }

  BeeSimAdapter? _resolveBeeAdapter(Adapter adapter, Object? source) {
    if (adapter is BeeSimAdapter) return adapter;
    if (source is BeeSimAdapter) return source;
    return null;
  }

  Future<void> _runFirmwareUpgrade(
    BuildContext context,
    BeeSimAdapter adapter,
  ) async {
    final logs = ValueNotifier<List<String>>(<String>[]);
    final progress = ValueNotifier<_UpgradeProgress?>(null);
    final done = ValueNotifier<bool>(false);

    void log(String line) {
      _log.info(line);
      logs.value = <String>[...logs.value, line];
    }

    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BeeSimUpgradeDialog(
        logs: logs,
        progress: progress,
        done: done,
      ),
    );

    try {
      log('Checking current firmware state…');
      final status = await adapter.checkUpgrading();
      log(
        'Device reports crc=${status.crc} '
        'rows=${status.currentRow}/${status.totalRows}',
      );

      log('Querying BeeSIM for available firmware…');
      final upgrade = await _postUpgradeCheck(status);
      if (upgrade.status != 200) {
        log('Server rejected upgrade check: ${upgrade.message}');
        return;
      }
      if (upgrade.rows.isEmpty) {
        log('Firmware is already up to date.');
        return;
      }

      log(
        'Server returned ${upgrade.rows.length} rows '
        '(total=${upgrade.total}, resume index=${upgrade.index}).',
      );
      progress.value = _UpgradeProgress(
        current: upgrade.index,
        total: upgrade.total,
      );

      int n = upgrade.index;
      for (final row in upgrade.rows) {
        final ok = await adapter.writeFirmwareRow(
          totalRows: upgrade.total,
          currentRow: n,
          rowBytes: row,
        );
        if (!ok) {
          throw StateError(
            'Device rejected firmware row $n/${upgrade.total}.',
          );
        }
        progress.value = _UpgradeProgress(current: n, total: upgrade.total);
        n++;
      }

      log('All rows accepted. Resetting device…');
      try {
        await adapter.resetDevice();
      } catch (e) {
        // A clean reset usually drops the BLE link before acknowledging — the
        // upload itself already succeeded, so don't fail the whole flow on
        // post-reset I/O errors.
        log('Reset returned ${e.runtimeType} (ignored — device is rebooting).');
      }
      log('Firmware update complete.');
    } catch (e, st) {
      log('Firmware update failed: $e');
      _log.severe('BeeSIM upgrade failed', e, st);
    } finally {
      done.value = true;
      await dialogFuture;
    }
  }

  Future<_UpgradeCheckResponse> _postUpgradeCheck(
    BeeSimUpgradeStatus status,
  ) async {
    const action = 'upgrade_check';
    final body = <String, dynamic>{
      'key': _upgradeKey,
      'crc': status.crc,
      'totalRows': status.totalRows,
      'currentRow': status.currentRow,
    };
    final params = <String, String>{'action': action};
    final bodyJson = jsonEncode(body);
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final sign = _signRequest(params: params, body: bodyJson, ts: timestamp);

    final uri = Uri.parse(
      '$_apiBase/v2/plugin/mall/firmware.do',
    ).replace(queryParameters: params);

    final resp = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json;charset=UTF-8',
            'X-Timestamp': timestamp,
            'X-Sign': sign,
          },
          body: bodyJson,
        )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      return _UpgradeCheckResponse(
        status: resp.statusCode,
        message: 'HTTP ${resp.statusCode}',
        rows: const <Uint8List>[],
        total: 0,
        index: 0,
      );
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawData = decoded['data'];
    final rows = <Uint8List>[];
    if (rawData is List) {
      for (final row in rawData) {
        if (row is String && row.isNotEmpty) {
          rows.add(HexUtils.hexToBytes(row));
        }
      }
    }
    return _UpgradeCheckResponse(
      status: (decoded['status'] as num?)?.toInt() ?? 200,
      message: decoded['msg']?.toString() ?? '',
      rows: rows,
      total: (decoded['total'] as num?)?.toInt() ?? rows.length,
      index: (decoded['index'] as num?)?.toInt() ?? 1,
    );
  }

  String _signRequest({
    required Map<String, String> params,
    required String body,
    required String ts,
  }) {
    // Replicates the JS client's `st()` signer:
    //   X-Sign = md5( base64utf8( params_qs + body + ts + SECRET ) )
    // params_qs is the unreserved `a=1&b=2` joining produced by `jt(params)`.
    final qs = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final raw = '$qs$body$ts$_signSecret';
    final b64 = base64.encode(utf8.encode(raw));
    return md5.convert(utf8.encode(b64)).toString();
  }
}

class _UpgradeCheckResponse {
  const _UpgradeCheckResponse({
    required this.status,
    required this.message,
    required this.rows,
    required this.total,
    required this.index,
  });

  final int status;
  final String message;
  final List<Uint8List> rows;
  final int total;
  final int index;
}

class _UpgradeProgress {
  const _UpgradeProgress({required this.current, required this.total});
  final int current;
  final int total;
}

class _BeeSimUpgradeDialog extends StatelessWidget {
  const _BeeSimUpgradeDialog({
    required this.logs,
    required this.progress,
    required this.done,
  });

  final ValueNotifier<List<String>> logs;
  final ValueNotifier<_UpgradeProgress?> progress;
  final ValueNotifier<bool> done;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('BeeSIM firmware update'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<_UpgradeProgress?>(
              valueListenable: progress,
              builder: (_, p, _) {
                if (p == null) return const SizedBox.shrink();
                final fraction = p.total == 0 ? null : p.current / p.total;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(value: fraction),
                      const SizedBox(height: 4),
                      Text('Row ${p.current} / ${p.total}'),
                    ],
                  ),
                );
              },
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ValueListenableBuilder<List<String>>(
                valueListenable: logs,
                builder: (_, lines, _) => SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    lines.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: done,
          builder: (ctx, isDone, _) => TextButton(
            onPressed: isDone ? () => Navigator.of(ctx).pop() : null,
            child: const Text('Close'),
          ),
        ),
      ],
    );
  }
}
