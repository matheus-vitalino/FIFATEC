import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';

class BackupService {
  final DatabaseHelper _db = DatabaseHelper();

  Future<File> exportBackup() async {
    final data = await _db.exportAll();
    final dir = await getTemporaryDirectory();
    final zipPath = p.join(dir.path, 'timinho_backup_${DateTime.now().millisecondsSinceEpoch}.zip');

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    // Adiciona JSON
    final jsonBytes = utf8.encode(jsonEncode(data));
    encoder.addArchiveFile(ArchiveFile('data/backup.json', jsonBytes.length, jsonBytes));

    // Adiciona imagens
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'images'));
    if (await imagesDir.exists()) {
      final files = imagesDir.listSync().whereType<File>().toList();
      for (final file in files) {
        final bytes = await file.readAsBytes();
        encoder.addArchiveFile(
          ArchiveFile('images/${p.basename(file.path)}', bytes.length, bytes),
        );
      }
    }

    encoder.close();
    return File(zipPath);
  }

  Future<void> shareBackup() async {
    final file = await exportBackup();
    await Share.shareXFiles([XFile(file.path)], text: 'AppTiminho - Backup');
  }

  Future<void> importBackup(String zipPath) async {
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    Map<String, dynamic>? data;

    // Prepara pasta de imagens
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'images'));
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

    for (final file in archive) {
      if (file.isFile) {
        final content = file.content as List<int>;
        if (file.name == 'data/backup.json') {
          data = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
        } else if (file.name.startsWith('images/')) {
          final imgName = p.basename(file.name);
          final destPath = p.join(imagesDir.path, imgName);
          File(destPath).writeAsBytesSync(content);
        }
      }
    }

    if (data != null) {
      await _db.importAll(data);
    } else {
      throw Exception('Arquivo de backup inválido: JSON não encontrado.');
    }
  }
}