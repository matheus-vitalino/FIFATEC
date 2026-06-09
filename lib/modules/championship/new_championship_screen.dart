import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/championship.dart';
import '../../core/models/match.dart';
import '../../core/models/player.dart';
import '../../core/models/team.dart';
import '../../core/repositories/championship_repository.dart';
import '../../core/repositories/match_repository.dart';
import '../../core/repositories/player_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/models/season.dart';
import '../../core/services/season_manager.dart';
import '../../core/services/team_draw_service.dart';
import '../../shared/widgets/custom_app_bar.dart';
import '../../shared/widgets/player_avatar.dart';

class NewChampionshipScreen extends StatefulWidget {
  const NewChampionshipScreen({super.key});

  @override
  State<NewChampionshipScreen> createState() => _NewChampionshipScreenState();
}

class _NewChampionshipScreenState extends State<NewChampionshipScreen> {
  final _nameCtrl = TextEditingController();
  final _champRepo = ChampionshipRepository();
  final _matchRepo = MatchRepository();
  final _playerRepo = PlayerRepository();
  final _settingsRepo = SettingsRepository();
  final _drawService = TeamDrawService();
  final _uuid = const Uuid();

  List<Player> _allPlayers = [];
  Set<String> _selectedIds = {};
  List<Team> _teams = [];
  final List<TextEditingController> _teamNameCtrls = [];
  ChampionshipMode _mode = ChampionshipMode.bracket;
  bool _balanceTeams = false;
  int _teamSize = 3;
  bool _loading = false;
  bool _manualTeams = false; // true = montar times manualmente
  int _step = 0;
  final List<List<String>> _localDrawHistoryTeamGroups = [];

  // Temporada
  List<Season> _seasons = [];
  Season? _selectedSeason;
  String? _activeSeasonId;

  static const _stepLabels = ['Configurar', 'Jogadores', 'Times'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final settings = await _settingsRepo.get();
    final players = await _playerRepo.getAll();
    final seasons = await SeasonManager.instance.getSeasons();
    final active = await SeasonManager.instance.getActiveSeason();
    setState(() {
      _teamSize = settings.teamSize;
      _balanceTeams = settings.balanceTeams;
      _allPlayers = players;
      _seasons = seasons;
      _selectedSeason = active ?? (seasons.isNotEmpty ? seasons.first : null);
      _activeSeasonId = active?.id;
    });
  }

  void _togglePlayer(String id) => setState(() {
        _selectedIds.contains(id) ? _selectedIds.remove(id) : _selectedIds.add(id);
      });

  // ── Sorteio automático ────────────────────────────────────────
  Future<void> _drawTeamsAuto() async {
    if (_loading) return;

    final selected = _allPlayers.where((p) => _selectedIds.contains(p.id)).toList();
    if (selected.length < _teamSize * 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Selecione pelo menos ${_teamSize * 2} jogadores'),
        backgroundColor: AppColors.loss,
      ));
      return;
    }

    setState(() => _loading = true);
    try {
      final savedHistory = await _loadTeamDrawHistory();
      final teams = _drawService.drawSmartTeams(
        players: selected,
        teamSize: _teamSize,
        balanceTeams: _balanceTeams,
        historyTeamGroups: [
          ...savedHistory,
          ..._localDrawHistoryTeamGroups,
        ],
      );

      if (teams.length < 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível montar pelo menos 2 times'),
          backgroundColor: AppColors.loss,
        ));
        return;
      }

      _localDrawHistoryTeamGroups.addAll(_teamGroupsFromTeams(teams));
      if (_localDrawHistoryTeamGroups.length > 80) {
        _localDrawHistoryTeamGroups.removeRange(
          0,
          _localDrawHistoryTeamGroups.length - 80,
        );
      }

      if (!mounted) return;
      setState(() {
        _teams = teams;
        _syncTeamControllers();
        _step = 2;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao sortear times: $e'),
        backgroundColor: AppColors.loss,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<List<String>>> _loadTeamDrawHistory() async {
    final championships = await _champRepo.getAll(seasonId: _selectedSeason?.id);
    final groups = <List<String>>[];

    for (final championship in championships) {
      for (final team in championship.teams) {
        final ids = team.activePlayers
            .map((p) => p.playerId)
            .where((id) => id.trim().isNotEmpty)
            .toSet()
            .toList();
        if (ids.length > 1) groups.add(ids);
      }
    }

    return groups;
  }

  List<List<String>> _teamGroupsFromTeams(List<Team> teams) {
    return teams
        .map((team) => team.activePlayers
            .map((p) => p.playerId)
            .where((id) => id.trim().isNotEmpty)
            .toSet()
            .toList())
        .where((ids) => ids.length > 1)
        .toList();
  }

  // ── Montagem manual ───────────────────────────────────────────
  void _goToManualTeams() {
    final selected = _allPlayers.where((p) => _selectedIds.contains(p.id)).toList();
    if (selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Selecione pelo menos 2 jogadores'),
        backgroundColor: AppColors.loss,
      ));
      return;
    }

    _teams = _buildDefaultManualTeams();
    _syncTeamControllers();

    setState(() {
      _step = 2;
    });
  }

  List<Team> _buildDefaultManualTeams() {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final colors = ['#E53935', '#1E88E5', '#43A047', '#FB8C00', '#8E24AA', '#00ACC1', '#F4511E', '#6D4C41'];
    return List.generate(2, (i) => Team(
      id: _uuid.v4(),
      name: 'Time ${letters[i % 26]}',
      color: colors[i % colors.length],
      players: [],
    ));
  }

  void _syncTeamControllers() {
    while (_teamNameCtrls.length < _teams.length) {
      _teamNameCtrls.add(TextEditingController(text: _teams[_teamNameCtrls.length].name));
    }
    while (_teamNameCtrls.length > _teams.length) {
      final ctrl = _teamNameCtrls.removeLast();
      ctrl.dispose();
    }
    for (int i = 0; i < _teams.length && i < _teamNameCtrls.length; i++) {
      if (_teamNameCtrls[i].text.trim().isEmpty) {
        _teamNameCtrls[i].text = _teams[i].name;
      }
    }
  }

  void _addManualTeam() {
    final index = _teams.length;
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final colors = ['#E53935', '#1E88E5', '#43A047', '#FB8C00', '#8E24AA', '#00ACC1', '#F4511E', '#6D4C41'];
    setState(() {
      _teams.add(Team(
        id: _uuid.v4(),
        name: 'Time ${letters[index % 26]}',
        color: colors[index % colors.length],
        players: [],
      ));
      _syncTeamControllers();
    });
  }

  void _removeManualTeam(int index) {
    if (_teams.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Mantenha pelo menos 2 times'),
        backgroundColor: AppColors.loss,
      ));
      return;
    }
    setState(() {
      _teams.removeAt(index);
      _syncTeamControllers();
    });
  }

  List<Team>? _buildTeamsFromList(List<Player> selected) {
    final total = selected.length;
    final fullTeams = total ~/ _teamSize;

    if (fullTeams < 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Selecione pelo menos ${_teamSize * 2} jogadores'),
        backgroundColor: AppColors.loss,
      ));
      return null;
    }

    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final colors = ['#E53935', '#1E88E5', '#43A047', '#FB8C00', '#8E24AA', '#00ACC1', '#F4511E', '#6D4C41'];
    final teams = <Team>[];

    for (int i = 0; i < fullTeams; i++) {
      final chunk = selected.sublist(i * _teamSize, (i + 1) * _teamSize);
      teams.add(Team(
        id: _uuid.v4(),
        name: 'Time ${letters[i % 26]}',
        color: colors[i % colors.length],
        players: chunk.map((p) => TeamPlayer(playerId: p.id, playerName: p.name)).toList(),
      ));
    }

    // Sobras -> cria um time extra (mesmo com 1 ou 2 jogadores)
    final remainder = total % _teamSize;
    if (remainder >= 1) {
      final extra = selected.sublist(fullTeams * _teamSize);
      teams.add(Team(
        id: _uuid.v4(),
        name: 'Time ${letters[teams.length % 26]}',
        color: colors[teams.length % colors.length],
        players: extra.map((p) => TeamPlayer(playerId: p.id, playerName: p.name)).toList(),
      ));
    }
    return teams;
  }

  void _applyBalancing(List<Team> teams, List<Player> selected) {
    final scores = {for (final p in selected) p.id: (p.wins * 3.0) + p.goals};
    final allActive = teams.expand((t) => t.activePlayers).toList()
      ..sort((a, b) => (scores[b.playerId] ?? 0).compareTo(scores[a.playerId] ?? 0));

    final slots = List.generate(teams.length, (_) => <TeamPlayer>[]);
    bool fwd = true;
    int col = 0;
    for (final tp in allActive) {
      slots[col].add(tp);
      if (fwd) { col++; if (col >= teams.length) { col = teams.length - 1; fwd = false; } }
      else { col--; if (col < 0) { col = 0; fwd = true; } }
    }
    for (int i = 0; i < teams.length; i++) {
      teams[i].players..clear()..addAll([...slots[i], ...teams[i].reservePlayers]);
    }
  }

  Future<void> _create() async {
    // Nome automático se vazio
    if (_nameCtrl.text.trim().isEmpty) {
      final all = await _champRepo.getAll(all: true);
      _nameCtrl.text = 'Campeonato ${all.length + 1}';
    }
    if (_teams.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Necessário pelo menos 2 times'),
        backgroundColor: AppColors.loss,
      ));
      return;
    }

    for (int i = 0; i < _teams.length && i < _teamNameCtrls.length; i++) {
      final name = _teamNameCtrls[i].text.trim();
      if (name.isNotEmpty) _teams[i].name = name;
    }

    setState(() => _loading = true);
    try {
      final champId = _uuid.v4();
      final matchIds = <String>[];
      final rounds = <BracketRound>[];

      if (_mode == ChampionshipMode.bracket) {
        // Chaveamento eliminatório: monta rodadas tipo torneio
        // Rodada 1: oitavas/quartas/semifinal dependendo da qtd de times
        final shuffled = List<Team>.from(_teams)..shuffle();
        final round1Matches = <MatchModel>[];
        final round1Ids = <String>[];

        // Emparelha times: [0 vs 1], [2 vs 3], ...
        // Se impar, o último avança automaticamente (bye)
        for (int i = 0; i + 1 < shuffled.length; i += 2) {
          final roundName = _bracketRoundName(shuffled.length);
          final m = MatchModel(
            id: _uuid.v4(),
            championshipId: champId,
            teamA: shuffled[i],
            teamB: shuffled[i + 1],
            round: roundName,
          );
          round1Matches.add(m);
          round1Ids.add(m.id);
          matchIds.add(m.id);
        }

        if (round1Matches.isNotEmpty) {
          rounds.add(BracketRound(
            id: _uuid.v4(),
            name: _bracketRoundName(shuffled.length),
            matchIds: round1Ids,
          ));
          for (final m in round1Matches) await _matchRepo.save(m);
        }
      }

      final champ = Championship(
        id: champId,
        name: _nameCtrl.text.trim(),
        teams: _teams,
        matchIds: matchIds,
        rounds: rounds,
        mode: _mode,
        status: ChampionshipStatus.inProgress,
        balanceTeams: _balanceTeams,
        teamSize: _teamSize,
        seasonId: _selectedSeason?.id,
      );
      await _champRepo.save(champ);

      if (mounted) {
        Navigator.pop(context);
        Navigator.pushNamed(context, '/championship/detail', arguments: champId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.loss));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  String _bracketRoundName(int teamCount) {
    if (teamCount <= 2) return 'Final';
    if (teamCount <= 4) return 'Semifinal';
    if (teamCount <= 8) return 'Quartas de Final';
    if (teamCount <= 16) return 'Oitavas de Final';
    return 'Rodada Classificatória';
  }

  Future<void> _nextStep() async {
    if (_step == 0) {
      setState(() => _step = 1);
    } else if (_step == 1) {
      if (_selectedIds.length < _teamSize * 2) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Selecione pelo menos ${_teamSize * 2} jogadores'),
          backgroundColor: AppColors.loss,
        ));
        return;
      }
      if (_manualTeams) {
        _goToManualTeams();
      } else {
        await _drawTeamsAuto();
      }
    } else {
      _create();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: 'Novo Campeonato'),
      body: Column(
        children: [
          _buildStepBar(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: [_buildStep0(), _buildStep1(), _buildStep2()][_step],
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildStepBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: List.generate(_stepLabels.length, (i) {
          final active = i == _step;
          final done = i < _step;
          final isLast = i == _stepLabels.length - 1;
          final circleColor = done
              ? AppColors.primaryDark
              : active
                  ? AppColors.primary
                  : AppColors.surfaceLight;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: circleColor,
                          border: Border.all(
                            color: active ? AppColors.accentLight : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.28),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: done
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 14,
                                )
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: active ? AppColors.background : AppColors.textHint,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _stepLabels[i],
                        style: TextStyle(
                          color: active
                              ? AppColors.primaryLight
                              : done
                                  ? AppColors.textSecondary
                                  : AppColors.textHint,
                          fontSize: 10,
                          fontWeight: active ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 18),
                      color: i < _step ? AppColors.primaryDark : AppColors.surfaceLight,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── PASSO 0 ──────────────────────────────────────────────────
  Widget _buildStep0() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nome do campeonato', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Ex: Pelada de Sexta',
              hintStyle: const TextStyle(color: AppColors.textHint),
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.emoji_events_rounded, color: AppColors.accent),
            ),
          ),

          const SizedBox(height: 20),
          const Text('Temporada', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          if (_seasons.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Nenhuma temporada encontrada',
                  style: TextStyle(color: AppColors.textHint, fontSize: 13)),
            )
          else
            DropdownButtonFormField<String>(
              value: _selectedSeason?.id,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.event_note_rounded, color: AppColors.accent),
              ),
              items: _seasons.map((s) => DropdownMenuItem(
                value: s.id,
                child: Row(
                  children: [
                    Text(s.name),
                    if (s.id == _activeSeasonId) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.win.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('atual', style: TextStyle(color: AppColors.win, fontSize: 10)),
                      ),
                    ],
                  ],
                ),
              )).toList(),
              onChanged: (id) {
                if (id == null) return;
                setState(() => _selectedSeason = _seasons.firstWhere((s) => s.id == id));
              },
            ),

          const SizedBox(height: 28),
          const Text('Modo de disputa', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _OptionTile(
                icon: Icons.account_tree_rounded,
                label: 'Todos contra todos',
                desc: 'Cada time enfrenta todos os outros',
                selected: _mode == ChampionshipMode.bracket,
                onTap: () => setState(() => _mode = ChampionshipMode.bracket),
              )),
              const SizedBox(width: 12),
              Expanded(child: _OptionTile(
                icon: Icons.groups_rounded,
                label: 'Livre',
                desc: 'Partidas criadas manualmente',
                selected: _mode == ChampionshipMode.teamsOnly,
                onTap: () => setState(() => _mode = ChampionshipMode.teamsOnly),
              )),
            ],
          ),

          const SizedBox(height: 28),
          const Text('Montagem dos times', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _OptionTile(
                icon: Icons.shuffle_rounded,
                label: 'Sorteio automático',
                desc: 'App distribui os jogadores',
                selected: !_manualTeams,
                onTap: () => setState(() => _manualTeams = false),
              )),
              const SizedBox(width: 12),
              Expanded(child: _OptionTile(
                icon: Icons.edit_rounded,
                label: 'Montar manualmente',
                desc: 'Você escolhe quem vai em cada time',
                selected: _manualTeams,
                onTap: () => setState(() => _manualTeams = true),
              )),
            ],
          ),

          const SizedBox(height: 20),
          if (!_manualTeams)
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.surfaceLight),
              ),
              child: SwitchListTile(
                value: _balanceTeams,
                onChanged: (v) => setState(() => _balanceTeams = v),
                title: const Text('Equilibrar times', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                subtitle: const Text('Distribui por vitórias e gols', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                activeColor: AppColors.accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
        ],
      ),
    );
  }

  // ── PASSO 1 ──────────────────────────────────────────────────
  Widget _buildStep1() {
    final total = _selectedIds.length;
    final minNeeded = _teamSize * 2;
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$total selecionados', style: const TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(
                      total < minNeeded
                          ? 'Mín. $minNeeded para ${minNeeded ~/ _teamSize} times de $_teamSize'
                          : 'Formará ${total ~/ _teamSize} time(s) • ${total % _teamSize == 0 ? "sem sobras" : "${total % _teamSize} jogador(es) em time extra"}',
                      style: TextStyle(color: total < minNeeded ? AppColors.loss : AppColors.win, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _selectedIds.length == _allPlayers.length
                      ? _selectedIds.clear()
                      : _selectedIds = _allPlayers.map((p) => p.id).toSet();
                }),
                child: Text(_selectedIds.length == _allPlayers.length ? 'Nenhum' : 'Todos',
                    style: const TextStyle(color: AppColors.accent)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _allPlayers.isEmpty
              ? const EmptyState(icon: Icons.person_off_rounded, title: 'Nenhum jogador', subtitle: 'Adicione jogadores primeiro')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _allPlayers.length,
                  itemBuilder: (_, i) {
                    final p = _allPlayers[i];
                    final sel = _selectedIds.contains(p.id);
                    return GestureDetector(
                      onTap: () => _togglePlayer(p.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary.withOpacity(0.12) : AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sel ? AppColors.primary : AppColors.surfaceLight, width: sel ? 1.5 : 1),
                        ),
                        child: Row(
                          children: [
                            Stack(clipBehavior: Clip.none, children: [
                              PlayerAvatar(photoPath: p.photoPath, name: p.name, size: 44),
                              if (sel)
                                Positioned(
                                  right: -4, bottom: -4,
                                  child: Container(
                                    width: 18, height: 18,
                                    decoration: const BoxDecoration(color: AppColors.win, shape: BoxShape.circle),
                                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 12),
                                  ),
                                ),
                            ]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name, style: TextStyle(
                                  color: sel ? AppColors.textPrimary : AppColors.textSecondary,
                                  fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 14,
                                )),
                                Text('${p.wins}V  ${p.goals}G  ${p.matchesPlayed}J',
                                    style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                              ]),
                            ),
                            Icon(sel ? Icons.check_circle_rounded : Icons.circle_outlined,
                                color: sel ? AppColors.win : AppColors.textHint),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── PASSO 2 ──────────────────────────────────────────────────
  Widget _buildStep2() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _manualTeams ? 'Monte os times abaixo' : '${_teams.length} times sorteados',
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              if (!_manualTeams)
                TextButton.icon(
                  onPressed: _loading ? null : () => _drawTeamsAuto(),
                  icon: const Icon(Icons.shuffle_rounded, size: 16, color: AppColors.accent),
                  label: const Text('Sortear novamente', style: TextStyle(color: AppColors.accent, fontSize: 13)),
                ),
            ],
          ),
        ),
        Expanded(
          child: _manualTeams
              ? _buildManualEditor()
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _teams.length,
                  itemBuilder: (_, i) => _TeamPreviewCard(team: _teams[i]),
                ),
        ),
      ],
    );
  }

  // ── Editor manual de times ────────────────────────────────────
  Widget _buildManualEditor() {
    final selectedPlayers = _allPlayers.where((p) => _selectedIds.contains(p.id)).toList();
    final allocatedIds = _teams.expand((t) => t.players.map((p) => p.playerId)).toSet();
    final unallocated = selectedPlayers.where((p) => !allocatedIds.contains(p.id)).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.draw.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline, color: AppColors.draw, size: 16),
                  const SizedBox(width: 6),
                  Text('Jogadores sem time (${unallocated.length})',
                      style: const TextStyle(color: AppColors.draw, fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addManualTeam,
                    icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.accent),
                    label: const Text('Adicionar time', style: TextStyle(color: AppColors.accent)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (unallocated.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Todos os jogadores já foram distribuídos.', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: unallocated.map((p) => _DraggablePlayerChip(
                    player: p,
                    onAssign: (teamIndex) {
                      setState(() {
                        if (teamIndex >= 0 && teamIndex < _teams.length) {
                          _teams[teamIndex].players.add(TeamPlayer(playerId: p.id, playerName: p.name));
                        }
                      });
                    },
                    teamNames: _teams.map((t) => t.name).toList(),
                  )).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        ..._teams.asMap().entries.map((e) {
          final i = e.key;
          final team = e.value;
          final color = _teamColor(team);
          final controller = _teamNameCtrls[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                  ),
                  child: Row(
                    children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Nome do time',
                            hintStyle: TextStyle(color: AppColors.textHint),
                          ),
                          onChanged: (value) => _teams[i].name = value.trim().isEmpty ? 'Time ${i + 1}' : value.trim(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_rounded, color: AppColors.loss, size: 18),
                        onPressed: () => _removeManualTeam(i),
                        visualDensity: VisualDensity.compact,
                      ),
                      Text('${team.players.length}/$_teamSize', style: TextStyle(
                        color: team.players.length == _teamSize ? AppColors.win : AppColors.textHint,
                        fontSize: 12,
                      )),
                    ],
                  ),
                ),
                if (team.players.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Nenhum jogador', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                  )
                else
                  ...team.players.asMap().entries.map((pe) {
                    final pi = pe.key;
                    final tp = pe.value;
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.person_rounded, size: 16, color: color),
                      title: Text(tp.playerName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.loss),
                        onPressed: () => setState(() => _teams[i].players.removeAt(pi)),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: _AddPlayerButton(
                    availablePlayers: unallocated,
                    onAdd: (player) {
                      setState(() {
                        _teams[i].players.add(TeamPlayer(playerId: player.id, playerName: player.name));
                      });
                    },
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Color _teamColor(Team team) {
    if (team.color == null) return AppColors.primary;
    try { return Color(int.parse('FF${team.color!.replaceAll('#', '')}', radix: 16)); } catch (_) { return AppColors.primary; }
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceLight)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              if (_step > 0) ...[
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _step--),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.surfaceLight),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: const Text('Voltar', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : () => _nextStep(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      disabledBackgroundColor: AppColors.surfaceLight,
                      disabledForegroundColor: AppColors.textHint,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.background,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _step == 0
                                ? 'Próximo: Jogadores'
                                : _step == 1
                                    ? (_manualTeams ? 'Montar Times' : 'Sortear Times')
                                    : 'Criar Campeonato',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final ctrl in _teamNameCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label, desc;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({required this.icon, required this.label, required this.desc, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.primary : AppColors.surfaceLight, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? AppColors.accent : AppColors.textHint, size: 24),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 13,
            )),
            const SizedBox(height: 3),
            Text(desc, style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _TeamPreviewCard extends StatelessWidget {
  final Team team;
  const _TeamPreviewCard({required this.team});

  Color get _color {
    if (team.color == null) return AppColors.primary;
    try { return Color(int.parse('FF${team.color!.replaceAll('#', '')}', radix: 16)); } catch (_) { return AppColors.primary; }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _color.withOpacity(0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Container(width: 14, height: 14, decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text(team.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                Text('${team.activePlayers.length} jogadores', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          ...team.players.map((p) => ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            leading: Icon(
              p.isReserve ? Icons.airline_seat_recline_normal_rounded : p.isInTwoTeams ? Icons.swap_horiz_rounded : Icons.person_rounded,
              color: p.isReserve ? AppColors.textHint : p.isInTwoTeams ? AppColors.draw : _color, size: 18,
            ),
            title: Text(p.playerName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
            trailing: p.isReserve ? _chip('Reserva', AppColors.textHint) : p.isInTwoTeams ? _chip('2 times', AppColors.draw) : null,
          )),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
  );
}

class _DraggablePlayerChip extends StatelessWidget {
  final Player player;
  final Function(int teamIndex) onAssign;
  final List<String> teamNames;

  const _DraggablePlayerChip({required this.player, required this.onAssign, required this.teamNames});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (teamNames.isEmpty) return;
        final idx = await showDialog<int>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.card,
            title: Text('Adicionar ${player.name} a:', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: teamNames.asMap().entries.map((e) => ListTile(
                title: Text(e.value, style: const TextStyle(color: AppColors.textPrimary)),
                leading: const Icon(Icons.group_rounded, color: AppColors.accent),
                onTap: () => Navigator.pop(context, e.key),
              )).toList(),
            ),
          ),
        );
        if (idx != null) onAssign(idx);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          PlayerAvatar(name: player.name, photoPath: player.photoPath, size: 22),
          const SizedBox(width: 6),
          Text(player.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _AddPlayerButton extends StatelessWidget {
  final List<Player> availablePlayers;
  final Function(Player) onAdd;

  const _AddPlayerButton({required this.availablePlayers, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    if (availablePlayers.isEmpty) return const SizedBox();
    return GestureDetector(
      onTap: () async {
        final player = await showDialog<Player>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text('Adicionar jogador', style: TextStyle(color: AppColors.textPrimary)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: availablePlayers.map((p) => ListTile(
                  leading: PlayerAvatar(name: p.name, photoPath: p.photoPath, size: 36),
                  title: Text(p.name, style: const TextStyle(color: AppColors.textPrimary)),
                  onTap: () => Navigator.pop(context, p),
                )).toList(),
              ),
            ),
          ),
        );
        if (player != null) onAdd(player);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_rounded, size: 16, color: AppColors.accent),
            SizedBox(width: 6),
            Text('Adicionar jogador', style: TextStyle(color: AppColors.accent, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}