import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/player.dart';
import '../../core/models/match.dart';
import '../../core/models/season.dart';
import '../../core/repositories/player_repository.dart';
import '../../core/repositories/match_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/season_manager.dart';
import '../../shared/widgets/custom_app_bar.dart';
import '../../shared/widgets/player_avatar.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen>
    with SingleTickerProviderStateMixin {
  final _playerRepo = PlayerRepository();
  final _matchRepo = MatchRepository();
  final _seasonManager = SeasonManager.instance;
  final _settingsRepo = SettingsRepository();

  List<Player> _players = [];
  List<MatchModel> _matches = [];
  List<Season> _seasons = [];
  Season? _selectedSeason;
  AppSettings _settings = AppSettings();
  bool _loading = true;
  bool _busy = false;

  bool _trioByStats = true;

  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _seasonManager.getSeasons(),
      _seasonManager.getActiveSeason(),
      _settingsRepo.get(),
    ]);
    _seasons = results[0] as List<Season>;
    _selectedSeason = results[1] as Season?;
    _settings = results[2] as AppSettings;
    _selectedSeason ??= _seasons.isNotEmpty ? _seasons.first : null;
    _players = _selectedSeason == null
        ? []
        : await _playerRepo.getPlayersForSeason(_selectedSeason!.id);
    _matches = _selectedSeason == null
        ? []
        : (await _matchRepo.getAll(seasonId: _selectedSeason!.id))
            .where((m) => m.status == MatchStatus.finished)
            .toList();
    if (mounted) setState(() => _loading = false);
  }

  List<Player> get _byGoals =>
      [..._players]..sort((a, b) => b.goals.compareTo(a.goals));
  List<Player> get _byWins =>
      [..._players]..sort(_seasonManager.comparePlayersBySeasonRanking);
  List<Player> get _byTitles =>
      [..._players]..sort((a, b) => b.titles.compareTo(a.titles));
  List<Player> get _byOwnGoals =>
      [..._players]..sort((a, b) => b.ownGoals.compareTo(a.ownGoals));

  List<_Duo> get _bestDuos {
    final Map<String, _Duo> duos = {};
    final playersById = {for (final p in _players) p.id: p};
    final useGoals = _settings.duoRankingMode == DuoRankingMode.sharedGoals;

    if (useGoals) {
      for (final match in _matches) {
        for (final team in [match.teamA, match.teamB]) {
          final goalsByPlayer = <String, int>{};
          for (final goal in match.goals.where((g) =>
              g.teamId == team.id &&
              !g.isOwnGoal &&
              g.playerId != 'unknown')) {
            goalsByPlayer[goal.playerId] =
                (goalsByPlayer[goal.playerId] ?? 0) + 1;
          }
          final entries = goalsByPlayer.entries.toList();
          for (int i = 0; i < entries.length - 1; i++) {
            for (int j = i + 1; j < entries.length; j++) {
              final aId = entries[i].key;
              final bId = entries[j].key;
              final sorted = [aId, bId]..sort();
              final a = playersById[sorted[0]];
              final b = playersById[sorted[1]];
              if (a == null || b == null) continue;
              final key = '${sorted[0]}_${sorted[1]}';
              final scoreDelta = entries[i].value * entries[j].value;
              final sharedGoals = entries[i].value + entries[j].value;
              final existing = duos[key];
              if (existing == null) {
                duos[key] = _Duo(a, b, scoreDelta, sharedGoals, 1);
              } else {
                duos[key] = existing.copyWith(
                  scoreDelta: scoreDelta,
                  sharedGoals: sharedGoals,
                  sharedMatches: 1,
                );
              }
            }
          }
        }
      }
      final list = duos.values.toList()
        ..sort((a, b) {
          final sc = b.score.compareTo(a.score);
          if (sc != 0) return sc;
          return b.sharedGoals.compareTo(a.sharedGoals);
        });
      return list.where((d) => d.score > 0).take(10).toList();
    }

    for (int i = 0; i < _players.length - 1; i++) {
      for (int j = i + 1; j < _players.length; j++) {
        final a = _players[i], b = _players[j];
        final score = (a.titles + b.titles) * 10 + a.wins + b.wins;
        duos['${a.id}_${b.id}'] = _Duo(a, b, score, 0, 0);
      }
    }
    final list = duos.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return list.where((d) => d.score > 0).take(10).toList();
  }

  List<_Trio> get _bestTrios {
    if (!_trioByStats) {
      final List<_Trio> trios = [];

      for (int i = 0; i < _players.length - 2; i++) {
        for (int j = i + 1; j < _players.length - 1; j++) {
          for (int k = j + 1; k < _players.length; k++) {
            final a = _players[i];
            final b = _players[j];
            final c = _players[k];
            final totalWins = a.wins + b.wins + c.wins;
            final totalGoals = a.goals + b.goals + c.goals;
            final totalMatches =
                a.matchesPlayed + b.matchesPlayed + c.matchesPlayed;

            // Super trio da temporada:
            // vitória tem peso maior, mas gols também ajudam a formar o trio.
            final score = (totalWins * 3) + totalGoals;

            trios.add(_Trio(
              a,
              b,
              c,
              score,
              0,
              totalWins: totalWins,
              totalGoals: totalGoals,
              totalMatches: totalMatches,
            ));
          }
        }
      }

      trios.sort((a, b) {
        final score = b.score.compareTo(a.score);
        if (score != 0) return score;

        final wins = b.totalWins.compareTo(a.totalWins);
        if (wins != 0) return wins;

        final goals = b.totalGoals.compareTo(a.totalGoals);
        if (goals != 0) return goals;

        return b.totalMatches.compareTo(a.totalMatches);
      });

      return trios
          .where((t) =>
              t.totalWins > 0 || t.totalGoals > 0 || t.totalMatches > 0)
          .take(10)
          .toList();
    }

    final Map<String, _Trio> trios = {};
    final playersById = {for (final p in _players) p.id: p};

    for (final match in _matches) {
      for (final team in [match.teamA, match.teamB]) {
        final ids = team.activePlayers
            .map((tp) => tp.playerId)
            .where((id) => playersById.containsKey(id))
            .toList()
          ..sort();

        for (int i = 0; i < ids.length - 2; i++) {
          for (int j = i + 1; j < ids.length - 1; j++) {
            for (int k = j + 1; k < ids.length; k++) {
              final a = playersById[ids[i]];
              final b = playersById[ids[j]];
              final c = playersById[ids[k]];
              if (a == null || b == null || c == null) continue;
              final key = '${ids[i]}_${ids[j]}_${ids[k]}';
              final didWin = match.winnerId == team.id ? 1 : 0;
              final existing = trios[key];
              if (existing == null) {
                trios[key] = _Trio(
                  a,
                  b,
                  c,
                  didWin * 3,
                  1,
                  sharedWins: didWin,
                );
              } else {
                trios[key] = _Trio(
                  a,
                  b,
                  c,
                  existing.score + didWin * 3,
                  existing.sharedMatches + 1,
                  sharedWins: existing.sharedWins + didWin,
                );
              }
            }
          }
        }
      }
    }

    final list = trios.values.toList()
      ..sort((a, b) {
        final sc = b.score.compareTo(a.score);
        if (sc != 0) return sc;
        return b.sharedMatches.compareTo(a.sharedMatches);
      });
    return list.where((t) => t.sharedMatches > 0).take(10).toList();
  }

  Future<void> _selectSeason(Season season) async {
    setState(() => _busy = true);
    await _seasonManager.switchSeason(season.id);
    _selectedSeason = season;
    _players = await _playerRepo.getPlayersForSeason(season.id);
    _matches = (await _matchRepo.getAll(seasonId: season.id))
        .where((m) => m.status == MatchStatus.finished)
        .toList();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _selectCurrentSeason() async {
    final active = await _seasonManager.getActiveSeason();
    if (active != null) await _selectSeason(active);
  }

  Future<void> _createSeason() async {
    final ctrl =
        TextEditingController(text: 'Temporada ${DateTime.now().year}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nova Temporada',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome da temporada'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppColors.textHint))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Criar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final season =
        await _seasonManager.createNewSeason(name: ctrl.text.trim());
    _selectedSeason = season;
    _seasons = await _seasonManager.getSeasons();
    _players = await _playerRepo.getPlayersForSeason(season.id);
    _matches = (await _matchRepo.getAll(seasonId: season.id))
        .where((m) => m.status == MatchStatus.finished)
        .toList();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finishSeason() async {
    if (_selectedSeason == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Finalizar temporada?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Tem certeza que deseja finalizar "${_selectedSeason!.name}"?\n\nIsso não exclui os dados.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppColors.textHint))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.loss),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final season = await _seasonManager.finishSeason(_selectedSeason!.id);
    if (season != null) {
      _selectedSeason = season;
      _seasons = await _seasonManager.getSeasons();
      _players = await _playerRepo.getPlayersForSeason(season.id);
      _matches = (await _matchRepo.getAll(seasonId: season.id))
          .where((m) => m.status == MatchStatus.finished)
          .toList();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _unfinishSeason() async {
    if (_selectedSeason == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Desfinalizar temporada?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'A temporada "${_selectedSeason!.name}" voltará a ficar ativa.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppColors.textHint))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Desfinalizar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    _selectedSeason!.finishedAt = null;
    _selectedSeason!.goldenBallPlayerId = null;
    _selectedSeason!.goldenBallPlayerName = null;
    _selectedSeason!.goldenBallScore = null;
    await _seasonManager.saveSeason(_selectedSeason!);
    _seasons = await _seasonManager.getSeasons();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _deleteSeason() async {
    if (_selectedSeason == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir temporada?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Todos os dados de "${_selectedSeason!.name}" serão apagados permanentemente.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppColors.textHint))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir',
                  style: TextStyle(color: AppColors.loss))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await _seasonManager.deleteSeason(_selectedSeason!.id);
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _goPreviousSeason() async {
    if (_seasons.isEmpty || _selectedSeason == null) return;
    final idx = _seasons.indexWhere((s) => s.id == _selectedSeason!.id);
    if (idx < 0 || idx >= _seasons.length - 1) return;
    await _selectSeason(_seasons[idx + 1]);
  }

  Future<void> _renameSeason() async {
    if (_selectedSeason == null) return;
    final ctrl = TextEditingController(text: _selectedSeason!.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Renomear temporada',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppColors.textHint))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    _selectedSeason!.name = ctrl.text.trim();
    await _seasonManager.saveSeason(_selectedSeason!);
    _seasons = await _seasonManager.getSeasons();
    if (mounted) setState(() {});
  }

  bool get _isFinished => _selectedSeason?.finishedAt != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  backgroundColor: AppColors.background,
                  pinned: true,
                  floating: false,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: AppColors.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  title: const Text('Temporada',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold)),
                  centerTitle: true,
                  bottom: TabBar(
                    controller: _tab,
                    // Nova paleta: indicador Electric Lime, label Primary
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 3,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textHint,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: const [
                      Tab(text: 'Jogadores'),
                      Tab(text: 'Duplas'),
                      Tab(text: 'Trios'),
                      Tab(text: 'Categorias'),
                    ],
                  ),
                ),

                SliverToBoxAdapter(
                  child: _SeasonPanel(
                    selectedSeason: _selectedSeason,
                    seasons: _seasons,
                    busy: _busy,
                    isFinished: _isFinished,
                    onSeasonSelected: _selectSeason,
                    onCurrentSeason: _selectCurrentSeason,
                    onCreateSeason: _busy ? null : _createSeason,
                    onRenameSeason: _busy ? null : _renameSeason,
                    onPreviousSeason: _busy ? null : _goPreviousSeason,
                    onDeleteSeason: _busy ? null : _deleteSeason,
                    onFinishSeason: _busy ? null : _finishSeason,
                    onUnfinishSeason: _busy ? null : _unfinishSeason,
                  ),
                ),

                // Bola de Ouro — gradiente com nova paleta
                if (_isFinished && _byWins.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withOpacity(0.15),
                            AppColors.accentDark.withOpacity(0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.40)),
                      ),
                      child: Row(
                        children: [
                          const Text('🏅', style: TextStyle(fontSize: 24)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Bola de Ouro',
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1)),
                                Text(
                                  _selectedSeason?.goldenBallPlayerName ??
                                      _byWins.first.name,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Top 1 da temporada finalizada',
                                  style: TextStyle(
                                      color: AppColors.textHint, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              Text(
                                _byWins.first.wins.toString(),
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18),
                              ),
                              const Text('vitórias',
                                  style: TextStyle(
                                      color: AppColors.textHint, fontSize: 10)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              body: TabBarView(
                controller: _tab,
                children: [
                  _buildPlayerRanking(context),
                  _buildDuoRanking(context),
                  _buildTrioRanking(context),
                  _buildCategoryRanking(context),
                ],
              ),
            ),
    );
  }

  Widget _buildPlayerRanking(BuildContext context) {
    final players = _byWins;
    if (players.isEmpty) {
      return const _EmptyRanking(
          message: 'Jogue partidas para gerar o ranking');
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 80),
      itemCount: players.length,
      itemBuilder: (_, i) {
        final p = players[i];
        return _RankCard(
          position: i + 1,
          name: p.name,
          photoPath: p.photoPath,
          subtitle:
              '${p.wins} vitórias • ${p.goals} gols • ${p.titles} títulos • ${p.ownGoals} GC',
          value: p.wins,
          valueLabel: 'V',
          index: i,
          onTap: () => Navigator.pushNamed(context, '/players/profile',
              arguments: p.id),
        );
      },
    );
  }

  Widget _buildDuoRanking(BuildContext context) {
    final duos = _bestDuos;
    if (duos.isEmpty) {
      return const _EmptyRanking(message: 'Jogue partidas para gerar duplas');
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 80),
      itemCount: duos.length,
      itemBuilder: (_, i) => _DuoCard(
        duo: duos[i],
        position: i + 1,
        index: i,
        mode: _settings.duoRankingMode,
      ),
    );
  }

  Widget _buildTrioRanking(BuildContext context) {
    final trios = _bestTrios;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    label: 'Por histórico',
                    subtitle: 'Trios que jogaram juntos',
                    icon: Icons.history_rounded,
                    selected: _trioByStats,
                    onTap: () => setState(() => _trioByStats = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ModeButton(
                    label: 'Super trio',
                    subtitle: 'Vitórias + gols da temporada',
                    icon: Icons.auto_awesome_rounded,
                    selected: !_trioByStats,
                    onTap: () => setState(() => _trioByStats = false),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (trios.isEmpty)
          SliverFillRemaining(
            child: _EmptyRanking(
              message: _trioByStats
                  ? 'Ainda sem trios com histórico suficiente'
                  : 'Jogue partidas para gerar o Super Trio',
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                0, 0, 0, MediaQuery.of(context).padding.bottom + 80),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _TrioCard(
                    trio: trios[i],
                    position: i + 1,
                    index: i,
                    byStats: _trioByStats),
                childCount: trios.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryRanking(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 80),
      children: [
        _CategorySection(
          title: '🥅 Artilheiros',
          color: AppColors.goal,
          players: _byGoals.take(5).toList(),
          valueLabel: (p) => '${p.goals} gols',
        ),
        const SizedBox(height: 14),
        _CategorySection(
          title: '🏆 Campeões',
          color: AppColors.primary,
          players: _byTitles.take(5).toList(),
          valueLabel: (p) => '${p.titles} títulos',
        ),
        const SizedBox(height: 14),
        _CategorySection(
          title: '💪 Mais Vitórias',
          color: AppColors.win,
          players: _byWins.take(5).toList(),
          valueLabel: (p) => '${p.wins} vitórias',
        ),
        const SizedBox(height: 14),
        _CategorySection(
          title: '⚠️ Gols Contra',
          color: AppColors.loss,
          players:
              _byOwnGoals.where((p) => p.ownGoals > 0).take(5).toList(),
          valueLabel: (p) => '${p.ownGoals} GC',
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }
}

// ── _SeasonPanel ──────────────────────────────────────────────────

class _SeasonPanel extends StatefulWidget {
  final Season? selectedSeason;
  final List<Season> seasons;
  final bool busy;
  final bool isFinished;
  final ValueChanged<Season> onSeasonSelected;
  final VoidCallback onCurrentSeason;
  final VoidCallback? onCreateSeason;
  final VoidCallback? onRenameSeason;
  final VoidCallback? onPreviousSeason;
  final VoidCallback? onDeleteSeason;
  final VoidCallback? onFinishSeason;
  final VoidCallback? onUnfinishSeason;

  const _SeasonPanel({
    required this.selectedSeason,
    required this.seasons,
    required this.busy,
    required this.isFinished,
    required this.onSeasonSelected,
    required this.onCurrentSeason,
    this.onCreateSeason,
    this.onRenameSeason,
    this.onPreviousSeason,
    this.onDeleteSeason,
    this.onFinishSeason,
    this.onUnfinishSeason,
  });

  @override
  State<_SeasonPanel> createState() => _SeasonPanelState();
}

class _SeasonPanelState extends State<_SeasonPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.selectedSeason;
    final statusLabel = s == null
        ? 'Nenhuma temporada'
        : s.finishedAt != null
            ? '${s.name} · Finalizada'
            : s.isActive
                ? '${s.name} · Atual'
                : s.name;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Ícone com cor Electric Lime
                  const Icon(Icons.event_note_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusLabel,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
                  if (widget.busy)
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary))
                  else
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textHint,
                    ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(color: AppColors.border, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: widget.selectedSeason?.id,
                    decoration:
                        const InputDecoration(labelText: 'Selecionar temporada'),
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(color: AppColors.textPrimary),
                    items: widget.seasons
                        .map((s) =>
                            DropdownMenuItem(value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      final season =
                          widget.seasons.firstWhere((s) => s.id == id);
                      widget.onSeasonSelected(season);
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ActionChip(
                          label: 'Atual',
                          icon: Icons.refresh_rounded,
                          onTap: widget.onCurrentSeason),
                      _ActionChip(
                          label: 'Renomear',
                          icon: Icons.edit_rounded,
                          onTap: widget.onRenameSeason),
                      _ActionChip(
                          label: 'Nova',
                          icon: Icons.add_rounded,
                          onTap: widget.onCreateSeason),
                      _ActionChip(
                          label: 'Anterior',
                          icon: Icons.arrow_back_rounded,
                          onTap: widget.onPreviousSeason),
                      if (!widget.isFinished)
                        _ActionChip(
                            label: 'Finalizar',
                            icon: Icons.flag_rounded,
                            onTap: widget.onFinishSeason),
                      if (widget.isFinished)
                        _ActionChip(
                            label: 'Desfinalizar',
                            icon: Icons.undo_rounded,
                            onTap: widget.onUnfinishSeason),
                      _ActionChip(
                          label: 'Excluir',
                          icon: Icons.delete_rounded,
                          onTap: widget.onDeleteSeason,
                          danger: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  const _ActionChip(
      {required this.label,
      required this.icon,
      this.onTap,
      this.danger = false});

  @override
  Widget build(BuildContext context) {
    // Danger usa AppColors.loss; ações normais usam Electric Lime
    final color = danger ? AppColors.loss : AppColors.primary;
    return ActionChip(
      label: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      avatar: Icon(icon, size: 15, color: color),
      backgroundColor: color.withOpacity(0.10),
      side: BorderSide(color: color.withOpacity(0.30)),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color: selected ? AppColors.primary : AppColors.textHint,
                size: 20),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
            Text(subtitle,
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _EmptyRanking extends StatelessWidget {
  final String message;
  const _EmptyRanking({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.leaderboard_outlined,
                color: AppColors.textHint.withOpacity(0.5), size: 56),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ── Modelos internos ──────────────────────────────────────────────

class _Trio {
  final Player a, b, c;
  final int score;
  final int sharedMatches;
  final int sharedWins;
  final int totalWins;
  final int totalGoals;
  final int totalMatches;

  const _Trio(
    this.a,
    this.b,
    this.c,
    this.score,
    this.sharedMatches, {
    this.sharedWins = 0,
    this.totalWins = 0,
    this.totalGoals = 0,
    this.totalMatches = 0,
  });
}

class _Duo {
  final Player a, b;
  final int score;
  final int sharedGoals;
  final int sharedMatches;

  const _Duo(this.a, this.b, this.score, this.sharedGoals, this.sharedMatches);

  _Duo copyWith(
      {int scoreDelta = 0, int sharedGoals = 0, int sharedMatches = 0}) {
    return _Duo(
      a,
      b,
      score + scoreDelta,
      this.sharedGoals + sharedGoals,
      this.sharedMatches + sharedMatches,
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────

class _TrioCard extends StatelessWidget {
  final _Trio trio;
  final int position, index;
  final bool byStats;

  const _TrioCard(
      {required this.trio,
      required this.position,
      required this.index,
      required this.byStats});

  @override
  Widget build(BuildContext context) {
    final isTop3 = position <= 3;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Top 3 recebe gradiente sutil com Navy → Deep Steel
        gradient: isTop3
            ? LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.08),
                  AppColors.card,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isTop3 ? null : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTop3
              ? AppColors.primary.withOpacity(0.40)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: isTop3
                ? Text(
                    position == 1
                        ? '🥇'
                        : position == 2
                            ? '🥈'
                            : '🥉',
                    style: const TextStyle(fontSize: 20),
                    textAlign: TextAlign.center)
                : Text('#$position',
                    style: const TextStyle(
                        color: AppColors.textHint,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                    textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            height: 42,
            child: Stack(
              children: [
                PlayerAvatar(
                    photoPath: trio.a.photoPath,
                    name: trio.a.name,
                    size: 38),
                Positioned(
                    left: 20,
                    child: PlayerAvatar(
                        photoPath: trio.b.photoPath,
                        name: trio.b.name,
                        size: 38)),
                Positioned(
                    left: 40,
                    child: PlayerAvatar(
                        photoPath: trio.c.photoPath,
                        name: trio.c.name,
                        size: 38)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${trio.a.name}, ${trio.b.name} & ${trio.c.name}',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  byStats
                      ? '${trio.sharedMatches} partida(s) juntos • ${trio.sharedWins} vitória(s)'
                      : '${trio.totalMatches} partida(s) somadas • ${trio.totalWins} vitória(s) • ${trio.totalGoals} gol(s)',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text('${trio.score}',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              const Text('pts',
                  style:
                      TextStyle(color: AppColors.textHint, fontSize: 10)),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(
        delay: Duration(milliseconds: index * 40), duration: 300.ms);
  }
}

class _RankCard extends StatelessWidget {
  final int position;
  final String name;
  final String? photoPath;
  final String subtitle;
  final int value;
  final String valueLabel;
  final int index;
  final VoidCallback? onTap;

  const _RankCard({
    required this.position,
    required this.name,
    this.photoPath,
    required this.subtitle,
    required this.value,
    required this.valueLabel,
    required this.index,
    this.onTap,
  });

  Color get _medalColor {
    if (position == 1) return const Color(0xFFFFD700);
    if (position == 2) return const Color(0xFFC0C0C0);
    if (position == 3) return const Color(0xFFCD7F32);
    return AppColors.textHint;
  }

  @override
  Widget build(BuildContext context) {
    final isTop3 = position <= 3;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: isTop3
              ? LinearGradient(
                  colors: [
                    _medalColor.withOpacity(0.08),
                    AppColors.card,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isTop3 ? null : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isTop3
                  ? _medalColor.withOpacity(0.45)
                  : AppColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: isTop3
                  ? Text(
                      position == 1
                          ? '🥇'
                          : position == 2
                              ? '🥈'
                              : '🥉',
                      style: const TextStyle(fontSize: 22),
                      textAlign: TextAlign.center)
                  : Text('#$position',
                      style: TextStyle(
                          color: _medalColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                      textAlign: TextAlign.center),
            ),
            const SizedBox(width: 12),
            PlayerAvatar(photoPath: photoPath, name: name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            // Badge de valor com Electric Lime
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.primary.withOpacity(0.25)),
              ),
              child: Column(
                children: [
                  Text('$value',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  Text(valueLabel,
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(
          delay: Duration(milliseconds: index * 40), duration: 300.ms),
    );
  }
}

class _DuoCard extends StatelessWidget {
  final _Duo duo;
  final int position, index;
  final DuoRankingMode mode;

  const _DuoCard(
      {required this.duo,
      required this.position,
      required this.index,
      required this.mode});

  @override
  Widget build(BuildContext context) {
    final isTop3 = position <= 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: isTop3
            ? LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.08),
                  AppColors.card,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isTop3 ? null : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isTop3
                ? AppColors.primary.withOpacity(0.40)
                : AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: isTop3
                ? Text(
                    position == 1
                        ? '🥇'
                        : position == 2
                            ? '🥈'
                            : '🥉',
                    style: const TextStyle(fontSize: 20),
                    textAlign: TextAlign.center)
                : Text('#$position',
                    style: const TextStyle(
                        color: AppColors.textHint,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                    textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 58,
            height: 40,
            child: Stack(
              children: [
                PlayerAvatar(
                    photoPath: duo.a.photoPath,
                    name: duo.a.name,
                    size: 38),
                Positioned(
                    left: 20,
                    child: PlayerAvatar(
                        photoPath: duo.b.photoPath,
                        name: duo.b.name,
                        size: 38)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${duo.a.name} & ${duo.b.name}',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Text(
                  mode == DuoRankingMode.sharedGoals
                      ? '${duo.sharedGoals} gols juntos em ${duo.sharedMatches} partida(s)'
                      : '${duo.a.titles + duo.b.titles} títulos • ${duo.a.wins + duo.b.wins} vitórias',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text('${duo.score}',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              const Text('pts',
                  style:
                      TextStyle(color: AppColors.textHint, fontSize: 10)),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(
        delay: Duration(milliseconds: index * 40), duration: 300.ms);
  }
}

class _CategorySection extends StatelessWidget {
  final String title;
  final Color color;
  final List<Player> players;
  final String Function(Player) valueLabel;

  const _CategorySection({
    required this.title,
    required this.color,
    required this.players,
    required this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (players.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text('Sem dados',
                  style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            ...players.asMap().entries.map((entry) {
              final i = entry.key;
              final p = entry.value;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: AppColors.border.withOpacity(0.6)))),
                child: Row(
                  children: [
                    Text('${i + 1}',
                        style: const TextStyle(
                            color: AppColors.textHint,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(p.name,
                            style: const TextStyle(
                                color: AppColors.textPrimary))),
                    Text(valueLabel(p),
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
