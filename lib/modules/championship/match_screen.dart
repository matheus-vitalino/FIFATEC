import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/match.dart';
import '../../core/models/player.dart';
import '../../core/models/team.dart' show Team, TeamPlayer;
import '../../core/models/team.dart';
import '../../core/repositories/championship_repository.dart';
import '../../core/repositories/match_repository.dart';
import '../../core/repositories/player_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/audio_service.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/custom_app_bar.dart';

class MatchScreen extends StatefulWidget {
  final String matchId;
  final String championshipId;

  const MatchScreen({super.key, required this.matchId, required this.championshipId});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  final _matchRepo = MatchRepository();
  final _champRepo = ChampionshipRepository();
  final _playerRepo = PlayerRepository();
  final _settingsRepo = SettingsRepository();
  final _seasonRepo = SeasonRepository();

  MatchModel? _match;
  bool _loading = true;
  bool _saving = false;

  // Timer
  Timer? _timer;
  Timer? _delayTimer;
  int _elapsed = 0;
  int _duration = 300;
  bool _running = false;

  // Delay: exibe 3, 2, 1 e SÓ ENTÃO começa
  bool _delayActive = false;
  int _delayRemaining = 3; // começa em 3
  int _startDelay = 3;

  int _goalLimit = 2;
  bool _showGoalTime = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _match = await _matchRepo.getById(widget.matchId);
    final settings = await _settingsRepo.get();
    _duration = settings.matchDurationSeconds;
    _startDelay = settings.startDelaySeconds;
    _goalLimit = settings.goalLimit;
    _showGoalTime = settings.showGoalTime;
    if (_match != null) {
      _duration = _match!.durationSeconds;
      _showGoalTime = _match!.showGoalTime;
    }
    setState(() => _loading = false);
  }

  // ── Cronômetro ────────────────────────────────────────────────

  void _startTimer() {
    if (_delayActive || _running) return;
    _updateMatchStatus(MatchStatus.inProgress);

    if (_startDelay > 0) {
      // Inicia o delay: mostra _startDelay, _startDelay-1, ..., 1 e depois começa
      setState(() {
        _delayActive = true;
        _delayRemaining = _startDelay; // Ex: começa em 3
      });
      _delayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        setState(() {
          _delayRemaining--; // 3 → 2 → 1 → 0 (quando chega a 0, para)
          if (_delayRemaining <= 0) {
            _delayActive = false;
            t.cancel();
            AudioService.playWhistle();
            _beginCounting();
          }
        });
      });
    } else {
      _beginCounting();
    }
  }

  void _beginCounting() {
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed++;
        if (_elapsed >= _duration) {
          AudioService.playWhistle();
          _stopTimer();
          _showTimeUpDialog();
        }
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _delayTimer?.cancel();
    _running = false;
    _delayActive = false;
  }

  void _togglePause() {
    if (_running) {
      _stopTimer();
      setState(() {});
    } else if (_elapsed < _duration) {
      _beginCounting();
    }
  }

  // +10s adiciona tempo RESTANTE → reduz _elapsed
  // -10s remove tempo restante → aumenta _elapsed
  void _addTime() => setState(() {
        _elapsed = (_elapsed - 10).clamp(0, _duration);
      });

  void _removeTime() => setState(() {
        _elapsed = (_elapsed + 10).clamp(0, _duration + 600);
      });

  void _resetTimer() {
    _stopTimer();
    setState(() { _elapsed = 0; _delayActive = false; _delayRemaining = _startDelay; });
  }

  Future<void> _updateMatchStatus(MatchStatus status) async {
    if (_match == null) return;
    _match!.status = status;
    await _matchRepo.save(_match!);
  }

  void _showTimeUpDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('⏱ Fim do Tempo!', style: TextStyle(color: AppColors.accent)),
        content: const Text('O que deseja fazer?', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); _confirmResult(); }, child: const Text('Confirmar resultado')),
          TextButton(onPressed: () { Navigator.pop(context); _addPenalties(); }, child: const Text('Pênaltis', style: TextStyle(color: AppColors.draw))),
        ],
      ),
    );
  }

  void _addPenalties() {
    setState(() { _match?.isPenalty = true; });
    if (_match != null) _matchRepo.save(_match!);
  }

  // ── Gols ──────────────────────────────────────────────────────

  Future<void> _registerGoal(Team team, TeamPlayer player) async {
    if (_match == null) return;
    final goal = GoalEvent(
      playerId: player.playerId,
      playerName: player.playerName,
      teamId: team.id,
      timeSeconds: _elapsed,
    );
    setState(() => _match!.goals.add(goal));
    await _matchRepo.save(_match!);

    final aScore = _match!.teamAScore;
    final bScore = _match!.teamBScore;
    if (aScore >= _goalLimit || bScore >= _goalLimit) {
      _stopTimer();
      _showGoalLimitDialog();
    }
  }

  Future<void> _removeGoal(GoalEvent goal) async {
    if (_match == null) return;
    setState(() => _match!.goals.remove(goal));
    await _matchRepo.save(_match!);
  }


  Future<void> _deleteMatch() async {
    if (_match == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Excluir partida?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('A partida será apagada permanentemente.', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir', style: TextStyle(color: AppColors.loss))),
        ],
      ),
    );
    if (confirm != true) return;
    final champ = await _champRepo.getById(widget.championshipId);
    if (champ != null) {
      champ.matchIds.remove(_match!.id);
      await _champRepo.save(champ);
    }
    await _matchRepo.delete(_match!.id);
    if (mounted) Navigator.pop(context);
  }

  void _showGoalLimitDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('⚽ Limite de gols!', style: TextStyle(color: AppColors.goal)),
        content: const Text('O que deseja fazer?', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); _confirmResult(); }, child: const Text('Confirmar resultado')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Continuar', style: TextStyle(color: AppColors.textHint))),
        ],
      ),
    );
  }

  void _showGoalPicker(Team team) {
    final players = team.activePlayers;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text('Gol de ${team.name}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ...players.map((p) => ListTile(
                leading: const Icon(Icons.sports_soccer, color: AppColors.goal),
                title: Text(p.playerName, style: const TextStyle(color: AppColors.textPrimary)),
                onTap: () { Navigator.pop(context); _registerGoal(team, p); },
              )),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: AppColors.textHint),
            title: const Text('Gol sem jogador', style: TextStyle(color: AppColors.textSecondary)),
            onTap: () { Navigator.pop(context); _registerGoal(team, TeamPlayer(playerId: 'unknown', playerName: '?')); },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Substituições ────────────────────────────────────────────
  Future<void> _showSubstitutionPicker(Team team) async {
    // Coleta jogadores disponíveis (não estão ativos no time)
    final allPlayers = await _playerRepo.getAll();
    final activePlayers = team.activePlayers;
    // Jogadores que já foram para fora (substituídos)
    final outPlayerIds = _match!.substitutions
        .where((s) => s.teamId == team.id)
        .map((s) => s.playerOutId)
        .toSet();
    // Jogadores que entraram como substitutos
    final inPlayerIds = _match!.substitutions
        .where((s) => s.teamId == team.id)
        .map((s) => s.playerInId)
        .toSet();

    // Candidatos a sair: jogadores ativos no time
    TeamPlayer? playerOut;
    // Candidatos a entrar: qualquer jogador não no time ativo
    Player? playerIn;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Substituição — ${team.name}',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quem SAI:', style: TextStyle(color: AppColors.loss, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...activePlayers.map((tp) => GestureDetector(
                  onTap: () => setS(() => playerOut = tp),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: playerOut?.playerId == tp.playerId
                          ? AppColors.loss.withOpacity(0.15)
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: playerOut?.playerId == tp.playerId ? AppColors.loss : Colors.transparent,
                      ),
                    ),
                    child: Row(children: [
                      const Icon(Icons.arrow_upward_rounded, color: AppColors.loss, size: 14),
                      const SizedBox(width: 8),
                      Text(tp.playerName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    ]),
                  ),
                )),
                const SizedBox(height: 12),
                const Text('Quem ENTRA:', style: TextStyle(color: AppColors.win, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...allPlayers
                  .where((p) => !activePlayers.any((tp) => tp.playerId == p.id) && p.id != (playerOut?.playerId ?? ''))
                  .map((p) => GestureDetector(
                  onTap: () => setS(() => playerIn = p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: playerIn?.id == p.id
                          ? AppColors.win.withOpacity(0.15)
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: playerIn?.id == p.id ? AppColors.win : Colors.transparent,
                      ),
                    ),
                    child: Row(children: [
                      const Icon(Icons.arrow_downward_rounded, color: AppColors.win, size: 14),
                      const SizedBox(width: 8),
                      Text(p.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    ]),
                  ),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: (playerOut != null && playerIn != null)
                  ? () {
                      Navigator.pop(ctx);
                      _applySubstitution(team, playerOut!, playerIn!);
                    }
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applySubstitution(Team team, TeamPlayer out, Player inPlayer) async {
    if (_match == null) return;
    final sub = SubstitutionEvent(
      teamId: team.id,
      playerOutId: out.playerId,
      playerOutName: out.playerName,
      playerInId: inPlayer.id,
      playerInName: inPlayer.name,
      timeSeconds: _elapsed,
    );

    // Atualiza o time na partida
    final teamRef = _match!.teamA.id == team.id ? _match!.teamA : _match!.teamB;
    final idx = teamRef.players.indexWhere((tp) => tp.playerId == out.playerId);
    if (idx != -1) {
      teamRef.players[idx] = TeamPlayer(
        playerId: inPlayer.id,
        playerName: inPlayer.name,
      );
    }

    setState(() => _match!.substitutions.add(sub));
    await _matchRepo.save(_match!);
  }

  // ── Confirmar resultado ───────────────────────────────────────

  Future<void> _confirmResult() async {
    if (_match == null) return;
    final aScore = _match!.teamAScore;
    final bScore = _match!.teamBScore;

    String? winnerId;
    bool isDraw = false;

    if (aScore > bScore) {
      winnerId = _match!.teamA.id;
    } else if (bScore > aScore) {
      winnerId = _match!.teamB.id;
    } else {
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Empate!', style: TextStyle(color: AppColors.draw)),
          content: const Text('Como resolver?', style: TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'draw'), child: const Text('Empate')),
            TextButton(onPressed: () => Navigator.pop(context, _match!.teamA.id), child: Text(_match!.teamA.name)),
            TextButton(onPressed: () => Navigator.pop(context, _match!.teamB.id), child: Text(_match!.teamB.name)),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'draw') isDraw = true;
      else winnerId = choice;
    }

    setState(() => _saving = true);
    _stopTimer();
    _match!.status = MatchStatus.finished;
    _match!.winnerId = winnerId;
    _match!.isDraw = isDraw;
    await _matchRepo.save(_match!);
    await _updatePlayerStats(winnerId, isDraw);
    setState(() { _saving = false; });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Resultado confirmado! ✅'),
        backgroundColor: AppColors.win,
      ));
    }
  }

  Future<void> _updatePlayerStats(String? winnerId, bool isDraw) async {
    if (_match == null) return;
    final isFinal = _match!.matchType == MatchType.final_;
    final isSemifinal = _match!.matchType == MatchType.semifinal;

    final seasonId = _match!.seasonId ?? (await _seasonRepo.ensureCurrentSeason()).id;

    for (final team in [_match!.teamA, _match!.teamB]) {
      final isWinner = team.id == winnerId;
      final isLoser = !isDraw && !isWinner;

      // Coleta jogadores ativos + substitutos que entraram
      final playerIds = <String>{};
      for (final tp in team.activePlayers) playerIds.add(tp.playerId);
      for (final sub in _match!.substitutions.where((s) => s.teamId == team.id)) {
        playerIds.add(sub.playerInId);
      }

      for (final pid in playerIds) {
        await _playerRepo.updateStats(pid,
          seasonId: seasonId,
          matchesDelta: 1,
          winsDelta: isWinner ? 1 : 0,
          lossesDelta: isLoser ? 1 : 0,
          // Na final: vencedor = título, perdedor = vice
          titlesDelta: (isFinal && isWinner) ? 1 : 0,
          vicesDelta: (isFinal && isLoser) ? 1 : 0,
          // Semifinal e final contam como "final" nas estatísticas
          finalsDelta: (isFinal || isSemifinal) ? 1 : 0,
        );
      }
    }
    for (final goal in _match!.goals) {
      if (goal.playerId != 'unknown') {
        await _playerRepo.updateStats(goal.playerId, seasonId: seasonId, goalsDelta: 1);
      }
    }
  }

  int get _remaining => (_duration - _elapsed).clamp(0, _duration);
  double get _progress => _duration > 0 ? _elapsed / _duration : 0;

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Partida',
        actions: [
          if (_match != null)
            IconButton(
              icon: const Icon(Icons.delete_rounded, color: AppColors.loss),
              onPressed: _deleteMatch,
            ),
          if (_match != null && !_match!.isFinished)
            TextButton(
              onPressed: _saving ? null : _confirmResult,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                  : const Text('Confirmar', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _match == null
              ? const EmptyState(icon: Icons.error, title: 'Partida não encontrada', subtitle: '')
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final m = _match!;
    final aScore = m.teamAScore;
    final bScore = m.teamBScore;
    final finished = m.isFinished;

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildTimer(finished),
          const SizedBox(height: 8),
          _buildScoreboard(m, aScore, bScore, finished),
          const SizedBox(height: 16),
          if (!finished) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: _goalButton(m.teamA)),
                  const SizedBox(width: 12),
                  Expanded(child: _goalButton(m.teamB)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: _subButton(m.teamA)),
                  const SizedBox(width: 12),
                  Expanded(child: _subButton(m.teamB)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildGoalLog(m, finished),
        ],
      ),
    );
  }

  Widget _buildTimer(bool finished) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        children: [
          // Display principal: delay ou tempo restante
          if (_delayActive)
            Text(
              // Mostra 3, 2, 1 — quando _delayRemaining=0 já iniciou
              '$_delayRemaining',
              style: const TextStyle(color: AppColors.accent, fontSize: 72, fontWeight: FontWeight.bold),
            )
          else ...[
            Text(
              AppDateUtils.formatDuration(_remaining),
              style: TextStyle(
                color: _remaining < 30 && _running ? AppColors.loss : AppColors.textPrimary,
                fontSize: 52,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: 1 - _progress,
                backgroundColor: AppColors.surfaceLight,
                valueColor: AlwaysStoppedAnimation<Color>(_remaining < 30 ? AppColors.loss : AppColors.win),
                minHeight: 8,
              ),
            ),
          ],

          const SizedBox(height: 16),

          if (!finished && !_delayActive)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // -10s = REMOVE tempo restante (aumenta elapsed) — fica na esquerda
                _timerBtn('-10s', _removeTime, color: AppColors.loss),
                const SizedBox(width: 8),

                // Botão principal
                if (!_running && _elapsed == 0)
                  ElevatedButton.icon(
                    onPressed: _startTimer,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(_startDelay > 0 ? 'Iniciar (${_startDelay}s)' : 'Iniciar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.win,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _togglePause,
                    icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    label: Text(_running ? 'Pausar' : 'Continuar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _running ? AppColors.draw : AppColors.win,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),

                const SizedBox(width: 8),
                // +10s = ADICIONA tempo restante (reduz elapsed) — fica na direita
                _timerBtn('+10s', _addTime, color: AppColors.win),
                const SizedBox(width: 6),
                _timerBtn('↺', _resetTimer, color: AppColors.textHint),
              ],
            ),

          if (_delayActive)
            const Text('Preparar...', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _timerBtn(String label, VoidCallback onTap, {Color color = AppColors.textSecondary}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildScoreboard(MatchModel m, int aScore, int bScore, bool finished) {
    final aWin = aScore > bScore;
    final bWin = bScore > aScore;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text(m.teamA.name, textAlign: TextAlign.center, style: TextStyle(
                  color: aWin ? AppColors.win : AppColors.textPrimary,
                  fontWeight: FontWeight.bold, fontSize: 14,
                )),
                const SizedBox(height: 12),
                Text('$aScore', style: TextStyle(
                  color: aWin ? AppColors.win : AppColors.textPrimary,
                  fontSize: 52, fontWeight: FontWeight.bold,
                )),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              children: [
                if (finished)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: m.isDraw ? AppColors.draw.withOpacity(0.2) : AppColors.win.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(m.isDraw ? 'EMPATE' : 'FIM', style: TextStyle(
                      color: m.isDraw ? AppColors.draw : AppColors.win,
                      fontSize: 11, fontWeight: FontWeight.bold,
                    )),
                  )
                else
                  const Text('×', style: TextStyle(color: AppColors.textHint, fontSize: 28, fontWeight: FontWeight.bold)),
                if (m.isPenalty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('PÊNALTIS', style: TextStyle(color: AppColors.draw, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(m.teamB.name, textAlign: TextAlign.center, style: TextStyle(
                  color: bWin ? AppColors.win : AppColors.textPrimary,
                  fontWeight: FontWeight.bold, fontSize: 14,
                )),
                const SizedBox(height: 12),
                Text('$bScore', style: TextStyle(
                  color: bWin ? AppColors.win : AppColors.textPrimary,
                  fontSize: 52, fontWeight: FontWeight.bold,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _goalButton(Team team) {
    return ElevatedButton(
      onPressed: () => _showGoalPicker(team),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary.withOpacity(0.2),
        foregroundColor: AppColors.accent,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sports_soccer, size: 18),
          const SizedBox(width: 6),
          Flexible(child: Text('⚽ ${team.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _subButton(Team team) {
    return OutlinedButton(
      onPressed: () => _showSubstitutionPicker(team),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.draw,
        side: const BorderSide(color: AppColors.draw),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.swap_horiz_rounded, size: 16),
          const SizedBox(width: 6),
          Flexible(child: Text('Sub ${team.name}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildGoalLog(MatchModel m, bool finished) {
    if (m.goals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Nenhum gol registrado', style: TextStyle(color: AppColors.textHint, fontSize: 13), textAlign: TextAlign.center),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Gols'),
          ...m.goals.map((goal) {
            final isTeamA = goal.teamId == m.teamA.id;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sports_soccer, color: AppColors.goal, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(goal.playerName == '?' ? 'Gol sem jogador' : goal.playerName,
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(isTeamA ? m.teamA.name : m.teamB.name,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (_showGoalTime)
                    Text(AppDateUtils.formatDuration(goal.timeSeconds),
                        style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                  if (!finished)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.loss, size: 16),
                      onPressed: () => _removeGoal(goal),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            );
          }),
          // Log de substituições
          if (m.substitutions.isNotEmpty) ...[
            const SectionHeader(title: 'Substituições'),
            ...m.substitutions.map((sub) {
              final isTeamA = sub.teamId == m.teamA.id;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz_rounded, color: AppColors.draw, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(text: TextSpan(
                            style: const TextStyle(fontSize: 12),
                            children: [
                              TextSpan(text: sub.playerOutName,
                                  style: const TextStyle(color: AppColors.loss, fontWeight: FontWeight.bold)),
                              const TextSpan(text: ' → ', style: TextStyle(color: AppColors.textHint)),
                              TextSpan(text: sub.playerInName,
                                  style: const TextStyle(color: AppColors.win, fontWeight: FontWeight.bold)),
                            ],
                          )),
                          Text(isTeamA ? m.teamA.name : m.teamB.name,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                    if (_showGoalTime)
                      Text(AppDateUtils.formatDuration(sub.timeSeconds),
                          style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _delayTimer?.cancel();
    super.dispose();
  }
}