import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/services/match_background_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/match.dart';
import '../../core/models/player.dart';
import '../../core/models/team.dart';
import '../../core/repositories/championship_repository.dart';
import '../../core/repositories/match_repository.dart';
import '../../core/repositories/player_repository.dart';
import '../../core/repositories/settings_repository.dart';
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

  MatchModel? _match;
  bool _loading = true;
  bool _saving = false;

  StreamSubscription? _timerUpdateSub;
  StreamSubscription? _delayTickSub;
  StreamSubscription? _timerFinishedSub;
  Timer? _uiTicker;

  DateTime? _delayStartedAt;

  int _elapsed = 0;
  int _runningBaseElapsed = 0;
  DateTime? _runningSince;
  int _duration = 300;
  bool _running = false;

  bool _delayActive = false;
  int _delayRemaining = 3;
  int _startDelay = 3;

  int _goalLimit = 2;
  bool _showGoalTime = true;
  int _lastTimerRevision = 0;

  @override
  void initState() {
    super.initState();
    _bindBackgroundEvents();
    _load();
  }

  void _bindBackgroundEvents() {
    final service = FlutterBackgroundService();

    _timerUpdateSub = service.on('timer_update').listen((event) async {
      if (!mounted || _match == null) return;

      final data = Map<String, dynamic>.from(event ?? {});
      if (data['matchId'] != _match!.id) return;

      final revision = (data['revision'] as int?) ?? _lastTimerRevision;
      if (revision < _lastTimerRevision) return;
      _lastTimerRevision = revision;

      final elapsed = (data['elapsedSeconds'] as int?) ?? _elapsed;
      final running = data['running'] as bool? ?? false;
      final reset = data['reset'] as bool? ?? false;
      final baseElapsed = (data['baseElapsedSeconds'] as int?) ?? elapsed;
      final startedAtMillis = data['startedAtMillis'] as int?;
      final serviceStartedAt = startedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(startedAtMillis);

      final serviceElapsed = elapsed.clamp(0, _duration).toInt();
      final serviceBaseElapsed = baseElapsed.clamp(0, _duration).toInt();

      if (reset) {
        _stopUiTicker();
        setState(() {
          _delayActive = false;
          _delayStartedAt = null;
          _running = false;
          _runningSince = null;
          _runningBaseElapsed = 0;
          _elapsed = 0;
          _delayRemaining = _startDelay;
        });
      } else if (running) {
        // Fonte única: o serviço manda o mesmo segundo oficial usado na notificação.
        // A tela apenas mostra esse valor, sem recalcular por conta própria.
        _stopUiTicker();
        setState(() {
          _elapsed = serviceElapsed;
          _running = true;
          _delayActive = false;
          _delayStartedAt = null;
          _delayRemaining = _startDelay;
          _runningBaseElapsed = serviceBaseElapsed;
          _runningSince = serviceStartedAt;
        });
      } else {
        _stopUiTicker();
        setState(() {
          _elapsed = serviceElapsed.clamp(0, _duration).toInt();
          _running = false;
          _delayActive = false;
          _delayStartedAt = null;
          _runningSince = null;
          _runningBaseElapsed = _elapsed;
        });
      }

      _match!.timerElapsedSeconds = _elapsed;
      _match!.timerRunning = running;
      _match!.timerStartedAt = running ? _runningSince : null;
    });

    _delayTickSub = service.on('timer_delay_tick').listen((event) {
      if (!mounted || _match == null) return;

      final data = Map<String, dynamic>.from(event ?? {});
      if (data['matchId'] != _match!.id) return;

      final remaining = (data['remainingSeconds'] as int?) ?? 0;
      setState(() {
        _delayRemaining = remaining.clamp(0, _startDelay).toInt();
        _delayActive = _delayRemaining > 0;

        if (_delayActive && _delayStartedAt == null) {
          _delayStartedAt = DateTime.now();
        }

        if (_delayRemaining == 0) {
          _delayActive = false;
          _delayStartedAt = null;
          _running = true;
          if (_runningSince == null) {
            _runningSince = DateTime.now();
            _runningBaseElapsed = _elapsed;
          }
        }
      });

      _startUiTicker();
    });

    _timerFinishedSub = service.on('timer_finished').listen((event) {
      if (!mounted || _match == null) return;

      final data = Map<String, dynamic>.from(event ?? {});
      if (data['matchId'] != _match!.id) return;

      _stopUiTicker();
      setState(() {
        _running = false;
        _delayActive = false;
        _delayStartedAt = null;
        _runningSince = null;
        _runningBaseElapsed = _duration;
        _elapsed = _duration;
      });

      _match!.timerRunning = false;
      _match!.timerElapsedSeconds = _duration;
      _match!.timerStartedAt = null;
      _matchRepo.save(_match!);

      if (mounted) {
        _showTimeUpDialog();
      }
    });
  }

  int _calculateLocalElapsed() {
    // O tempo exibido vem do serviço em segundo plano, que também atualiza a notificação.
    // Por isso, ações como pausar, +10s e -10s usam exatamente o valor que está na tela.
    return _elapsed.clamp(0, _duration).toInt();
  }

  int _calculateLocalDelayRemaining() {
    if (!_delayActive) return 0;

    final started = _delayStartedAt;
    if (started == null) return _delayRemaining.clamp(0, _startDelay).toInt();

    final passedSeconds = DateTime.now().difference(started).inMilliseconds ~/ 1000;
    return (_startDelay - passedSeconds).clamp(0, _startDelay).toInt();
  }

  void _startUiTicker() {
    if (_uiTicker?.isActive == true) return;

    _uiTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _match == null) return;

      if (_delayActive) {
        final nextRemaining = _calculateLocalDelayRemaining();

        if (nextRemaining != _delayRemaining) {
          setState(() {
            _delayRemaining = nextRemaining;
            if (_delayRemaining == 0) {
              _delayActive = false;
              _delayStartedAt = null;
              _running = true;
              _runningSince = DateTime.now();
              _runningBaseElapsed = _elapsed;
            }
          });
        }
        return;
      }

      // Quando a partida está rodando, quem atualiza o tempo da tela é o serviço.
      // Assim o cronômetro do app e o da notificação exibem exatamente o mesmo valor.
    });
  }

  void _stopUiTicker() {
    _uiTicker?.cancel();
    _uiTicker = null;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _match = await _matchRepo.getById(widget.matchId);
      final settings = await _settingsRepo.get();
      _duration = settings.matchDurationSeconds;
      _startDelay = settings.startDelaySeconds;
      _goalLimit = settings.goalLimit;
      _showGoalTime = settings.showGoalTime;

      if (_match != null) {
        _duration = _match!.durationSeconds;
        _showGoalTime = _match!.showGoalTime;

        if (_match!.timerRunning && _match!.timerStartedAt != null) {
          final currentElapsed = (_match!.timerElapsedSeconds +
                  DateTime.now().difference(_match!.timerStartedAt!).inSeconds)
              .clamp(0, _duration)
              .toInt();

          _elapsed = currentElapsed;
          _running = true;
          _runningSince = _match!.timerStartedAt;
          _runningBaseElapsed = _match!.timerElapsedSeconds;

          try {
            await MatchBackgroundService.resumeTimer(
              matchId: _match!.id,
              durationSeconds: _duration,
              elapsedSeconds: currentElapsed,
              showGoalTime: _showGoalTime,
            );
          } catch (_) {
            _running = false;
            _stopUiTicker();
            _match!.timerRunning = false;
            _match!.timerStartedAt = null;
            await _matchRepo.save(_match!);
          }
        } else {
          _elapsed = _match!.timerElapsedSeconds.clamp(0, _duration).toInt();
          _running = _match!.timerRunning;
          if (_running) {
            _runningSince = _match!.timerStartedAt;
            _runningBaseElapsed = _match!.timerElapsedSeconds;
          }
        }
      }

      if (_match != null &&
          !_match!.timerRunning &&
          _elapsed >= _duration &&
          _match!.status == MatchStatus.inProgress) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showTimeUpDialog();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ── Cronômetro ────────────────────────────────────────────────

  Future<void> _startTimer() async {
    if (_delayActive || _running || _match == null) return;

    final permission = await Permission.notification.status;
    if (!permission.isGranted) {
      final requested = await Permission.notification.request();
      if (!requested.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permita as notificações para iniciar o cronômetro em segundo plano.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    }

    await _updateMatchStatus(MatchStatus.inProgress);

    final hasDelay = _startDelay > 0;
    setState(() {
      _delayActive = hasDelay;
      _delayRemaining = _startDelay;
      _delayStartedAt = hasDelay ? DateTime.now() : null;
      _running = !hasDelay;
      // Não define _runningSince aqui: o primeiro timer_update do serviço
      // enviará o startedAtMillis exato e o listener sincronizará a âncora.
      // Isso evita drift entre app e notificação causado pelo delay de inicialização.
      _runningSince = null;
      _runningBaseElapsed = _elapsed;
    });

    try {
      await MatchBackgroundService.startTimer(
        matchId: _match!.id,
        durationSeconds: _duration,
        elapsedSeconds: _elapsed,
        startDelaySeconds: _startDelay,
        showGoalTime: _showGoalTime,
      );

      if (_startDelay == 0 && mounted) {
        setState(() => _running = true);
      }
    } catch (e) {
      if (!mounted) return;

      _stopUiTicker();
      setState(() {
        _delayActive = false;
        _running = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao iniciar o cronômetro: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _pauseTimer() async {
    if (_match == null) return;
    try {
      final currentElapsed = _calculateLocalElapsed();
      _stopUiTicker();
      setState(() {
        _elapsed = currentElapsed;
        _running = false;
        _delayActive = false;
        _delayStartedAt = null;
      });
      _match!.timerRunning = false;
      _match!.timerElapsedSeconds = _elapsed.clamp(0, _duration).toInt();
      _match!.timerStartedAt = null;
      await _matchRepo.save(_match!);
      await MatchBackgroundService.pauseTimer(
        matchId: _match!.id,
        durationSeconds: _duration,
        elapsedSeconds: _elapsed,
        showGoalTime: _showGoalTime,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao pausar o cronômetro: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _togglePause() async {
    if (_running) {
      await _pauseTimer();
    } else if (_elapsed < _duration && _match != null) {
      final permission = await Permission.notification.status;
      if (!permission.isGranted) {
        final requested = await Permission.notification.request();
        if (!requested.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Permita as notificações para retomar o cronômetro em segundo plano.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
      }

      _match!.timerRunning = true;
      _match!.timerElapsedSeconds = _elapsed;
      _match!.timerStartedAt = null; // será atualizado pelo timer_update do serviço
      // Não define _runningSince aqui: o primeiro timer_update do serviço
      // enviará o startedAtMillis exato e sincronizará a âncora local.
      _runningSince = null;
      _runningBaseElapsed = _elapsed;
      await _matchRepo.save(_match!);

      try {
        await MatchBackgroundService.resumeTimer(
          matchId: _match!.id,
          durationSeconds: _duration,
          elapsedSeconds: _elapsed,
          showGoalTime: _showGoalTime,
        );
        if (mounted) {
          setState(() {
            _running = true;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Falha ao retomar o cronômetro: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _setElapsed(int value) async {
    final wasRunning = _running;
    final newElapsed = value.clamp(0, _duration + 600).toInt();
    final now = DateTime.now();

    setState(() {
      _elapsed = newElapsed;
      _delayActive = false;
      _delayStartedAt = null;
      _runningBaseElapsed = newElapsed;
      _runningSince = wasRunning ? now : null;
      _running = wasRunning;
    });

    if (_match == null) return;

    try {
      _match!.timerElapsedSeconds = newElapsed;
      _match!.timerRunning = wasRunning;
      _match!.timerStartedAt = wasRunning ? now : null;
      await _matchRepo.save(_match!);

      final serviceIsRunning = await MatchBackgroundService.isRunning();
      if (serviceIsRunning || wasRunning) {
        await MatchBackgroundService.adjustTimer(
          matchId: _match!.id,
          durationSeconds: _duration,
          elapsedSeconds: newElapsed,
          showGoalTime: _showGoalTime,
          running: wasRunning,
        );
      }

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao atualizar o tempo: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _addTime() async {
    await _setElapsed(_calculateLocalElapsed() - 10);
  }

  Future<void> _removeTime() async {
    await _setElapsed(_calculateLocalElapsed() + 10);
  }

  Future<void> _resetTimer() async {
    if (_match == null) return;
    try {
      _stopUiTicker();
      setState(() {
        _elapsed = 0;
        _delayActive = false;
        _delayStartedAt = null;
        _delayRemaining = _startDelay;
        _running = false;
        _runningSince = null;
        _runningBaseElapsed = 0;
      });
      _match!.timerRunning = false;
      _match!.timerElapsedSeconds = 0;
      _match!.timerStartedAt = null;
      await _matchRepo.save(_match!);
      await MatchBackgroundService.resetTimer(
        matchId: _match!.id,
        durationSeconds: _duration,
        showGoalTime: _showGoalTime,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao resetar o cronômetro: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
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

  Future<void> _registerOwnGoal(Team benefitingTeam, TeamPlayer player) async {
    // Gol contra: quem faz é o jogador selecionado, mas o ponto vai para o time adversário dele.
    if (_match == null) return;
    final goal = GoalEvent(
      playerId: player.playerId,
      playerName: player.playerName,
      teamId: benefitingTeam.id,
      timeSeconds: _elapsed,
      isOwnGoal: true,
    );
    setState(() => _match!.goals.add(goal));
    await _matchRepo.save(_match!);

    final aScore = _match!.teamAScore;
    final bScore = _match!.teamBScore;
    if (aScore >= _goalLimit || bScore >= _goalLimit) {
      await _pauseTimer();
      _showGoalLimitDialog();
    }
  }

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
      await _pauseTimer();
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
    if (_match == null) return;
    final players = team.activePlayers;
    final opponent = team.id == _match!.teamA.id ? _match!.teamB : _match!.teamA;
    final opponentPlayers = opponent.activePlayers;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Text('Gol para ${team.name}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Gol normal', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
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
                if (opponentPlayers.isNotEmpty) ...[
                  const Divider(color: AppColors.surfaceLight, height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Gol contra de ${opponent.name}', style: const TextStyle(color: AppColors.loss, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  ...opponentPlayers.map((p) => ListTile(
                        leading: const Icon(Icons.warning_rounded, color: AppColors.loss),
                        title: Text(p.playerName, style: const TextStyle(color: AppColors.textPrimary)),
                        subtitle: Text('Ponto para ${team.name}', style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                        onTap: () { Navigator.pop(context); _registerOwnGoal(team, p); },
                      )),
                ],
              ],
            ),
          ),
        ),
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
    await MatchBackgroundService.stopService();
    _match!.timerRunning = false;
    _match!.timerStartedAt = null;
    _match!.timerElapsedSeconds = _elapsed.clamp(0, _duration).toInt();
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
    final seasonId = _match!.seasonId ?? widget.championshipId;

    for (final team in [_match!.teamA, _match!.teamB]) {
      final isWinner = team.id == winnerId;
      final isLoser = !isDraw && !isWinner;

      final playerIds = <String>{};
      for (final tp in team.activePlayers) playerIds.add(tp.playerId);
      for (final sub in _match!.substitutions.where((s) => s.teamId == team.id)) {
        playerIds.add(sub.playerInId);
      }

      for (final pid in playerIds) {
        await _playerRepo.updateStats(
          pid,
          seasonId: seasonId,
          matchesDelta: 1,
          winsDelta: isWinner ? 1 : 0,
          lossesDelta: isLoser ? 1 : 0,
          titlesDelta: (isFinal && isWinner) ? 1 : 0,
          vicesDelta: (isFinal && isLoser) ? 1 : 0,
          finalsDelta: (isFinal || isSemifinal) ? 1 : 0,
        );
      }
    }
    for (final goal in _match!.goals) {
      if (goal.playerId == 'unknown') continue;
      await _playerRepo.updateStats(
        goal.playerId,
        seasonId: seasonId,
        goalsDelta: goal.isOwnGoal ? 0 : 1,
        ownGoalsDelta: goal.isOwnGoal ? 1 : 0,
      );
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

  Widget _timerBtn(String label, FutureOr<void> Function() onTap, {Color color = AppColors.textSecondary}) {
    return GestureDetector(
      onTap: () {
        final result = onTap();
        if (result is Future<void>) {
          unawaited(result);
        }
      },
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
            final teamName = isTeamA ? m.teamA.name : m.teamB.name;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    goal.isOwnGoal ? Icons.warning_rounded : Icons.sports_soccer,
                    color: goal.isOwnGoal ? AppColors.loss : AppColors.goal,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.isOwnGoal
                              ? 'Gol contra: ${goal.playerName}'
                              : (goal.playerName == '?' ? 'Gol sem jogador' : goal.playerName),
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Text(
                          goal.isOwnGoal ? 'Ponto para $teamName' : teamName,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
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
    _stopUiTicker();
    _timerUpdateSub?.cancel();
    _delayTickSub?.cancel();
    _timerFinishedSub?.cancel();
    super.dispose();
  }
}