import '../database/database_helper.dart';
import '../models/championship.dart';
import 'settings_repository.dart';

class ChampionshipRepository {
  final DatabaseHelper _db = DatabaseHelper();
  final SeasonRepository _seasonRepo = SeasonRepository();

  Future<List<Championship>> getAll({String? seasonId, bool all = false}) async {
    final rows = await _db.getAllChampionships();
    final items = rows.map(Championship.fromMap).toList();
    if (all || seasonId == null) return items;
    return items.where((c) => c.seasonId == seasonId).toList();
  }

  Future<Championship?> getById(String id) async {
    final row = await _db.getChampionship(id);
    return row != null ? Championship.fromMap(row) : null;
  }

  Future<void> save(Championship championship) async {
    final season = await _seasonRepo.ensureCurrentSeason();
    championship.seasonId ??= season.id;
    await _db.saveChampionship(championship.id, championship.toMap());
  }

  Future<void> delete(String id) async {
    await _db.deleteChampionship(id);
  }
}
