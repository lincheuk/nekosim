import 'dart:async';
import 'dart:typed_data';
import 'package:ble/ble.dart';
import 'package:logging/logging.dart';
import '../euicc_adapter.dart';
import '../../utils/hex_utils.dart';
import '../../utils/error_codes.dart';

/// Reports current firmware-row progress while [BeeSimAdapter.uploadFirmware]
/// streams data to the device. Carries the row index and the total number of
/// rows reported by the upstream upgrade-check response.
class BeeSimUpgradeStatus {
  const BeeSimUpgradeStatus({
    required this.crc,
    required this.totalRows,
    required this.currentRow,
  });

  final String crc;
  final int totalRows;
  final int currentRow;

  @override
  String toString() =>
      'BeeSimUpgradeStatus(crc=$crc, totalRows=$totalRows, currentRow=$currentRow)';
}

class BeeSimAdapter extends BaseAdapter {
  static final Logger _log = Logger('BeeSimAdapter');

  BeeSimAdapter() : super(_log);

  /// Mirrors the JS client's `groupValue()`: BLE notify packets are 20 bytes
  /// max — 2 bytes header `[total, index]` + 18 bytes payload.
  static const int _maxFramePayload = 18;

  /// Service used purely for documentation — discovery uses TX/RX char hints.
  /// JS picks the first writable + first notify-only characteristic, so we do
  /// the same and only treat AE01/AE02 as preference hints.
  final Guid serviceUuid = Guid('0000ae30-0000-1000-8000-00805f9b34fb');

  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  StreamSubscription? _rxSub;
  StreamSubscription? _connSub;
  bool _isBeeSimConnected = false;
  final List<Uint8List> _rxQueue = [];
  Completer<void>? _rxSignal;

  String? _lastAtr;
  bool _initialized = false;
  final StreamController<EuiccPortState> _stateController =
      StreamController<EuiccPortState>.broadcast();

  final List<int> _rxBuffer = [];

  @override
  Stream<EuiccPortState> get stateStream => _stateController.stream;

  @override
  bool get requiresRefresh => true;

  @override
  String? get lastAtr => _lastAtr;

  @override
  ReaderStrategy get readerStrategy => ReaderStrategy.slow;

  @override
  NotificationStrategy get notificationStrategy => NotificationStrategy.twoStep;

  @override
  Future<List<Reader>> listReaders({bool force = false}) async {
    return connectedReader != null ? [connectedReader!] : [];
  }

  @override
  Future<void> connect(Reader reader) async {
    return await runExclusive(() async {
      updateConnectedReader(reader);
      final readerName = reader.id;
      final parts = readerName.split('|');
      final deviceId = parts.isNotEmpty ? parts.last : readerName;
      _device = BluetoothDevice.fromId(deviceId);

      _log.info("Connecting to BeeSIM device: $deviceId");
      try {
        if (await Ble.adapterState.first != BluetoothAdapterState.on) {
          _log.info("Waiting for Bluetooth adapter to be ON...");
          await Ble.adapterState
              .where((s) => s == BluetoothAdapterState.on)
              .first
              .timeout(
                const Duration(seconds: 3),
                onTimeout: () =>
                    throw AppException(AppErrorCode.ERROR_BLUETOOTH_DISABLED),
              );
        }

        await _device!.connect(
          autoConnect: false,
          timeout: const Duration(seconds: 10),
        );

        _connSub?.cancel();
        _isBeeSimConnected = true;
        _connSub = _device!.connectionState.listen((s) {
          if (s == BluetoothConnectionState.disconnected) {
            _log.warning("BeeSIM disconnected unexpectedly");
            _isBeeSimConnected = false;
            if (_rxSignal != null && !_rxSignal!.isCompleted) {
              _rxSignal!.completeError(
                AppException(
                  AppErrorCode.ERROR_BLUETOOTH_CONNECT_FAILED,
                  message: "The connection has timed out unexpectedly.",
                ),
              );
            }
          } else if (s == BluetoothConnectionState.connected) {
            _isBeeSimConnected = true;
          }
        });

        final services = await _device!.discoverServices();

        // Mirror the JS client: pick the first writable characteristic for TX
        // and the first notify-or-indicate one that is NOT the writer for RX.
        // AE01/AE02 are preferred hints when present.
        BluetoothCharacteristic? writerHinted;
        BluetoothCharacteristic? notifierHinted;
        BluetoothCharacteristic? writerFallback;
        BluetoothCharacteristic? notifierFallback;

        for (var svc in services) {
          for (var c in svc.characteristics) {
            final uuid = c.uuid.toString().toLowerCase();
            final canWrite =
                c.properties.write || c.properties.writeWithoutResponse;
            final canNotify = c.properties.notify || c.properties.indicate;
            if (uuid.contains('ae01') && canWrite) {
              writerHinted = c;
            } else if (uuid.contains('ae02') && canNotify) {
              notifierHinted = c;
            } else if (canWrite && writerFallback == null) {
              writerFallback = c;
            } else if (canNotify && notifierFallback == null) {
              notifierFallback = c;
            }
          }
        }
        _txChar = writerHinted ?? writerFallback;
        _rxChar = notifierHinted ?? notifierFallback;
        if (_txChar != null) {
          _log.info("BeeSIM TX characteristic: ${_txChar!.uuid}");
        }
        if (_rxChar != null) {
          _log.info("BeeSIM RX characteristic: ${_rxChar!.uuid}");
        }

        if (_txChar == null) {
          throw AppException(
            AppErrorCode.ERROR_BLUETOOTH_CHARACTERISTIC_NOT_FOUND,
            message: "BeeSIM write characteristic not found",
          );
        }
        if (_rxChar == null) {
          throw AppException(
            AppErrorCode.ERROR_BLUETOOTH_CHARACTERISTIC_NOT_FOUND,
            message: "BeeSIM notify characteristic not found",
          );
        }

        await _rxChar!.setNotifyValue(true);
        await Future.delayed(const Duration(milliseconds: 200));

        _rxSub = _rxChar!.onValueReceived.listen((data) {
          if (data.length < 2) return;
          final total = data[0];
          final index = data[1];
          if (index == 1) {
            _rxBuffer.clear();
          }
          _rxBuffer.addAll(data.sublist(2));
          if (index == total) {
            final frame = Uint8List.fromList(_rxBuffer);
            _rxQueue.add(frame);
            if (_rxSignal != null && !_rxSignal!.isCompleted) {
              _rxSignal!.complete();
            }
          }
        });

        // Initialize device — JS calls setTXPower(1) by default.
        _log.info("Initializing BeeSIM...");
        await _sendCommand(
          Uint8List.fromList([0xA0, 0x3E, 0x01, 0x00, 0x00]),
          "set power",
        );

        _initialized = true;
        _stateController.add(EuiccPortState.open);
      } catch (e) {
        _log.severe("BeeSIM connect failed: $e");
        await disconnect();
        rethrow;
      }
    });
  }

  @override
  Future<void> disconnect() async {
    return await runExclusive(() async {
      _initialized = false;
      _isBeeSimConnected = false;
      _connSub?.cancel();
      _connSub = null;
      await _rxSub?.cancel();
      _rxSub = null;
      _rxQueue.clear();
      await _device?.disconnect();
      _device = null;
      _txChar = null;
      _rxChar = null;
      updateConnectedReader(null);
      _stateController.add(EuiccPortState.closed);
    });
  }

  @override
  Future<Uint8List> sendRawApdu(Uint8List apdu) async {
    if (!_initialized) {
      if (connectedReader == null) {
        throw AppException(
          AppErrorCode.ERROR_UNKNOWN,
          message: "Not connected",
        );
      }
      await connect(connectedReader!);
    }
    return await _sendCommand(apdu, "apdu");
  }

  static const _standardAid = "A0000005591010FFFFFFFF8900000100";

  @override
  Future<Channel> openChannel({List<String>? aids}) async {
    return await openLogicalChannel(aids: [_standardAid]);
  }

  @override
  Future<void> proactiveRefresh() async {
    _log.info("Proactive refresh: Sending BeeSIM reset command...");
    try {
      await _sendCommand(
        Uint8List.fromList([0xA0, 0x3F, 0x00, 0x00, 0x00]),
        "reset",
      );
    } catch (e) {
      _log.warning("Proactive refresh reset command failed: $e");
    }
  }

  /// Sends the firmware "check upgrade" probe and parses the response.
  ///
  /// Mirrors `checkUpgrading()` in beesim.js: the device answers with
  /// `[0x10, ...]` on success; bytes 49..50 are the crc, 51..52 totalRows,
  /// 53..54 currentRow (all big-endian).
  Future<BeeSimUpgradeStatus> checkUpgrading() async {
    await _ensureConnected();
    final resp = await _sendCommand(
      Uint8List.fromList([0x00, 0x00, 0x00, 0x00, 0xF4, 0x01, 0x01]),
      'check upgrading',
    );
    if (resp.isEmpty || resp[0] != 0x10) {
      throw AppException(
        AppErrorCode.ERROR_UNKNOWN,
        message:
            'BeeSIM upgrade check failed: '
            '${resp.isEmpty ? '<empty>' : HexUtils.bytesToHex(resp)}',
      );
    }
    if (resp.length < 55) {
      throw AppException(
        AppErrorCode.ERROR_UNKNOWN,
        message:
            'BeeSIM upgrade check response too short (${resp.length} bytes)',
      );
    }
    final crc = HexUtils.bytesToHex(resp.sublist(49, 51));
    final totalRows = _beU16(resp, 51);
    final currentRow = _beU16(resp, 53);
    return BeeSimUpgradeStatus(
      crc: crc,
      totalRows: totalRows,
      currentRow: currentRow,
    );
  }

  /// Writes a single firmware row coming back from the upgrade endpoint.
  /// The wire format is `<total:u16><index:u16><row bytes>` per the JS client
  /// (`r = Ee(total) + Ee(index) + row` then `sendCommand(r)`).
  ///
  /// Returns true if the device echoed the expected success marker
  /// (`resp[0] == 0x10 && resp[3] == 0x01`).
  Future<bool> writeFirmwareRow({
    required int totalRows,
    required int currentRow,
    required Uint8List rowBytes,
  }) async {
    await _ensureConnected();
    final header = Uint8List(4)
      ..[0] = (totalRows >> 8) & 0xFF
      ..[1] = totalRows & 0xFF
      ..[2] = (currentRow >> 8) & 0xFF
      ..[3] = currentRow & 0xFF;
    final payload = Uint8List(header.length + rowBytes.length)
      ..setRange(0, header.length, header)
      ..setRange(header.length, header.length + rowBytes.length, rowBytes);
    final resp = await _sendCommand(payload, 'fw row $currentRow/$totalRows');
    return resp.length >= 4 && resp[0] == 0x10 && resp[3] == 0x01;
  }

  /// Issues the BLE reset command (`A0 3F 00 00 00`) and clears local
  /// initialised state so the next APDU re-opens a channel.
  ///
  /// The device usually drops the BLE link as it reboots, so a timeout or
  /// connect-failed reply is expected and not treated as an error.
  Future<void> resetDevice() async {
    try {
      await _sendCommand(
        Uint8List.fromList([0xA0, 0x3F, 0x00, 0x00, 0x00]),
        'reset',
      );
    } on AppException catch (e) {
      if (e.code != AppErrorCode.ERROR_BLUETOOTH_TIMEOUT &&
          e.code != AppErrorCode.ERROR_BLUETOOTH_CONNECT_FAILED) {
        rethrow;
      }
      _log.info('Reset acknowledged by disconnect (${e.code.name}).');
    } finally {
      _initialized = false;
    }
  }

  Future<void> _ensureConnected() async {
    if (_initialized && _isBeeSimConnected && _txChar != null) return;
    final reader = connectedReader;
    if (reader == null) {
      throw AppException(
        AppErrorCode.ERROR_BLUETOOTH_NOT_CONNECTED,
        message: 'BeeSIM reader is not selected.',
      );
    }
    await connect(reader);
  }

  int _beU16(Uint8List bytes, int offset) =>
      ((bytes[offset] & 0xFF) << 8) | (bytes[offset + 1] & 0xFF);

  Future<Uint8List> _sendCommand(Uint8List data, String label) async {
    _rxQueue.clear();
    final frames = _encodeFrames(data);
    _log.fine(
      () =>
          "[BeeSIM $label] TX len=${data.length} data=${HexUtils.bytesToHex(data)}",
    );

    if (_txChar == null) {
      throw AppException(
        AppErrorCode.ERROR_BLUETOOTH_CONNECT_FAILED,
        message: "BeeSIM TX characteristic is not available",
      );
    }
    final bool withoutResp =
        _txChar!.properties.writeWithoutResponse && !_txChar!.properties.write;

    for (var i = 0; i < frames.length; i++) {
      final f = frames[i];
      _log.fine(
        () =>
            "[BeeSIM $label] TX frame ${i + 1}/${frames.length} len=${f.length} data=${HexUtils.bytesToHex(f)}",
      );
      await _txChar!.write(f, withoutResponse: withoutResp);
      if (withoutResp || frames.length > 1) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    final resp = await _waitForResponse(const Duration(seconds: 100), label);
    _log.fine(
      () =>
          "[BeeSIM $label] RX len=${resp.length} data=${HexUtils.bytesToHex(resp)}",
    );
    return resp;
  }

  /// Splits the command into 20-byte BLE notify frames following the JS
  /// client's `groupValue()` (max 18 bytes of payload per frame) and prepends
  /// the `[total, index]` framing header.
  List<Uint8List> _encodeFrames(Uint8List data) {
    final frames = <Uint8List>[];
    int total = data.isEmpty ? 1 : (data.length / _maxFramePayload).ceil();
    for (int i = 0; i < total; i++) {
      final start = i * _maxFramePayload;
      final end = (start + _maxFramePayload > data.length)
          ? data.length
          : start + _maxFramePayload;
      final payload = data.sublist(start, end);

      final frame = Uint8List(2 + payload.length)
        ..[0] = total
        ..[1] = i + 1
        ..setRange(2, 2 + payload.length, payload);
      frames.add(frame);
    }
    return frames;
  }

  Future<Uint8List> _waitForResponse(
    Duration timeout,
    String description,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (_rxQueue.isNotEmpty) return _rxQueue.removeAt(0);

      if (_device == null || !_isBeeSimConnected) {
        throw AppException(
          AppErrorCode.ERROR_BLUETOOTH_CONNECT_FAILED,
          message: "The connection has timed out unexpectedly.",
        );
      }

      final now = DateTime.now();
      if (now.isAfter(deadline)) {
        throw AppException(
          AppErrorCode.ERROR_BLUETOOTH_TIMEOUT,
          message: "BeeSIM timeout: $description after ${timeout.inSeconds}s",
        );
      }

      _rxSignal = Completer<void>();
      try {
        await _rxSignal!.future.timeout(const Duration(milliseconds: 500));
      } on TimeoutException {
        // retry the loop
      } finally {
        _rxSignal = null;
      }
    }
  }
}
