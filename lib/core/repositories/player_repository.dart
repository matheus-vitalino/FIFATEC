import '../database/database_helper.dart';
import '../models/player.dart';
import '../models/player_season_stats.dart';
import 'settings_repository.dart';

class PlayerRepository {
  final DatabaseHelper _db = DatabaseHelper();
  final SeasonRepository _seasonRepo = SeasonRepository();

  Future<List<Player>> getAll({bool all = false}) async {
    final rows = await _db.getAllPlayers();
    final players = rows.map(Player.fromMap).toList();
    return players;
  }

  Future<List<Player>> getPlayersForSeason(String seasonId) async {
    final players = await getAll();
    final statsRows = await _db.getPlayerSeasonStatsBySeason(seasonId);
    final statsByPlayerId = {
      for (final row in statsRows) row['playerId'] as String: PlayerSeasonStats.fromMap(row),
    };

    return players
        .map((p) {
          final stats = statsByPlayerId[p.id];
          if (stats == null) return p.copyWith();
          return p.copyWith(
            matchesPlayed: stats.matchesPlayed,
            wins: stats.wins,
            losses: stats.losses,
            goals: stats.goals,
            assists: stats.assists,
            vices: stats.vices,
            finals: stats.finals,
            titles: stats.titles,
          );
        })
        .toList();
  }

  Future<Player?> getById(String id) async {
    final row = await _db.getPlayer(id);
    return row != null ? Player.fromMap(row) : null;
  }

  Future<void> save(Player player) async {
    await _db.insertPlayer(player.toMap());
    final season = await _seasonRepo.ensureCurrentSeason();
    final existing = await _db.getPlayerSeasonStats(season.id, player.id);
    if (existing == null) {
      await _db.savePlayerSeasonStats(PlayerSeasonStats(seasonId: season.id, playerId: player.id).toMap());
    }
  }

  Future<void> update(Player player) async {
    await _db.updatePlayer(player.toMap());
  }

  Future<void> delete(String id) async {
    await _db.deletePlayer(id);
  }

  Future<void> resetStatsBySeason(String seasonId) async {
    await _db.deletePlayerSeasonStatsBySeason(seasonId);
  }

  Future<void> updateStats(
    String id, {
    String? seasonId,
    int matchesDelta = 0,
    int winsDelta = 0,
    int lossesDelta = 0,
    int goalsDelta = 0,
    int assistsDelta = 0,
    int vicesDelta = 0,
    int finalsDelta = 0,
    int titlesDelta = 0,
  }) async {
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

    final season = seasonId ?? (await _seasonRepo.ensureCurrentSeason()).id;
    await _db.incrementPlayerSeasonStats(
      season,
      id,
      matchesDelta: matchesDelta,
      winsDelta: winsDelta,
      lossesDelta: lossesDelta,
      goalsDelta: goalsDelta,
      assistsDelta: assistsDelta,
      vicesDelta: vicesDelta,
      finalsDelta: finalsDelta,
      titlesDelta: titlesDelta,
    );
  }

  Future<void> ensureSeasonStatsForAllPlayers(String seasonId) async {
    final players = await getAll();
    for (final player in players) {
      final existing = await _db.getPlayerSeasonStats(seasonId, player.id);
      if (existing == null) {
        await _db.savePlayerSeasonStats(PlayerSeasonStats(seasonId: seasonId, playerId: player.id).toMap());
      }
    }
  }

  Future<List<Player>> getAllForSeason(String seasonId) => getPlayersForSeason(seasonId);

  Future<List<Player>> clonePlayersForSeason(
    String seasonId, {
    required List<Player> sourcePlayers,
  }) async {
    await ensureSeasonStatsForAllPlayers(seasonId);
    return sourcePlayers;
  }
}
