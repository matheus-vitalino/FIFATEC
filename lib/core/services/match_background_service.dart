import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';

import '../repositories/match_repository.dart';

class MatchBackgroundService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static bool _configured = false;

  static Future<void> initialize() async {
    if (_configured) return;

    await _ensureNotificationPluginReady();

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'FIFATEC',
        initialNotificationContent: 'Cronômetro pronto',
        foregroundServiceNotificationId: _notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _configured = true;
  }

  static Future<void> startTimer({
    required String matchId,
    required int durationSeconds,
    required int elapsedSeconds,
    required int startDelaySeconds,
    required bool showGoalTime,
  }) async {
    await initialize();

    final running = await _service.isRunning();
    if (!running) {
      final started = await _service.startService();
      if (!started) {
        throw StateError('Não foi possível iniciar o serviço em segundo plano.');
      }
      // Aguarda o serviço registrar os listeners em onStart antes de enviar o evento.
      await Future.delayed(const Duration(milliseconds: 600));
    }

    _service.invoke('start_timer', {
      'matchId': matchId,
      'durationSeconds': durationSeconds,
      'elapsedSeconds': elapsedSeconds,
      'startDelaySeconds': startDelaySeconds,
      'showGoalTime': showGoalTime,
      'isResume': false,
    });
  }

  static Future<void> resumeTimer({
    required String matchId,
    required int durationSeconds,
    required int elapsedSeconds,
    required bool showGoalTime,
  }) async {
    await initialize();

    final running = await _service.isRunning();
    if (!running) {
      final started = await _service.startService();
      if (!started) {
        throw StateError('Não foi possível iniciar o serviço em segundo plano.');
      }
      await Future.delayed(const Duration(milliseconds: 600));
    }

    _service.invoke('start_timer', {
      'matchId': matchId,
      'durationSeconds': durationSeconds,
      'elapsedSeconds': elapsedSeconds,
      'startDelaySeconds': 0,
      'showGoalTime': showGoalTime,
      'isResume': true,
    });
  }

  static Future<void> pauseTimer({
    required String matchId,
    required int durationSeconds,
    required int elapsedSeconds,
    required bool showGoalTime,
  }) async {
    await initialize();
    if (!await _service.isRunning()) return;

    _service.invoke('pause_timer', {
      'matchId': matchId,
      'durationSeconds': durationSeconds,
      'elapsedSeconds': elapsedSeconds,
      'showGoalTime': showGoalTime,
    });
  }

  static Future<void> adjustTimer({
    required String matchId,
    required int durationSeconds,
    required int elapsedSeconds,
    required bool showGoalTime,
    required bool running,
  }) async {
    await initialize();

    final serviceRunning = await _service.isRunning();
    if (!serviceRunning) {
      final started = await _service.startService();
      if (!started) {
        throw StateError('Não foi possível iniciar o serviço em segundo plano.');
      }
    }

    _service.invoke('adjust_timer', {
      'matchId': matchId,
      'durationSeconds': durationSeconds,
      'elapsedSeconds': elapsedSeconds,
      'showGoalTime': showGoalTime,
      'running': running,
    });
  }

  static Future<void> resetTimer({
    required String matchId,
    required int durationSeconds,
    required bool showGoalTime,
  }) async {
    await initialize();
    if (!await _service.isRunning()) return;

    _service.invoke('reset_timer', {
      'matchId': matchId,
      'durationSeconds': durationSeconds,
      'showGoalTime': showGoalTime,
    });
  }

  static Future<bool> isRunning() async {
    await initialize();
    return _service.isRunning();
  }

  static Future<void> stopService() async {
    await initialize();
    if (!await _service.isRunning()) return;

    _service.invoke('stop_service');
  }
}

const _notificationChannelId = 'match_timer_foreground';
const _finishNotificationChannelId = 'match_timer_finished_whistle_v4';
const _whistleNotificationChannelId = 'match_timer_whistle_v4';
const _notificationId = 991;
const _finishNotificationId = 992;
const _startNotificationId = 993;

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
bool _notificationsReady = false;

String? _activeMatchId;
String? _startedAtIso;
int _durationSeconds = 0;
int _elapsedSeconds = 0;
int _startDelaySeconds = 0;
bool _showGoalTime = true;
Timer? _runningTimer;
Timer? _delayTimer;
ServiceInstance? _serviceInstance;
int _timerRevision = 0;
int? _lastPublishedElapsed;
int? _lastPersistedElapsed;
bool _isPersistingTimerState = false;

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  _serviceInstance = service;

  await _ensureNotificationPluginReady();
  await _updateForegroundNotification(
    title: 'FIFATEC',
    body: 'Cronômetro ativo',
  );

  service.on('stop_service').listen((event) async {
    _cancelTimers();
    await _cancelForegroundNotification();
    service.stopSelf();
  });

  service.on('start_timer').listen((event) async {
    final data = Map<String, dynamic>.from(event ?? {});
    _timerRevision++;
    _activeMatchId = data['matchId'] as String?;
    _durationSeconds = (data['durationSeconds'] as int?) ?? 0;
    _elapsedSeconds = (data['elapsedSeconds'] as int?) ?? 0;
    _startDelaySeconds = (data['startDelaySeconds'] as int?) ?? 0;
    _showGoalTime = data['showGoalTime'] as bool? ?? true;
    final isResume = data['isResume'] as bool? ?? false;
    _startedAtIso = null;
    _cancelTimers(keepService: true);

    if (_startDelaySeconds > 0) {
      await _runDelayCountdown();
    } else {
      await _beginRunning(playWhistle: !isResume);
    }
  });

  service.on('pause_timer').listen((event) async {
    final data = Map<String, dynamic>.from(event ?? {});
    _timerRevision++;
    _activeMatchId = data['matchId'] as String?;
    _durationSeconds = (data['durationSeconds'] as int?) ?? _durationSeconds;
    _elapsedSeconds = (data['elapsedSeconds'] as int?) ?? _elapsedSeconds;
    _showGoalTime = data['showGoalTime'] as bool? ?? _showGoalTime;
    _cancelTimers(keepService: true);
    await _persistTimerState(running: false);
    _emitTimerUpdate(running: false);
    await _updateForegroundNotification(
      title: 'FIFATEC',
      body: 'Cronômetro pausado em ${_formatClock(_elapsedSeconds)}',
    );
  });

  service.on('adjust_timer').listen((event) async {
    final data = Map<String, dynamic>.from(event ?? {});
    _timerRevision++;
    _activeMatchId = data['matchId'] as String?;
    _durationSeconds = (data['durationSeconds'] as int?) ?? _durationSeconds;
    _elapsedSeconds = ((data['elapsedSeconds'] as int?) ?? _elapsedSeconds)
        .clamp(0, _durationSeconds + 600)
        .toInt();
    _showGoalTime = data['showGoalTime'] as bool? ?? _showGoalTime;
    final shouldRun = data['running'] as bool? ?? (_runningTimer != null);

    _lastPublishedElapsed = null;

    if (shouldRun) {
      _startedAtIso = DateTime.now().toIso8601String();

      if (_elapsedSeconds >= _durationSeconds) {
        await _finishTimer();
        return;
      }

      if (_runningTimer == null) {
        await _beginRunning(playWhistle: false);
        return;
      }

      _publishOfficialTick(force: true);
    } else {
      _startedAtIso = null;
      _emitTimerUpdate(running: false, elapsedSeconds: _elapsedSeconds);
      await _updateForegroundNotification(
        title: 'FIFATEC',
        body: 'Cronômetro pausado em ${_formatClock(_elapsedSeconds)}',
      );
    }
  });

  service.on('reset_timer').listen((event) async {
    final data = Map<String, dynamic>.from(event ?? {});
    _timerRevision++;
    _activeMatchId = data['matchId'] as String?;
    _durationSeconds = (data['durationSeconds'] as int?) ?? _durationSeconds;
    _showGoalTime = data['showGoalTime'] as bool? ?? _showGoalTime;
    _elapsedSeconds = 0;
    _cancelTimers(keepService: true);
    await _persistTimerState(running: false, reset: true);
    _emitTimerUpdate(running: false, reset: true);
    await _updateForegroundNotification(
      title: 'FIFATEC',
      body: 'Cronômetro zerado',
    );
  });
}

Future<void> _ensureNotificationPluginReady() async {
  if (_notificationsReady) return;

  try {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('ic_bg_service_small'),
      iOS: DarwinInitializationSettings(),
    );

    await _notifications.initialize(initializationSettings);

    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _notificationChannelId,
        'FIFATEC Cronômetro',
        description: 'Mostra o cronômetro ativo em segundo plano.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );

    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _finishNotificationChannelId,
        'FIFATEC Fim da Partida',
        description: 'Toca o apito quando o tempo da partida acaba.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('whistle'),
      ),
    );

    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _whistleNotificationChannelId,
        'FIFATEC Apito',
        description: 'Toca o apito no início e no fim da partida.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('whistle'),
      ),
    );

    _notificationsReady = true;
  } catch (_) {
    // Nunca deixe uma falha de notificação derrubar o cronômetro.
    _notificationsReady = false;
  }
}

Future<void> _runDelayCountdown() async {
  _delayTimer?.cancel();

  _serviceInstance?.invoke('timer_delay_tick', {
    'matchId': _activeMatchId,
    'remainingSeconds': _startDelaySeconds,
  });

  await _updateForegroundNotification(
    title: 'FIFATEC',
    body: _startDelaySeconds > 0
        ? 'Iniciando em $_startDelaySeconds s'
        : 'Iniciando partida...',
  );

  _delayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    _startDelaySeconds -= 1;
    if (_startDelaySeconds < 0) _startDelaySeconds = 0;

    _serviceInstance?.invoke('timer_delay_tick', {
      'matchId': _activeMatchId,
      'remainingSeconds': _startDelaySeconds,
    });

    _updateForegroundNotification(
      title: 'FIFATEC',
      body: _startDelaySeconds > 0
          ? 'Iniciando em $_startDelaySeconds s'
          : 'Iniciando partida...',
    );

    if (_startDelaySeconds <= 0) {
      timer.cancel();
      _beginRunning();
    }
  });
}

Future<void> _beginRunning({bool playWhistle = true}) async {
  _runningTimer?.cancel();
  _lastPublishedElapsed = null;

  if (playWhistle) {
    _playWhistle();
    _showWhistleNotification(
      id: _startNotificationId,
      title: 'FIFATEC',
      body: '▶️ Partida iniciada!',
    );
  }

  // Esta é a âncora oficial do cronômetro.
  // A tela e a notificação sempre recebem valores calculados a partir dela.
  _startedAtIso = DateTime.now().toIso8601String();

  _publishOfficialTick(force: true);

  // Tick curto: melhora a chance de atualizar exatamente na troca do segundo.
  // A notificação só é reescrita quando o segundo muda, então não fica pesada.
  _runningTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
    _publishOfficialTick();
  });
}

void _publishOfficialTick({bool force = false}) {
  final current = _currentElapsed().clamp(0, _durationSeconds).toInt();

  if (!force && _lastPublishedElapsed == current) return;
  _lastPublishedElapsed = current;

  final remaining = (_durationSeconds - current).clamp(0, _durationSeconds).toInt();

  _emitTimerUpdate(running: true, elapsedSeconds: current);

  _updateForegroundNotification(
    title: 'FIFATEC',
    body: 'Restante ${_formatClock(remaining)}',
  );

  if (current >= _durationSeconds) {
    _runningTimer?.cancel();
    _runningTimer = null;
    _finishTimer();
    return;
  }

  // Não salva mais no banco a cada 5 segundos.
  // Esse salvamento criava pequenos engasgos exatamente em 00, 05, 10, 15...
  // Agora o checkpoint é bem mais espaçado e não mexe na âncora do timer em memória.
  if (current > 0 && current % 30 == 0 && _lastPersistedElapsed != current) {
    _lastPersistedElapsed = current;
    _persistTimerState(running: true, updateRuntimeAnchor: false);
  }
}

Future<void> _updateForegroundNotification({
  required String title,
  required String body,
}) async {
  try {
    await _ensureNotificationPluginReady();

    await _notifications.show(
      _notificationId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _notificationChannelId,
          'FIFATEC Cronômetro',
          channelDescription: 'Mostra o cronômetro ativo em segundo plano.',
          icon: 'ic_bg_service_small',
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: false,
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
        ),
        iOS: DarwinNotificationDetails(presentSound: false),
      ),
    );
  } catch (_) {
    // Atualizar a notificação é secundário; o cronômetro deve continuar vivo.
  }
}

Future<void> _playWhistle() async {
  try {
    final player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.release);
    await player.play(AssetSource('audio/whistle.mp3'));

    unawaited(
      Future.delayed(const Duration(seconds: 3)).then((_) async {
        try {
          await player.dispose();
        } catch (_) {}
      }),
    );
  } catch (_) {
    // O som via assets é um reforço. Se falhar, a notificação sonora abaixo ainda tenta tocar.
  }
}

Future<void> _showWhistleNotification({
  required int id,
  required String title,
  required String body,
}) async {
  try {
    await _ensureNotificationPluginReady();

    await _notifications.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _whistleNotificationChannelId,
          'FIFATEC Apito',
          channelDescription: 'Toca o apito no início e no fim da partida.',
          icon: 'ic_bg_service_small',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('whistle'),
          enableVibration: true,
          autoCancel: true,
          onlyAlertOnce: false,
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
    );
  } catch (_) {
    // Se a notificação sonora falhar, o cronômetro continua normalmente.
  }
}

Future<void> _showFinishNotification() async {
  try {
    await _ensureNotificationPluginReady();

    await _notifications.show(
      _finishNotificationId,
      'FIFATEC',
      '⏱ Fim do tempo! Apito final.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _finishNotificationChannelId,
          'FIFATEC Fim da Partida',
          channelDescription: 'Toca o apito quando o tempo da partida acaba.',
          icon: 'ic_bg_service_small',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('whistle'),
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
    );
  } catch (_) {
    // Se o som falhar, não deixe o serviço cair.
  }
}

Future<void> _cancelForegroundNotification() async {
  try {
    await _notifications.cancel(_notificationId);
  } catch (_) {}
}

String _formatClock(num secondsValue) {
  final totalSeconds = secondsValue.toInt().clamp(0, 24 * 60 * 60);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

int _currentElapsed() {
  if (_startedAtIso == null) return _elapsedSeconds;

  final startedAt = DateTime.tryParse(_startedAtIso!);
  if (startedAt == null) return _elapsedSeconds;

  // Usa milissegundos para evitar que o truncamento de inSeconds
  // cause dessincronização de até 1 s entre notificação e app.
  return _elapsedSeconds + DateTime.now().difference(startedAt).inMilliseconds ~/ 1000;
}

void _emitTimerUpdate({
  required bool running,
  int? elapsedSeconds,
  bool reset = false,
}) {
  final elapsed = (elapsedSeconds ?? _currentElapsed()).clamp(0, _durationSeconds).toInt();
  final startedAt = _startedAtIso == null ? null : DateTime.tryParse(_startedAtIso!);

  _serviceInstance?.invoke('timer_update', {
    'matchId': _activeMatchId,
    'elapsedSeconds': elapsed,
    'durationSeconds': _durationSeconds,
    'running': running,
    'reset': reset,
    'showGoalTime': _showGoalTime,
    'revision': _timerRevision,
    'baseElapsedSeconds': _elapsedSeconds.clamp(0, _durationSeconds).toInt(),
    'startedAtMillis': running && startedAt != null
        ? startedAt.millisecondsSinceEpoch
        : null,
  });
}

Future<void> _finishTimer() async {
  _cancelTimers(keepService: true);
  _elapsedSeconds = _durationSeconds;
  _startedAtIso = null;

  await _persistTimerState(running: false);
  _emitTimerUpdate(running: false, elapsedSeconds: _durationSeconds);

  await _updateForegroundNotification(
    title: 'FIFATEC',
    body: '⏱ Fim do tempo!',
  );

  await _playWhistle();
  await _showFinishNotification();

  await Future.delayed(const Duration(milliseconds: 1200));

  _serviceInstance?.invoke('timer_finished', {
    'matchId': _activeMatchId,
    'elapsedSeconds': _durationSeconds,
    'durationSeconds': _durationSeconds,
  });

  await _cancelForegroundNotification();
  _serviceInstance?.stopSelf();
}

Future<void> _persistTimerState({
  required bool running,
  bool reset = false,
  bool updateRuntimeAnchor = true,
}) async {
  if (_activeMatchId == null) return;

  // Checkpoint em segundo plano não pode acumular várias escritas no banco.
  if (running && _isPersistingTimerState) return;
  _isPersistingTimerState = true;

  try {
    final repo = MatchRepository();
    final match = await repo.getById(_activeMatchId!);
    if (match == null) return;

    match.timerRunning = running;
    final currentElapsed = reset
        ? 0
        : _currentElapsed().clamp(0, _durationSeconds).toInt();
    match.timerElapsedSeconds = currentElapsed;
    match.durationSeconds = _durationSeconds;
    match.showGoalTime = _showGoalTime;

    if (running) {
      final now = DateTime.now();
      match.timerStartedAt = now;

      // Importante: checkpoint no banco NÃO pode resetar a âncora do cronômetro
      // em memória, senão causa microtravadas/voltas exatamente no momento do save.
      if (updateRuntimeAnchor) {
        _elapsedSeconds = currentElapsed;
        _startedAtIso = now.toIso8601String();
      }
    } else {
      match.timerStartedAt = null;
    }

    await repo.save(match);
  } catch (_) {
    // Salvar no banco é importante, mas não pode derrubar o serviço.
  } finally {
    _isPersistingTimerState = false;
  }
}

void _cancelTimers({bool keepService = false}) {
  _runningTimer?.cancel();
  _runningTimer = null;

  _delayTimer?.cancel();
  _delayTimer = null;

  _startedAtIso = null;
  _lastPublishedElapsed = null;
  _lastPersistedElapsed = null;

  if (!keepService) {
    _serviceInstance = null;
  }
}
