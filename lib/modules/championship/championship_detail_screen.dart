import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/championship.dart';
import '../../core/models/match.dart';
import '../../core/models/team.dart';
import '../../core/repositories/championship_repository.dart';
import '../../core/repositories/match_repository.dart';
import '../../core/services/image_service.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/custom_app_bar.dart';

class ChampionshipDetailScreen extends StatefulWidget {
  final String championshipId;
  const ChampionshipDetailScreen({super.key, required this.championshipId});

  @override
  State<ChampionshipDetailScreen> createState() => _ChampionshipDetailScreenState();
}

class _ChampionshipDetailScreenState extends State<ChampionshipDetailScreen>
    with SingleTickerProviderStateMixin {
  final _champRepo = ChampionshipRepository();
  final _matchRepo = MatchRepository();
  final _imgService = ImageService();
  final _uuid = const Uuid();

  Championship? _champ;
  List<MatchModel> _matches = [];
  bool _loading = true;
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _champ = await _champRepo.getById(widget.championshipId);
    if (_champ != null) {
      _matches = await _matchRepo.getByChampionship(widget.championshipId);
    }
    setState(() => _loading = false);
  }

  // ── Nova partida ─────────────────────────────────────────────
  Future<void> _addMatch() async {
    if (_champ == null || _champ!.teams.length < 2) return;

    Team? teamA, teamB;
    MatchType matchType = MatchType.normal;

    await showDialog(
      context: context,
      builder: (_) => _SelectTeamsDialog(
        teams: _champ!.teams,
        onSelect: (a, b, t) {
          teamA = a;
          teamB = b;
          matchType = t;
        },
      ),
    );

    if (teamA == null || teamB == null) return;

    String roundLabel;
    switch (matchType) {
      case MatchType.final_:
        roundLabel = 'Final';
      case MatchType.semifinal:
        roundLabel = 'Semifinal';
      case MatchType.normal:
        roundLabel = 'Partida';
    }

    final match = MatchModel(
      id: _uuid.v4(),
      championshipId: _champ!.id,
      teamA: teamA!,
      teamB: teamB!,
      matchType: matchType,
      round: roundLabel,
    );
    await _matchRepo.save(match);
    _champ!.matchIds.add(match.id);
    await _champRepo.save(_champ!);
    await _load();
  }

  Future<void> _openMatch(MatchModel match) async {
    await Navigator.pushNamed(context, '/championship/match', arguments: {
      'matchId': match.id,
      'championshipId': _champ!.id,
    });
    await _load();
  }

  Future<void> _deleteMatch(MatchModel match) async {
    if (_champ == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Excluir partida?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Essa partida será removida do campeonato e do histórico.', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir', style: TextStyle(color: AppColors.loss))),
        ],
      ),
    );
    if (confirm != true) return;
    _champ!.matchIds.remove(match.id);
    await _champRepo.save(_champ!);
    await _matchRepo.delete(match.id);
    await _load();
  }

  // ── Foto do campeonato ────────────────────────────────────────
  Future<void> _pickWinnerPhoto() async {
    if (_champ == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.textHint, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.accent),
              title: const Text('Galeria', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () async {
                Navigator.pop(context);
                final path = await _imgService.pickFromGallery();
                if (path != null && mounted) {
                  _champ!.finishedAt = _champ!.finishedAt ?? DateTime.now();
                  // Salvamos o path como winnerPhotoPath usando o winnerId field temporariamente
                  // Vamos usar um campo de conveniência: reutiliza seasonId para foto (ou adiciona ao modelo)
                  // Solução: salvamos no primeiro match como winnerPhotoPath
                  await _saveWinnerPhoto(path);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.accent),
              title: const Text('Câmera', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () async {
                Navigator.pop(context);
                final path = await _imgService.pickFromCamera();
                if (path != null && mounted) {
                  await _saveWinnerPhoto(path);
                }
              },
            ),
            if (_champ?.winnerPhotoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_rounded, color: AppColors.loss),
                title: const Text('Remover foto', style: TextStyle(color: AppColors.loss)),
                onTap: () async {
                  Navigator.pop(context);
                  _champ!.winnerPhotoPath = null;
                  await _champRepo.save(_champ!);
                  setState(() {});
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _saveWinnerPhoto(String path) async {
    _champ!.winnerPhotoPath = path;
    await _champRepo.save(_champ!);
    setState(() {});
  }

  String? get _winnerPhotoPath => _champ?.winnerPhotoPath;

  // ── Finalizar campeonato ──────────────────────────────────────
  Future<void> _finishChampionship() async {
    if (_champ == null) return;

    final Map<String, int> teamWins = {};
    for (final m in _matches.where((m) => m.isFinished && m.winnerId != null)) {
      teamWins[m.winnerId!] = (teamWins[m.winnerId!] ?? 0) + 1;
    }
    String? winnerId;
    String? winnerName;
    if (teamWins.isNotEmpty) {
      final topId = teamWins.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      winnerId = topId;
      try { winnerName = _champ!.teams.firstWhere((t) => t.id == topId).name; } catch (_) {}
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Finalizar campeonato?', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (winnerName != null) ...[
              const Icon(Icons.emoji_events_rounded, color: AppColors.accent, size: 40),
              const SizedBox(height: 8),
              Text('Campeão: $winnerName', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
            ] else
              const Text('Nenhum vencedor definido ainda.', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    _champ!.status = ChampionshipStatus.finished;
    _champ!.winnerId = winnerId;
    _champ!.winnerName = winnerName;
    _champ!.finishedAt = DateTime.now();
    await _champRepo.save(_champ!);
    await _load();
  }

  // Verifica se pode avançar rodada e gera próximos confrontos
  Future<void> _advanceBracket() async {
    if (_champ == null) return;
    final currentRound = _champ!.rounds.isNotEmpty ? _champ!.rounds.last : null;
    if (currentRound == null) return;

    // Pega partidas da rodada atual
    final roundMatches = _matches.where((m) => currentRound.matchIds.contains(m.id)).toList();
    final allDone = roundMatches.every((m) => m.isFinished);
    if (!allDone) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Finalize todas as partidas da rodada atual primeiro'),
        backgroundColor: AppColors.loss,
      ));
      return;
    }

    // Coleta os vencedores
    final winners = <Team>[];
    for (final m in roundMatches) {
      if (m.winnerId == m.teamA.id) winners.add(m.teamA);
      else if (m.winnerId == m.teamB.id) winners.add(m.teamB);
      // empate: não avança ninguém (deveria ser resolvido antes)
    }

    if (winners.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não há vencedores suficientes para nova rodada'),
        backgroundColor: AppColors.draw,
      ));
      return;
    }

    final champId = _champ!.id;
    final newMatchIds = <String>[];
    final newMatches = <MatchModel>[];

    String _roundName(int n) {
      if (n <= 2) return 'Final';
      if (n <= 4) return 'Semifinal';
      if (n <= 8) return 'Quartas de Final';
      return 'Oitavas de Final';
    }

    for (int i = 0; i + 1 < winners.length; i += 2) {
      final m = MatchModel(
        id: _uuid.v4(),
        championshipId: champId,
        teamA: winners[i],
        teamB: winners[i + 1],
        round: _roundName(winners.length),
      );
      newMatches.add(m);
      newMatchIds.add(m.id);
    }

    for (final m in newMatches) await _matchRepo.save(m);
    _champ!.matchIds.addAll(newMatchIds);
    currentRound.isFinished = true;
    _champ!.rounds.add(BracketRound(
      id: _uuid.v4(),
      name: _roundName(winners.length),
      matchIds: newMatchIds,
    ));
    await _champRepo.save(_champ!);
    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${_roundName(winners.length)} gerada com ${newMatches.length} confronto(s)!'),
        backgroundColor: AppColors.win,
      ));
    }
  }

  bool get _canAdvanceBracket {
    if (_champ == null || _champ!.status == ChampionshipStatus.finished) return false;
    if (_champ!.mode != ChampionshipMode.bracket) return false;
    if (_champ!.rounds.isEmpty) return false;
    final currentRound = _champ!.rounds.last;
    if (currentRound.isFinished) return false;
    final roundMatches = _matches.where((m) => currentRound.matchIds.contains(m.id)).toList();
    if (roundMatches.isEmpty) return false;
    return roundMatches.every((m) => m.isFinished);
  }

  @override
  Widget build(BuildContext context) {
    final photoPath = _winnerPhotoPath;
    final isFinished = _champ?.status == ChampionshipStatus.finished;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: _champ?.name ?? 'Campeonato',
        actions: [
          // Foto dos vencedores
          if (_champ != null)
            IconButton(
              icon: const Icon(Icons.photo_camera_rounded, color: AppColors.accent),
              onPressed: _pickWinnerPhoto,
              tooltip: 'Foto dos vencedores',
            ),
          if (_canAdvanceBracket)
            IconButton(
              icon: const Icon(Icons.skip_next_rounded, color: AppColors.win),
              onPressed: _advanceBracket,
              tooltip: 'Próxima Rodada',
            ),
          if (_champ != null && !isFinished)
            IconButton(
              icon: const Icon(Icons.flag_rounded, color: AppColors.accent),
              onPressed: _finishChampionship,
              tooltip: 'Finalizar',
            ),
        ],
        bottomHeight: 48,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textHint,
          tabs: const [Tab(text: 'Partidas'), Tab(text: 'Times')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(
              children: [
                // Banner de vencedor + foto
                if (isFinished && (_champ?.winnerName != null || photoPath != null))
                  _buildWinnerBanner(photoPath),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [_buildMatches(), _buildTeams()],
                  ),
                ),
              ],
            ),
      floatingActionButton: !isFinished
          ? FloatingActionButton.extended(
              onPressed: _addMatch,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nova Partida'),
              backgroundColor: AppColors.primary,
            )
          : null,
    );
  }

  Widget _buildWinnerBanner(String? photoPath) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accent.withOpacity(0.15), AppColors.primary.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: const Border(bottom: BorderSide(color: AppColors.surfaceLight)),
      ),
      child: Row(
        children: [
          // Foto dos vencedores
          GestureDetector(
            onTap: _pickWinnerPhoto,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withOpacity(0.5), width: 2),
                color: AppColors.surfaceLight,
              ),
              child: photoPath != null && File(photoPath).existsSync()
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(File(photoPath), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _photoPlaceholder()),
                    )
                  : _photoPlaceholder(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.emoji_events_rounded, color: AppColors.accent, size: 16),
                    SizedBox(width: 4),
                    Text('CAMPEÃO', style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_champ?.winnerName ?? '—', style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold,
                )),
                if (_champ?.finishedAt != null)
                  Text(AppDateUtils.formatDate(_champ!.finishedAt!),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          // Botão editar foto
          IconButton(
            onPressed: _pickWinnerPhoto,
            icon: const Icon(Icons.add_a_photo_rounded, color: AppColors.accent, size: 20),
            tooltip: 'Foto dos vencedores',
          ),
        ],
      ),
    );
  }

  Widget _photoPlaceholder() => const Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.add_a_photo_rounded, color: AppColors.textHint, size: 24),
      SizedBox(height: 4),
      Text('Foto', style: TextStyle(color: AppColors.textHint, fontSize: 10)),
    ],
  );

  Widget _buildMatches() {
    if (_matches.isEmpty) {
      return EmptyState(
        icon: Icons.sports_soccer_outlined,
        title: 'Nenhuma partida',
        subtitle: 'Toque em "Nova Partida" para adicionar',
        action: _champ?.status == ChampionshipStatus.inProgress
            ? ElevatedButton.icon(onPressed: _addMatch, icon: const Icon(Icons.add), label: const Text('Adicionar Partida'))
            : null,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _matches.length,
      itemBuilder: (_, i) {
        final m = _matches[i];
        return _MatchCard(
          match: m,
          onTap: () => _openMatch(m),
          onDelete: () => _deleteMatch(m),
          champFinished: _champ?.status == ChampionshipStatus.finished,
        );
      },
    );
  }

  Widget _buildTeams() {
    if (_champ == null) return const SizedBox();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _champ!.teams.length,
      itemBuilder: (_, i) {
        final t = _champ!.teams[i];
        final wins = _matches.where((m) => m.isFinished && m.winnerId == t.id).length;
        final played = _matches.where((m) => m.isFinished && (m.teamA.id == t.id || m.teamB.id == t.id)).length;
        return _TeamCard(team: t, wins: wins, played: played);
      },
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }
}

// ── _MatchCard ────────────────────────────────────────────────────
class _MatchCard extends StatelessWidget {
  final MatchModel match;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool champFinished;

  const _MatchCard({required this.match, required this.onTap, this.onDelete, required this.champFinished});

  String _playersLabel(List<TeamPlayer> players) {
    if (players.isEmpty) return 'Sem jogadores';
    final names = players.map((p) => p.playerName).toList();
    return names.length <= 3 ? names.join(', ') : '${names.take(3).join(', ')} +${names.length - 3}';
  }

  @override
  Widget build(BuildContext context) {
    final finished = match.status == MatchStatus.finished;
    final aScore = match.teamAScore;
    final bScore = match.teamBScore;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: finished ? AppColors.win.withOpacity(0.3) : AppColors.surfaceLight),
        ),
        child: Column(
          children: [
            if (match.round != null) ...[
              Text(match.round!, style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(match.teamA.name, textAlign: TextAlign.center, style: TextStyle(
                        color: match.winnerId == match.teamA.id ? AppColors.win : AppColors.textPrimary,
                        fontWeight: FontWeight.bold, fontSize: 14,
                      )),
                      const SizedBox(height: 6),
                      Text(_playersLabel(match.teamA.players), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    finished ? '$aScore × $bScore' : 'VS',
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(match.teamB.name, textAlign: TextAlign.center, style: TextStyle(
                        color: match.winnerId == match.teamB.id ? AppColors.win : AppColors.textPrimary,
                        fontWeight: FontWeight.bold, fontSize: 14,
                      )),
                      const SizedBox(height: 6),
                      Text(_playersLabel(match.teamB.players), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(AppDateUtils.formatDateTime(match.date), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                Row(
                  children: [
                    _StatusBadge(status: match.status, isDraw: match.isDraw),
                    if (onDelete != null) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.delete_rounded, color: AppColors.loss, size: 18),
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {

  final MatchStatus status;
  final bool isDraw;
  const _StatusBadge({required this.status, required this.isDraw});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case MatchStatus.pending: color = AppColors.textHint; label = 'Pendente';
      case MatchStatus.inProgress: color = AppColors.win; label = '● Ao vivo';
      case MatchStatus.finished: color = isDraw ? AppColors.draw : AppColors.accent; label = isDraw ? 'Empate' : 'Finalizada';
      case MatchStatus.cancelled: color = AppColors.loss; label = 'Cancelada';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final Team team;
  final int wins, played;
  const _TeamCard({required this.team, required this.wins, required this.played});

  Color get _color {
    if (team.color == null) return AppColors.primary;
    try { return Color(int.parse('FF${team.color!.replaceAll('#', '')}', radix: 16)); } catch (_) { return AppColors.primary; }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: ExpansionTile(
        leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
        title: Text(team.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        subtitle: Text('$played jogos • $wins vitórias', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        iconColor: AppColors.textHint,
        collapsedIconColor: AppColors.textHint,
        children: team.players.map((p) => ListTile(
          dense: true,
          leading: Icon(Icons.person_rounded, size: 16, color: _color),
          title: Text(p.playerName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          trailing: p.isReserve ? _chip('Reserva', AppColors.textHint) : p.isInTwoTeams ? _chip('2 times', AppColors.draw) : null,
        )).toList(),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
  );
}

// ── Diálogo de seleção de times ──────────────────────────────────
class _SelectTeamsDialog extends StatefulWidget {
  final List<Team> teams;
  final Function(Team, Team, MatchType) onSelect;
  const _SelectTeamsDialog({required this.teams, required this.onSelect});

  @override
  State<_SelectTeamsDialog> createState() => _SelectTeamsDialogState();
}

class _SelectTeamsDialogState extends State<_SelectTeamsDialog> {
  Team? _a, _b;
  MatchType _matchType = MatchType.normal;

  @override
  Widget build(BuildContext context) {
    final canConfirm = _a != null && _b != null && _a!.id != _b!.id;
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Nova Partida', style: TextStyle(color: AppColors.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<Team>(
              value: _a,
              decoration: const InputDecoration(labelText: 'Time A'),
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: AppColors.textPrimary),
              items: widget.teams.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
              onChanged: (v) => setState(() => _a = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Team>(
              value: _b,
              decoration: const InputDecoration(labelText: 'Time B'),
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: AppColors.textPrimary),
              items: widget.teams
                  .where((t) => _a == null || t.id != _a!.id)
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                  .toList(),
              onChanged: (v) => setState(() => _b = v),
            ),
            if (_a != null && _b != null && _a!.id == _b!.id)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Escolha times diferentes', style: TextStyle(color: AppColors.loss, fontSize: 12)),
              ),
            const SizedBox(height: 16),
            const Text('Tipo de partida', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            ...MatchType.values.map((type) {
              final labels = {
                MatchType.normal: ('Partida Normal', Icons.sports_soccer, AppColors.textSecondary),
                MatchType.semifinal: ('Semifinal', Icons.star_half_rounded, AppColors.draw),
                MatchType.final_: ('Final 🏆', Icons.emoji_events_rounded, AppColors.accent),
              };
              final (label, icon, color) = labels[type]!;
              return GestureDetector(
                onTap: () => setState(() => _matchType = type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _matchType == type ? color.withOpacity(0.15) : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _matchType == type ? color : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: _matchType == type ? color : AppColors.textHint, size: 18),
                      const SizedBox(width: 10),
                      Text(label, style: TextStyle(
                        color: _matchType == type ? color : AppColors.textSecondary,
                        fontWeight: _matchType == type ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      )),
                      if (type == MatchType.final_) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('conta vices', style: TextStyle(color: AppColors.accent, fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: canConfirm
              ? () {
                  widget.onSelect(_a!, _b!, _matchType);
                  Navigator.pop(context);
                }
              : null,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}