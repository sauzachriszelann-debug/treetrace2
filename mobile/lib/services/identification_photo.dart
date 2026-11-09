import 'dart:typed_data';
import 'dart:ui' as ui;

class IdentificationPhoto {
  final Uint8List bytes;
  final String mimeType;
  const IdentificationPhoto(this.bytes, this.mimeType);
}

/// Species-only derivative. Never overwrite the original or use this for DBH.
/// Keep the multipart body well below the server's observed upload limit.
Future<IdentificationPhoto> prepareIdentificationPhoto(
    Uint8List original, String mimeType,
    {int maxBytes = 1500000}) async {
  if (original.length <= maxBytes) {
    return IdentificationPhoto(original, mimeType);
  }
  for (final size in [1280, 960, 640, 480, 320]) {
    final codec = await ui.instantiateImageCodec(original,
        targetWidth: size, allowUpscaling: false);
    try {
      final frame = await codec.getNextFrame();
      try {
        final png =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (png != null && png.lengthInBytes <= maxBytes) {
          return IdentificationPhoto(
              png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
              'image/png');
        }
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
  throw const FormatException('Could not prepare identification photo');
}
