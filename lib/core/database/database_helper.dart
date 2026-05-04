import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try { await db.execute('ALTER TABLE players ADD COLUMN assists INTEGER DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE matches ADD COLUMN seasonId TEXT'); } catch (_) {}
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
  }

  Future<void> deletePlayersBySeason(String seasonId) async {
    final db = await database;
    await db.delete('players', where: 'seasonId = ?', whereArgs: [seasonId]);
  }

  Future<List<Map<String, dynamic>>> getAllPlayers() async {
    final db = await database;
    return await db.query('players', orderBy: 'name ASC');
  }

  Future<List<Map<String, dynamic>>> getPlayersBySeason(String seasonId) async {
    final db = await database;
    return await db.query('players', where: 'seasonId = ?', whereArgs: [seasonId], orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getPlayer(String id) async {
    final db = await database;
    final results = await db.query('players', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
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
      'championships': await getAllChampionships(),
      'matches': await getAllMatches(),
      'seasons': await getAllSeasons(),
      'settings': await getSettings(),
    };
  }

  Future<void> importAll(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('players');
      await txn.delete('championships');
      await txn.delete('matches');
      await txn.delete('seasons');
      await txn.delete('settings');

      for (final p in (data['players'] as List? ?? [])) {
        await txn.insert('players', p as Map<String, dynamic>, conflictAlgorithm: ConflictAlgorithm.replace);
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
