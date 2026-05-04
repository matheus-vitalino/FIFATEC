import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ImageService {
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickFromGallery({BuildContext? context}) async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1200,
    );
    if (file == null) return null;
    if (context != null && context.mounted) {
      return await _cropAndSave(context, file.path);
    }
    return await _saveToApp(file.path);
  }

  Future<String?> pickFromCamera({BuildContext? context}) async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 1200,
    );
    if (file == null) return null;
    if (context != null && context.mounted) {
      return await _cropAndSave(context, file.path);
    }
    return await _saveToApp(file.path);
  }

  Future<String?> _cropAndSave(BuildContext context, String sourcePath) async {
    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CropScreen(imagePath: sourcePath),
      ),
    );
    return croppedPath;
  }

  Future<String> _saveToApp(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(dir.path, 'images'));
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    final fileName =
        'img_${DateTime.now().millisecondsSinceEpoch}${p.extension(sourcePath)}';
    final destPath = p.join(imagesDir.path, fileName);
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  Future<String> saveBytes(Uint8List bytes, String ext) async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(dir.path, 'images'));
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final destPath = p.join(imagesDir.path, fileName);
    await File(destPath).writeAsBytes(bytes);
    return destPath;
  }

  Future<void> deleteImage(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  bool imageExists(String? path) {
    if (path == null) return false;
    return File(path).existsSync();
  }

  Future<List<File>> getAllImages() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(dir.path, 'images'));
      if (!await imagesDir.exists()) return [];
      return imagesDir
          .listSync()
          .whereType<File>()
          .where((f) => ['.jpg', '.jpeg', '.png', '.webp']
              .contains(p.extension(f.path).toLowerCase()))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

// ── Tela de crop ───────────────────────────────────────────────────
class _CropScreen extends StatefulWidget {
  final String imagePath;
  const _CropScreen({required this.imagePath});

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  final TransformationController _transformCtrl = TransformationController();
  final GlobalKey _repaintKey = GlobalKey();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cropSize = size.width * 0.82;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Recortar Foto',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _confirm,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Usar',
                    style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          // Área de crop
          Center(
            child: SizedBox(
              width: cropSize,
              height: cropSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Imagem com zoom/pan
                  ClipOval(
                    child: RepaintBoundary(
                      key: _repaintKey,
                      child: InteractiveViewer(
                        transformationController: _transformCtrl,
                        minScale: 1.0,
                        maxScale: 6.0,
                        clipBehavior: Clip.hardEdge,
                        child: Image.file(
                          File(widget.imagePath),
                          width: cropSize,
                          height: cropSize,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  // Borda do círculo
                  IgnorePointer(
                    child: Container(
                      width: cropSize,
                      height: cropSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Pinça para zoom • Arraste para reposicionar',
            style:
                TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Confirmar',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        setState(() => _saving = false);
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      final imgService = ImageService();
      final path = await imgService.saveBytes(bytes, 'png');
      if (mounted) Navigator.pop(context, path);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao cortar foto: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }
}
