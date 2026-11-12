import 'dart:io';

/// Resolve only fixed UBTech paths on this device. Never copy them into the APK.
class VisbotFaceAssets {
  final String root;
  const VisbotFaceAssets({this.root = '/system/media/visbot/emotion'});

  Future<String?> resolve(String emotion, bool speaking) async {
    // Emotion is selected by FaceController, not interpolated from server input.
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(emotion)) return null;
    final prefix = speaking ? 'speak' : 'silent';
    final directory = speaking ? 'shuohua' : 'bushuohua';
    for (final name in [emotion, 'default']) {
      final path = '$root/$directory/${prefix}_${name}_1.svga';
      try {
        if (await File(path).exists()) return path;
      } on FileSystemException {
        return null;
      }
    }
    return null;
  }
}
