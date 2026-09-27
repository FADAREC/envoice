import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Picks a logo and stores it under a unique path so Flutter's Image.file
/// cache cannot keep showing the previous file after an overwrite.
Future<String?> pickAndStoreLogo({String? previousPath}) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 85,
  );
  if (file == null) return null;

  final dir = await getApplicationDocumentsDirectory();
  final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final dest = File(p.join(dir.path, 'business_logo_$stamp$ext'));
  await File(file.path).copy(dest.path);

  // Best-effort cleanup of previous logo so files don't accumulate.
  if (previousPath != null && previousPath != dest.path) {
    try {
      final old = File(previousPath);
      if (await old.exists()) await old.delete();
    } catch (_) {}
  }

  return dest.path;
}
