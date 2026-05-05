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
      version: 3,
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
      await db.execute('''
        CREATE TABLE IF NOT EXISTS player_season_stats (
          seasonId TEXT NOT NULL,
          playerId TEXT NOT NULL,
          matchesPlayed INTEGER DEFAULT 0,
          wins INTEGER DEFAULT 0,
          losses INTEGER DEFAULT 0,
          goals INTEGER DEFAULT 0,
          assists INTEGER DEFAULT 0,
          vices INTEGER DEFAULT 0,
          finals INTEGER DEFAULT 0,
          titles INTEGER DEFAULT 0,
          PRIMARY KEY (seasonId, playerId)
        )
      ''');

      await _migrateLegacyPlayersToGlobal(db);
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
        final assists = (entry['assists'] as int?) ?? 0;
        final vices = (entry['vices'] as int?) ?? 0;
        final finals = (entry['finals'] as int?) ?? 0;
        final titles = (entry['titles'] as int?) ?? 0;

        merged['matchesPlayed'] += matchesPlayed;
        merged['wins'] += wins;
        merged['losses'] += losses;
        merged['goals'] += goals;
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
            'assists': 0,
            'vices': 0,
            'finals': 0,
            'titles': 0,
          });
          totals['matchesPlayed'] = totals['matchesPlayed']! + matchesPlayed;
          totals['wins'] = totals['wins']! + wins;
          totals['losses'] = totals['losses']! + losses;
          totals['goals'] = totals['goals']! + goals;
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

  Future<void> importAll(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('players');
      await txn.delete('player_season_stats');
      await txn.delete('championships');
      await txn.delete('matches');
      await txn.delete('seasons');
      await txn.delete('settings');

      for (final p in (data['players'] as List? ?? [])) {
        await txn.insert('players', p as Map<String, dynamic>, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final s in (data['playerSeasonStats'] as List? ?? [])) {
        await txn.insert('player_season_stats', s as Map<String, dynamic>, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final c in (data['championships'] as List? ?? [])) {
        await txn.insert('championships', {'id': (c as Map)['id'], 'data': jsonEncode(c)}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final m in (data['matches'] as List? ?? [])) {
        await txn.insert('matches', {'id': (m as Map)['id'], 'championshipId': m['championshipId'], 'data': jsonEncode(m)}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final s in (data['seasons'] as List? ?? [])) {
        await txn.insert('seasons', {'id': (s as Map)['id'], 'data': jsonEncode(s)}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (data['settings'] != null) {
        await txn.insert('settings', {'id': 1, 'data': jsonEncode(data['settings'])}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
