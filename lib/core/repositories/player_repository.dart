import '../database/database_helper.dart';
import '../models/player.dart';
import 'settings_repository.dart';

class PlayerRepository {
  final DatabaseHelper _db = DatabaseHelper();
  final SeasonRepository _seasonRepo = SeasonRepository();

  Future<List<Player>> getAll({String? seasonId, bool all = false}) async {
    final rows = seasonId != null
        ? await _db.getPlayersBySeason(seasonId)
        : all
            ? await _db.getAllPlayers()
            : await _db.getPlayersBySeason((await _seasonRepo.ensureCurrentSeason()).id);
    return rows.map(Player.fromMap).toList();
  }

  Future<Player?> getById(String id) async {
    final row = await _db.getPlayer(id);
    return row != null ? Player.fromMap(row) : null;
  }

  Future<void> save(Player player) async {
    final season = await _seasonRepo.ensureCurrentSeason();
    await _db.insertPlayer(player.copyWith(seasonId: player.seasonId ?? season.id).toMap());
  }

  Future<void> update(Player player) async {
    await _db.updatePlayer(player.toMap());
  }

  Future<void> delete(String id) async {
    await _db.deletePlayer(id);
  }

  Future<void> deleteBySeason(String seasonId) async {
    await _db.deletePlayersBySeason(seasonId);
  }

  Future<void> updateStats(String id,
      {int matchesDelta = 0,
      int winsDelta = 0,
      int lossesDelta = 0,
      int goalsDelta = 0,
      int assistsDelta = 0,
      int vicesDelta = 0,
      int finalsDelta = 0,
      int titlesDelta = 0}) async {
    final player = await getById(id);
    if (player == null) return;
    final updated = player.copyWith(
      matchesPlayed: player.matchesPlayed + matchesDelta,
      wins: player.wins + winsDelta,
      losses: player.losses + lossesDelta,
      goals: player.goals + goalsDelta,
      assists: player.assists + assistsDelta,
      vices: player.vices + vicesDelta,
      finals: player.finals + finalsDelta,
      titles: player.titles + titlesDelta,
    );
    await update(updated);
  }

  Future<List<Player>> clonePlayersForSeason(String seasonId, {required List<Player> sourcePlayers}) async {
    final clones = <Player>[];
    for (final p in sourcePlayers) {
      final clone = p.resetForSeason(seasonId: seasonId, newId: '${p.id}_$seasonId');
      clones.add(clone);
      await save(clone);
    }
    return clones;
  }
}
