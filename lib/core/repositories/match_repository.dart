import '../database/database_helper.dart';
import '../models/match.dart';
import 'championship_repository.dart';
import 'settings_repository.dart';

class MatchRepository {
  final DatabaseHelper _db = DatabaseHelper();
  final SeasonRepository _seasonRepo = SeasonRepository();
  final ChampionshipRepository _champRepo = ChampionshipRepository();

  Future<List<MatchModel>> getAll({String? seasonId, bool all = false}) async {
    final rows = await _db.getAllMatches();
    final items = rows.map(MatchModel.fromMap).toList();
    if (all || seasonId == null) return items;
    final champs = {for (final c in await _champRepo.getAll(all: true)) c.id: c.seasonId};
    return items.where((m) {
      if (m.seasonId != null) return m.seasonId == seasonId;
      return champs[m.championshipId] == seasonId;
    }).toList();
  }

  Future<List<MatchModel>> getByChampionship(String championshipId) async {
    final rows = await _db.getMatchesByChampionship(championshipId);
    return rows.map(MatchModel.fromMap).toList();
  }

  Future<MatchModel?> getById(String id) async {
    final row = await _db.getMatch(id);
    return row != null ? MatchModel.fromMap(row) : null;
  }

  Future<void> save(MatchModel match) async {
    final season = await _seasonRepo.ensureCurrentSeason();
    match.seasonId ??= season.id;
    await _db.saveMatch(match.id, match.championshipId, match.toMap());
  }

  Future<void> delete(String id) async {
    await _db.deleteMatch(id);
  }
}
