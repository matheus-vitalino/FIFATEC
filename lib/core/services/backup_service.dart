import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';

class BackupImportOptions {
  final bool players;
  final bool playerStats;
  final bool championships;
  final bool matches;
  final bool seasons;
  final bool settings;
  final bool images;
  final bool overwrite;

  const BackupImportOptions({
    this.players = true,
    this.playerStats = true,
    this.championships = true,
    this.matches = true,
    this.seasons = true,
    this.settings = true,
    this.images = true,
    this.overwrite = true,
  });

  const BackupImportOptions.empty()
      : players = false,
        playerStats = false,
        championships = false,
        matches = false,
        seasons = false,
        settings = false,
        images = false,
        overwrite = true;

  bool get hasDatabaseData =>
      players || playerStats || championships || matches || seasons || settings;

  bool get hasAnything => hasDatabaseData || images;
}

/// Dados lidos do arquivo de backup para exibição de preview.
class BackupPreview {
  final int playerCount;
  final int championshipCount;
  final int matchCount;
  final int seasonCount;
  final bool hasSettings;
  final int imageCount;
  final List<String> playerNames;
  final List<String> championshipNames;
  final List<String> seasonNames;

  const BackupPreview({
    required this.playerCount,
    required this.championshipCount,
    required this.matchCount,
    required this.seasonCount,
    required this.hasSettings,
    required this.imageCount,
    required this.playerNames,
    required this.championshipNames,
    required this.seasonNames,
  });
}

class BackupService {
  final DatabaseHelper _db = DatabaseHelper();

  String createBackupFileName() {
    final now = DateTime.now().toLocal();
    final date = '${now.year}${_two(now.month)}${_two(now.day)}';
    final time = '${_two(now.hour)}${_two(now.minute)}';
    return 'fifatec_backup_${date}_$time.zip';
  }

  Future<File> exportBackup() async {
    final dir = await getTemporaryDirectory();
    final zipPath = p.join(dir.path, createBackupFileName());
    return _createBackupFile(zipPath);
  }

  Future<String?> exportBackupToSelectedLocation() async {
    final tempFile = await exportBackup();
    final bytes = await tempFile.readAsBytes();
    final fileName = p.basename(tempFile.path);

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Escolha onde salvar o backup',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: bytes,
    );

    if (savedPath == null) return null;

    if (!kIsWeb) {
      try {
        final savedFile = File(savedPath);
        final exists = await savedFile.exists();
        final isEmpty = exists ? await savedFile.length() == 0 : true;
        if (isEmpty) {
          await savedFile.writeAsBytes(bytes, flush: true);
        }
      } catch (_) {}
    }

    return savedPath;
  }

  Future<void> shareBackup() async {
    final file = await exportBackup();
    await Share.shareXFiles([XFile(file.path)], text: 'FIFATEC - Backup');
  }

  /// Lê o arquivo .zip e retorna um preview com contagens e nomes.
  Future<BackupPreview> readBackupPreview(String zipPath) async {
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    Map<String, dynamic>? data;
    int imageCount = 0;

    for (final file in archive) {
      if (!file.isFile) continue;
      if (file.name == 'data/backup.json') {
        final content = file.content as List<int>;
        data = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      } else if (file.name.startsWith('images/')) {
        final name = p.basename(file.name);
        if (name.trim().isNotEmpty) imageCount++;
      }
    }

    if (data == null) {
      return const BackupPreview(
        playerCount: 0,
        championshipCount: 0,
        matchCount: 0,
        seasonCount: 0,
        hasSettings: false,
        imageCount: 0,
        playerNames: [],
        championshipNames: [],
        seasonNames: [],
      );
    }

    final players = _mapList(data['players']);
    final championships = _mapList(data['championships']);
    final matches = _mapList(data['matches']);
    final seasons = _mapList(data['seasons']);

    return BackupPreview(
      playerCount: players.length,
      championshipCount: championships.length,
      matchCount: matches.length,
      seasonCount: seasons.length,
      hasSettings: data['settings'] != null,
      imageCount: imageCount,
      playerNames: players
          .take(5)
          .map((p) => (p['name'] as String?) ?? '?')
          .toList(),
      championshipNames: championships
          .take(5)
          .map((c) => (c['name'] as String?) ?? '?')
          .toList(),
      seasonNames: seasons
          .take(5)
          .map((s) => (s['name'] as String?) ?? '?')
          .toList(),
    );
  }

  Future<void> importBackup(
    String zipPath, {
    BackupImportOptions options = const BackupImportOptions(),
  }) async {
    if (!options.hasAnything) {
      throw Exception('Selecione pelo menos uma opção para importar.');
    }

    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    Map<String, dynamic>? data;

    if (options.images) {
      await _importImagesFromArchive(archive, overwrite: options.overwrite);
    }

    for (final file in archive) {
      if (!file.isFile || file.name != 'data/backup.json') continue;
      final content = file.content as List<int>;
      data = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      break;
    }

    if (options.hasDatabaseData) {
      if (data == null) {
        throw Exception('Arquivo de backup inválido: JSON não encontrado.');
      }

      await _db.importSelected(
        data,
        importPlayers: options.players,
        importPlayerStats: options.playerStats,
        importChampionships: options.championships,
        importMatches: options.matches,
        importSeasons: options.seasons,
        importSettings: options.settings,
        overwrite: options.overwrite,
      );
    }
  }

  Future<File> _createBackupFile(String zipPath) async {
    final data = await _db.exportAll();

    final zipFile = File(zipPath);
    if (await zipFile.exists()) {
      await zipFile.delete();
    }

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    final jsonBytes = utf8.encode(jsonEncode(data));
    encoder.addArchiveFile(
      ArchiveFile('data/backup.json', jsonBytes.length, jsonBytes),
    );

    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'images'));
    if (await imagesDir.exists()) {
      final files = imagesDir.listSync().whereType<File>().toList();
      for (final file in files) {
        final imageBytes = await file.readAsBytes();
        encoder.addArchiveFile(
          ArchiveFile(
            'images/${p.basename(file.path)}',
            imageBytes.length,
            imageBytes,
          ),
        );
      }
    }

    encoder.close();
    return File(zipPath);
  }

  Future<void> _importImagesFromArchive(
    Archive archive, {
    bool overwrite = true,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    for (final file in archive) {
      if (!file.isFile || !file.name.startsWith('images/')) continue;

      final imageName = p.basename(file.name);
      if (imageName.trim().isEmpty) continue;

      final destPath = p.join(imagesDir.path, imageName);

      // Se não for sobrescrever, pula arquivos que já existem
      if (!overwrite && await File(destPath).exists()) continue;

      final content = file.content as List<int>;
      await File(destPath).writeAsBytes(content, flush: true);
    }
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    return (value as List? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}