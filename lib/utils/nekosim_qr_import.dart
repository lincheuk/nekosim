import 'package:logging/logging.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;

import 'platform_adapter_io.dart'
    if (dart.library.js_interop) 'platform_adapter_web.dart';
import 'zxing_decoder.dart'
    if (dart.library.js_interop) 'zxing_decoder_web.dart';

final _log = Logger('NekoSimQrImport');

/// Decode a QR code from an image file, with the same platform split as the
/// host download page: zxing_lib on Windows/Linux (mobile_scanner
/// analyzeImage is not implemented there), mobile_scanner elsewhere with a
/// zxing_lib fallback.
Future<String?> decodeQrFromImagePath(String path) async {
  const bool useZxing = bool.fromEnvironment('ENABLE_ZXING', defaultValue: true);

  if ((PlatformX.isWindows || PlatformX.isLinux) && useZxing) {
    return decodeQrWithZxing(path);
  }
  try {
    final controller = ms.MobileScannerController();
    final capture = await controller.analyzeImage(path);
    await controller.dispose();
    if (capture != null && capture.barcodes.isNotEmpty) {
      return capture.barcodes.first.rawValue;
    }
  } catch (e) {
    _log.warning('mobile_scanner analyzeImage failed: $e');
    if (useZxing) return decodeQrWithZxing(path);
  }
  return null;
}
