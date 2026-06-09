import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'app_timinho.db');

    return openDatabase(
      path,
      version: 4,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE players ADD COLUMN assists INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE matches ADD COLUMN seasonId TEXT');
      } catch (_) {}
    }

    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE players ADD COLUMN ownGoals INTEGER DEFAULT 0');
      } catch (_) {}

      await db.execute('''
        CREATE TABLE IF NOT EXISTS player_season_stats (
          seasonId TEXT NOT NULL,
          playerId TEXT NOT NULL,
          matchesPlayed INTEGER DEFAULT 0,
          wins INTEGER DEFAULT 0,
          losses INTEGER DEFAULT 0,
          goals INTEGER DEFAULT 0,
          ownGoals INTEGER DEFAULT 0,
          assists INTEGER DEFAULT 0,
          vices INTEGER DEFAULT 0,
          finals INTEGER DEFAULT 0,
          titles INTEGER DEFAULT 0,
          PRIMARY KEY (seasonId, playerId)
        )
      ''');

      await _migrateLegacyPlayersToGlobal(db);
    }

    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE players ADD COLUMN ownGoals INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE player_season_stats ADD COLUMN ownGoals INTEGER DEFAULT 0');
      } catch (_) {}
    }
  }

  Future<void> _migrateLegacyPlayersToGlobal(Database db) async {
    final rows = await db.query('players', orderBy: 'createdAt ASC');
    if (rows.isEmpty) return;

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final name = ((row['name'] as String?) ?? '').trim().toLowerCase();
      final key = name.isEmpty ? (row['id'] as String? ?? '') : name;
      groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
    }

    for (final entries in groups.values) {
      if (entries.isEmpty) continue;

      final canonical = Map<String, dynamic>.from(entries.first);
      final merged = <String, dynamic>{
        ...canonical,
        'seasonId': null,
        'matchesPlayed': 0,
        'wins': 0,
        'losses': 0,
        'goals': 0,
        'ownGoals': 0,
        'assists': 0,
        'vices': 0,
        'finals': 0,
        'titles': 0,
      };

      String? bestDescription = canonical['description'] as String?;
      String? bestPhotoPath = canonical['photoPath'] as String?;
      DateTime earliest = DateTime.tryParse((canonical['createdAt'] as String?) ?? '') ?? DateTime.now();
      final seasonTotals = <String, Map<String, int>>{};

      for (final entry in entries) {
        final matchesPlayed = (entry['matchesPlayed'] as int?) ?? 0;
        final wins = (entry['wins'] as int?) ?? 0;
        final losses = (entry['losses'] as int?) ?? 0;
        final goals = (entry['goals'] as int?) ?? 0;
        final ownGoals = (entry['ownGoals'] as int?) ?? 0;
        final assists = (entry['assists'] as int?) ?? 0;
        final vices = (entry['vices'] as int?) ?? 0;
        final finals = (entry['finals'] as int?) ?? 0;
        final titles = (entry['titles'] as int?) ?? 0;

        merged['matchesPlayed'] += matchesPlayed;
        merged['wins'] += wins;
        merged['losses'] += losses;
        merged['goals'] += goals;
        merged['ownGoals'] += ownGoals;
        merged['assists'] += assists;
        merged['vices'] += vices;
        merged['finals'] += finals;
        merged['titles'] += titles;

        final seasonId = entry['seasonId'] as String?;
        if (seasonId != null && seasonId.isNotEmpty) {
          final totals = seasonTotals.putIfAbsent(seasonId, () => {
            'matchesPlayed': 0,
            'wins': 0,
            'losses': 0,
            'goals': 0,
            'ownGoals': 0,
            'assists': 0,
            'vices': 0,
            'finals': 0,
            'titles': 0,
          });
          totals['matchesPlayed'] = totals['matchesPlayed']! + matchesPlayed;
          totals['wins'] = totals['wins']! + wins;
          totals['losses'] = totals['losses']! + losses;
          totals['goals'] = totals['goals']! + goals;
          totals['ownGoals'] = totals['ownGoals']! + ownGoals;
          totals['assists'] = totals['assists']! + assists;
          totals['vices'] = totals['vices']! + vices;
          totals['finals'] = totals['finals']! + finals;
          totals['titles'] = totals['titles']! + titles;
        }

        final createdAt = DateTime.tryParse((entry['createdAt'] as String?) ?? '');
        if (createdAt != null && createdAt.isBefore(earliest)) {
          earliest = createdAt;
        }

        final desc = entry['description'] as String?;
        if ((bestDescription == null || bestDescription.isEmpty) && desc != null && desc.isNotEmpty) {
          bestDescription = desc;
        }
        final photo = entry['photoPath'] as String?;
        if ((bestPhotoPath == null || bestPhotoPath.isEmpty) && photo != null && photo.isNotEmpty) {
          bestPhotoPath = photo;
        }
      }

      merged['description'] = bestDescription;
      merged['photoPath'] = bestPhotoPath;
      merged['createdAt'] = earliest.toIso8601String();

      await db.update('players', merged, where: 'id = ?', whereArgs: [merged['id']]);

      for (final seasonEntry in seasonTotals.entries) {
        final seasonId = seasonEntry.key;
        final totals = seasonEntry.value;
        await db.insert(
          'player_season_stats',
          {
            'seasonId': seasonId,
            'playerId': merged['id'],
            ...totals,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final extra in entries.skip(1)) {
        await db.delete('players', where: 'id = ?', whereArgs: [extra['id']]);
      }
    }
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE players (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        photoPath TEXT,
        matchesPlayed INTEGER DEFAULT 0,
        wins INTEGER DEFAULT 0,
        losses INTEGER DEFAULT 0,
        goals INTEGER DEFAULT 0,
        ownGoals INTEGER DEFAULT 0,
        assists INTEGER DEFAULT 0,
        vices INTEGER DEFAULT 0,
        finals INTEGER DEFAULT 0,
        titles INTEGER DEFAULT 0,
        seasonId TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE championships (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE matches (
        id TEXT PRIMARY KEY,
        championshipId TEXT,
        data TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE seasons (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY,
        data TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE player_season_stats (
        seasonId TEXT NOT NULL,
        playerId TEXT NOT NULL,
        matchesPlayed INTEGER DEFAULT 0,
        wins INTEGER DEFAULT 0,
        losses INTEGER DEFAULT 0,
        goals INTEGER DEFAULT 0,
        ownGoals INTEGER DEFAULT 0,
        assists INTEGER DEFAULT 0,
        vices INTEGER DEFAULT 0,
        finals INTEGER DEFAULT 0,
        titles INTEGER DEFAULT 0,
        PRIMARY KEY (seasonId, playerId)
      )
    ''');
  }

  Future<void> insertPlayer(Map<String, dynamic> player) async {
    final db = await database;
    await db.insert('players', player, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePlayer(Map<String, dynamic> player) async {
    final db = await database;
    await db.update('players', player, where: 'id = ?', whereArgs: [player['id']]);
  }

  Future<void> deletePlayer(String id) async {
    final db = await database;
    await db.delete('players', where: 'id = ?', whereArgs: [id]);
    await db.delete('player_season_stats', where: 'playerId = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAllPlayers() async {
    final db = await database;
    return db.query('players', orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getPlayer(String id) async {
    final db = await database;
    final results = await db.query('players', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> savePlayerSeasonStats(Map<String, dynamic> stats) async {
    final db = await database;
    await db.insert('player_season_stats', stats, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getPlayerSeasonStats(String seasonId, String playerId) async {
    final db = await database;
    final results = await db.query(
      'player_season_stats',
      where: 'seasonId = ? AND playerId = ?',
      whereArgs: [seasonId, playerId],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getPlayerSeasonStatsBySeason(String seasonId) async {
    final db = await database;
    return db.query('player_season_stats', where: 'seasonId = ?', whereArgs: [seasonId]);
  }

  Future<void> deletePlayerSeasonStatsBySeason(String seasonId) async {
    final db = await database;
    await db.delete('player_season_stats', where: 'seasonId = ?', whereArgs: [seasonId]);
  }

  Future<void> deletePlayerSeasonStatsByPlayer(String playerId) async {
    final db = await database;
    await db.delete('player_season_stats', where: 'playerId = ?', whereArgs: [playerId]);
  }

  Future<void> incrementPlayerSeasonStats(
    String seasonId,
    String playerId, {
    int matchesDelta = 0,
    int winsDelta = 0,
    int lossesDelta = 0,
    int goalsDelta = 0,
    int ownGoalsDelta = 0,
    int assistsDelta = 0,
    int vicesDelta = 0,
    int finalsDelta = 0,
    int titlesDelta = 0,
  }) async {
    final current = await getPlayerSeasonStats(seasonId, playerId);
    final updated = {
      'seasonId': seasonId,
      'playerId': playerId,
      'matchesPlayed': ((current?['matchesPlayed'] as int?) ?? 0) + matchesDelta,
      'wins': ((current?['wins'] as int?) ?? 0) + winsDelta,
      'losses': ((current?['losses'] as int?) ?? 0) + lossesDelta,
      'goals': ((current?['goals'] as int?) ?? 0) + goalsDelta,
      'ownGoals': ((current?['ownGoals'] as int?) ?? 0) + ownGoalsDelta,
      'assists': ((current?['assists'] as int?) ?? 0) + assistsDelta,
      'vices': ((current?['vices'] as int?) ?? 0) + vicesDelta,
      'finals': ((current?['finals'] as int?) ?? 0) + finalsDelta,
      'titles': ((current?['titles'] as int?) ?? 0) + titlesDelta,
    };
    await savePlayerSeasonStats(updated);
  }

  Future<void> saveChampionship(String id, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('championships', {'id': id, 'data': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteChampionship(String id) async {
    final db = await database;
    await db.delete('championships', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAllChampionships() async {
    final db = await database;
    final rows = await db.query('championships');
    return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>?> getChampionship(String id) async {
    final db = await database;
    final results = await db.query('championships', where: 'id = ?', whereArgs: [id]);
    if (results.isEmpty) return null;
    return jsonDecode(results.first['data'] as String) as Map<String, dynamic>;
  }

  Future<void> saveMatch(String id, String championshipId, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('matches', {'id': id, 'championshipId': championshipId, 'data': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteMatch(String id) async {
    final db = await database;
    await db.delete('matches', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAllMatches() async {
    final db = await database;
    final rows = await db.query('matches', orderBy: 'rowid DESC');
    return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> getMatchesByChampionship(String championshipId) async {
    final db = await database;
    final rows = await db.query('matches', where: 'championshipId = ?', whereArgs: [championshipId]);
    return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>?> getMatch(String id) async {
    final db = await database;
    final results = await db.query('matches', where: 'id = ?', whereArgs: [id]);
    if (results.isEmpty) return null;
    return jsonDecode(results.first['data'] as String) as Map<String, dynamic>;
  }

  Future<void> saveSeason(String id, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('seasons', {'id': id, 'data': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSeason(String id) async {
    final db = await database;
    await db.delete('seasons', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAllSeasons() async {
    final db = await database;
    final rows = await db.query('seasons');
    return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }

  Future<void> saveSettings(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('settings', {'id': 1, 'data': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getSettings() async {
    final db = await database;
    final results = await db.query('settings', where: 'id = ?', whereArgs: [1]);
    if (results.isEmpty) return null;
    return jsonDecode(results.first['data'] as String) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> exportAll() async {
    return {
      'players': await getAllPlayers(),
      'playerSeasonStats': await _exportPlayerSeasonStats(),
      'championships': await getAllChampionships(),
      'matches': await getAllMatches(),
      'seasons': await getAllSeasons(),
      'settings': await getSettings(),
    };
  }

  Future<List<Map<String, dynamic>>> _exportPlayerSeasonStats() async {
    final db = await database;
    return db.query('player_season_stats');
  }

  Future<void> importSelected(
    Map<String, dynamic> data, {
    bool importPlayers = true,
    bool importPlayerStats = true,
    bool importChampionships = true,
    bool importMatches = true,
    bool importSeasons = true,
    bool importSettings = true,
    bool overwrite = true,
  }) async {
    final db = await database;

    if (overwrite) {
      // ── Modo SOBRESCREVER ──────────────────────────────────────────────────
      await db.transaction((txn) async {
        if (importPlayers) {
          // Antes de apagar, resolve duplicatas por nome dentro do próprio backup.
          // Se houver 2 jogadores com mesmo nome no backup, o último vence.
          final backupPlayers = _mapList(data['players']);
          final deduped = <String, Map<String, dynamic>>{};
          for (final player in backupPlayers) {
            final nameKey = ((player['name'] as String?) ?? '').trim().toLowerCase();
            deduped[nameKey] = player; // sobrescreve: último vence
          }
          final playersToInsert = deduped.values.toList();

          await txn.delete('players');
          if (importPlayerStats) await txn.delete('player_season_stats');

          for (final player in playersToInsert) {
            await txn.insert('players', player,
                conflictAlgorithm: ConflictAlgorithm.replace);
          }

          if (importPlayerStats) {
            // Só insere stats cujo playerId exista no backup deduplicado
            final validIds = playersToInsert
                .map((p) => p['id'] as String? ?? '')
                .toSet();
            for (final stats in _mapList(data['playerSeasonStats'])) {
              final pid = stats['playerId'] as String? ?? '';
              if (!validIds.contains(pid)) continue;
              await txn.insert('player_season_stats', stats,
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        } else if (importPlayerStats) {
          // Importar só stats sem importar jogadores:
          // só aplica stats de jogadores que já existem no banco.
          final existingIds = (await txn.query('players', columns: ['id']))
              .map((r) => r['id'] as String)
              .toSet();
          await txn.delete('player_season_stats');
          for (final stats in _mapList(data['playerSeasonStats'])) {
            final pid = stats['playerId'] as String? ?? '';
            if (!existingIds.contains(pid)) continue;
            await txn.insert('player_season_stats', stats,
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        if (importChampionships) {
          await txn.delete('championships');
          for (final championship in _mapList(data['championships'])) {
            await txn.insert(
              'championships',
              {'id': championship['id'], 'data': jsonEncode(championship)},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        if (importMatches) {
          await txn.delete('matches');
          for (final match in _mapList(data['matches'])) {
            await txn.insert(
              'matches',
              {
                'id': match['id'],
                'championshipId': match['championshipId'],
                'data': jsonEncode(match),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        if (importSeasons) {
          await txn.delete('seasons');
          for (final season in _mapList(data['seasons'])) {
            await txn.insert(
              'seasons',
              {'id': season['id'], 'data': jsonEncode(season)},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        if (importSettings && data['settings'] != null) {
          await txn.delete('settings');
          await txn.insert(
            'settings',
            {'id': 1, 'data': jsonEncode(data['settings'])},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      return;
    }

    // ── Modo JUNTAR ───────────────────────────────────────────────────────────

    // 1) Temporadas: mapa nome → id existente no banco
    final Map<String, String> existingSeasonNameToId = {};
    // oldSeasonId (do backup) → resolvedSeasonId (no banco após import)
    final Map<String, String> seasonIdRemap = {};

    if (importSeasons) {
      final existingRows = await db.query('seasons');
      for (final row in existingRows) {
        final decoded =
            jsonDecode(row['data'] as String) as Map<String, dynamic>;
        final name =
            ((decoded['name'] as String?) ?? '').trim().toLowerCase();
        final id = row['id'] as String;
        if (name.isNotEmpty) existingSeasonNameToId[name] = id;
      }

      for (final season in _mapList(data['seasons'])) {
        final backupId = season['id'] as String? ?? '';
        final backupName = ((season['name'] as String?) ?? '').trim();
        final backupNameKey = backupName.toLowerCase();

        if (existingSeasonNameToId.containsKey(backupNameKey)) {
          final existingId = existingSeasonNameToId[backupNameKey]!;
          seasonIdRemap[backupId] = existingId;
        } else {
          await db.insert(
            'seasons',
            {'id': backupId, 'data': jsonEncode(season)},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          seasonIdRemap[backupId] = backupId;
          existingSeasonNameToId[backupNameKey] = backupId;
        }
      }
    }

    // 2) Jogadores: juntar somando stats globais; não duplicar por nome
    if (importPlayers) {
      final existingRows = await db.query('players');
      final Map<String, Map<String, dynamic>> existingById = {
        for (final r in existingRows) r['id'] as String: r,
      };
      final Map<String, String> existingNameToId = {
        for (final r in existingRows)
          ((r['name'] as String?) ?? '').trim().toLowerCase():
              r['id'] as String,
      };

      for (final player in _mapList(data['players'])) {
        final backupPlayerId = player['id'] as String? ?? '';
        final backupName = ((player['name'] as String?) ?? '').trim();
        final backupNameKey = backupName.toLowerCase();

        if (existingById.containsKey(backupPlayerId)) {
          final existing =
              Map<String, dynamic>.from(existingById[backupPlayerId]!);
          final merged = _mergePlayers(existing, player);
          await db.update('players', merged,
              where: 'id = ?', whereArgs: [backupPlayerId]);
        } else if (existingNameToId.containsKey(backupNameKey)) {
          final existingId = existingNameToId[backupNameKey]!;
          final existing =
              Map<String, dynamic>.from(existingById[existingId]!);
          final merged = _mergePlayers(existing, player);
          await db.update('players', merged,
              where: 'id = ?', whereArgs: [existingId]);
        } else {
          await db.insert('players', player,
              conflictAlgorithm: ConflictAlgorithm.ignore);
          existingById[backupPlayerId] = player;
          existingNameToId[backupNameKey] = backupPlayerId;
        }
      }
    }

    // 3) player_season_stats: soma se jogador existir, ignora se não existir
    if (importPlayerStats) {
      // IDs de jogadores que existem no banco (após possível import acima)
      final existingPlayerIds = (await db.query('players', columns: ['id']))
          .map((r) => r['id'] as String)
          .toSet();

      for (final stats in _mapList(data['playerSeasonStats'])) {
        final backupSeasonId = stats['seasonId'] as String? ?? '';
        final playerId = stats['playerId'] as String? ?? '';

        // Ignora stats de jogadores que não existem no banco
        if (!existingPlayerIds.contains(playerId)) continue;

        final resolvedSeasonId = importSeasons
            ? (seasonIdRemap[backupSeasonId] ?? backupSeasonId)
            : backupSeasonId;

        final existing = await db.query(
          'player_season_stats',
          where: 'seasonId = ? AND playerId = ?',
          whereArgs: [resolvedSeasonId, playerId],
        );

        if (existing.isNotEmpty) {
          final cur = existing.first;
          final merged = {
            'seasonId': resolvedSeasonId,
            'playerId': playerId,
            'matchesPlayed':
                _sumInt(cur['matchesPlayed'], stats['matchesPlayed']),
            'wins': _sumInt(cur['wins'], stats['wins']),
            'losses': _sumInt(cur['losses'], stats['losses']),
            'goals': _sumInt(cur['goals'], stats['goals']),
            'ownGoals': _sumInt(cur['ownGoals'], stats['ownGoals']),
            'assists': _sumInt(cur['assists'], stats['assists']),
            'vices': _sumInt(cur['vices'], stats['vices']),
            'finals': _sumInt(cur['finals'], stats['finals']),
            'titles': _sumInt(cur['titles'], stats['titles']),
          };
          await db.update(
            'player_season_stats',
            merged,
            where: 'seasonId = ? AND playerId = ?',
            whereArgs: [resolvedSeasonId, playerId],
          );
        } else {
          final newStats = Map<String, dynamic>.from(stats);
          newStats['seasonId'] = resolvedSeasonId;
          await db.insert('player_season_stats', newStats,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    }

    // 4) Campeonatos
    if (importChampionships) {
      for (final championship in _mapList(data['championships'])) {
        await db.insert(
          'championships',
          {'id': championship['id'], 'data': jsonEncode(championship)},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    // 5) Partidas
    if (importMatches) {
      for (final match in _mapList(data['matches'])) {
        await db.insert(
          'matches',
          {
            'id': match['id'],
            'championshipId': match['championshipId'],
            'data': jsonEncode(match),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    // 6) Configurações
    if (importSettings && data['settings'] != null) {
      await db.insert(
        'settings',
        {'id': 1, 'data': jsonEncode(data['settings'])},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Soma as stats numéricas de dois mapas de jogador (mantém metadados do existente).
  Map<String, dynamic> _mergePlayers(
    Map<String, dynamic> existing,
    Map<String, dynamic> incoming,
  ) {
    return {
      ...existing,
      'matchesPlayed': _sumInt(existing['matchesPlayed'], incoming['matchesPlayed']),
      'wins': _sumInt(existing['wins'], incoming['wins']),
      'losses': _sumInt(existing['losses'], incoming['losses']),
      'goals': _sumInt(existing['goals'], incoming['goals']),
      'ownGoals': _sumInt(existing['ownGoals'], incoming['ownGoals']),
      'assists': _sumInt(existing['assists'], incoming['assists']),
      'vices': _sumInt(existing['vices'], incoming['vices']),
      'finals': _sumInt(existing['finals'], incoming['finals']),
      'titles': _sumInt(existing['titles'], incoming['titles']),
      // Preenche foto/descrição se estiver vazia no existente
      'photoPath': (existing['photoPath'] as String? ?? '').isNotEmpty
          ? existing['photoPath']
          : incoming['photoPath'],
      'description': (existing['description'] as String? ?? '').isNotEmpty
          ? existing['description']
          : incoming['description'],
    };
  }

  int _sumInt(dynamic a, dynamic b) => ((a as int?) ?? 0) + ((b as int?) ?? 0);

  Future<void> importAll(Map<String, dynamic> data) async {
    await importSelected(data);
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    return (value as List? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}