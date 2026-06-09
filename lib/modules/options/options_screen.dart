import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/season.dart';
import '../../core/repositories/settings_repository.dart'
    show SettingsRepository, SeasonRepository;
import '../../core/services/backup_service.dart';
import '../../core/services/google_drive_backup_service.dart';
import '../../shared/widgets/custom_app_bar.dart';
import 'package:uuid/uuid.dart';

class OptionsScreen extends StatefulWidget {
  const OptionsScreen({super.key});

  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  final _settingsRepo = SettingsRepository();
  final _seasonRepo = SeasonRepository();
  final _backupService = BackupService();
  final _driveBackupService = GoogleDriveBackupService();
  final _uuid = const Uuid();

  AppSettings _settings = AppSettings();
  List<Season> _seasons = [];
  bool _loading = true;
  bool _saving = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _settings = await _settingsRepo.get();
    _seasons = await _seasonRepo.getAll();
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    await _settingsRepo.save(_settings);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações salvas!'), backgroundColor: AppColors.win),
      );
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _saving = true);
    try {
      final savedPath = await _backupService.exportBackupToSelectedLocation();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedPath == null
                ? 'Exportação cancelada.'
                : 'Backup salvo no local escolhido!',
          ),
          backgroundColor: savedPath == null ? AppColors.draw : AppColors.win,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar: $e'), backgroundColor: AppColors.loss),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareBackup() async {
    setState(() => _saving = true);
    try {
      await _backupService.shareBackup();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao compartilhar: $e'), backgroundColor: AppColors.loss),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportOnlineBackup() async {
    setState(() => _saving = true);
    try {
      final result = await _driveBackupService.exportOnlineBackup(
        folderLink: _settings.googleDriveFolderLink,
        ownerEmail: _settings.googleDriveOwnerEmail,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.name.isEmpty
                ? 'Backup enviado para o Google Drive!'
                : 'Backup online enviado: ${result.name}',
          ),
          backgroundColor: AppColors.win,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar online: $e'), backgroundColor: AppColors.loss),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _importOnlineBackup() async {
    try {
      setState(() => _saving = true);
      final onlineFiles = await _driveBackupService.listOnlineBackups(
        _settings.googleDriveFolderLink,
      );
      if (!mounted) return;

      setState(() => _saving = false);

      if (onlineFiles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhum backup .zip encontrado nessa pasta online.'),
            backgroundColor: AppColors.draw,
          ),
        );
        return;
      }

      final selectedFile = await _showOnlineBackupPickerDialog(onlineFiles);
      if (selectedFile == null) return;

      setState(() => _saving = true);
      final downloadedFile = await _driveBackupService.downloadOnlineBackup(selectedFile);
      if (!mounted) return;

      final preview = await _backupService.readBackupPreview(downloadedFile.path);
      if (!mounted) return;

      setState(() => _saving = false);
      final options = await _showImportOptionsDialog(preview);
      if (options == null || !options.hasAnything) return;

      setState(() => _saving = true);
      await _backupService.importBackup(downloadedFile.path, options: options);
      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup online importado: ${selectedFile.name}'),
            backgroundColor: AppColors.win,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao importar online: $e'), backgroundColor: AppColors.loss),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<GoogleDriveBackupFile?> _showOnlineBackupPickerDialog(
    List<GoogleDriveBackupFile> files,
  ) async {
    return showDialog<GoogleDriveBackupFile>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Importar backup online',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: files.length,
            separatorBuilder: (_, __) => const Divider(color: AppColors.surfaceLight),
            itemBuilder: (context, index) {
              final file = files[index];
              final modified = file.modifiedTime;
              final modifiedText = modified == null
                  ? 'Data não informada'
                  : '${modified.day.toString().padLeft(2, '0')}/${modified.month.toString().padLeft(2, '0')}/${modified.year} às ${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}';

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_download_rounded, color: AppColors.accent),
                title: Text(
                  file.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  modifiedText,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                onTap: () => Navigator.pop(context, file),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editGoogleDriveSettings() async {
    final folderCtrl = TextEditingController(text: _settings.googleDriveFolderLink);
    final ownerCtrl = TextEditingController(text: _settings.googleDriveOwnerEmail);

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Google Drive Online',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Link da pasta de backups:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: folderCtrl,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.background,
                  hintText: AppSettings.defaultGoogleDriveFolderLink,
                  hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.surfaceLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'E-mail dono que pode exportar online:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: ownerCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.background,
                  hintText: 'exemplo@gmail.com',
                  hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.surfaceLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Deixe o e-mail vazio se quiser permitir exportação para qualquer conta que tenha permissão de escrita na pasta.',
                style: TextStyle(color: AppColors.textHint, fontSize: 11.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.background,
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    setState(() {
      _settings = _settings.copyWith(
        googleDriveFolderLink: folderCtrl.text.trim().isEmpty
            ? AppSettings.defaultGoogleDriveFolderLink
            : folderCtrl.text.trim(),
        googleDriveOwnerEmail: ownerCtrl.text.trim(),
      );
    });

    await _settingsRepo.save(_settings);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações do Drive salvas!'), backgroundColor: AppColors.win),
      );
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.single.path == null) return;
      if (!mounted) return;

      // Lê o preview do arquivo antes de mostrar o dialog
      final preview = await _backupService.readBackupPreview(result.files.single.path!);
      if (!mounted) return;

      final options = await _showImportOptionsDialog(preview);
      if (options == null || !options.hasAnything) return;

      setState(() => _saving = true);
      await _backupService.importBackup(
        result.files.single.path!,
        options: options,
      );
      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup importado com sucesso!'), backgroundColor: AppColors.win),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao importar: $e'), backgroundColor: AppColors.loss),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<BackupImportOptions?> _showImportOptionsDialog(BackupPreview preview) async {
    bool players = true;
    bool playerStats = true;
    bool championships = true;
    bool matches = true;
    bool seasons = true;
    bool settings = true;
    bool images = true;
    bool overwrite = true;
    bool showPreview = false;

    return showDialog<BackupImportOptions>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final allSelected = players &&
              playerStats &&
              championships &&
              matches &&
              seasons &&
              settings &&
              images;
          final canImport = players ||
              playerStats ||
              championships ||
              matches ||
              seasons ||
              settings ||
              images;

          void setAll(bool value) {
            setDialogState(() {
              players = value;
              playerStats = value;
              championships = value;
              matches = value;
              seasons = value;
              settings = value;
              images = value;
            });
          }

          return AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text(
              'O que importar?',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Modo de importação ──────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          _ModeRadioTile(
                            icon: Icons.layers_clear_rounded,
                            title: 'Sobrescrever atual',
                            subtitle: 'Apaga os dados marcados e substitui pelos do backup',
                            selected: overwrite,
                            onTap: () => setDialogState(() => overwrite = true),
                          ),
                          const Divider(height: 1, color: AppColors.card),
                          _ModeRadioTile(
                            icon: Icons.call_merge_rounded,
                            title: 'Juntar com atual',
                            subtitle: 'Mantém dados existentes e adiciona os novos do backup',
                            selected: !overwrite,
                            onTap: () => setDialogState(() => overwrite = false),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Preview do arquivo ──────────────────────────────
                    GestureDetector(
                      onTap: () => setDialogState(() => showPreview = !showPreview),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.preview_rounded, color: AppColors.accent, size: 18),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Preview do backup',
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              showPreview
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: AppColors.textSecondary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (showPreview) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PreviewRow(
                              icon: Icons.groups_rounded,
                              label: 'Jogadores',
                              count: preview.playerCount,
                              names: preview.playerNames,
                            ),
                            _PreviewRow(
                              icon: Icons.emoji_events_rounded,
                              label: 'Campeonatos',
                              count: preview.championshipCount,
                              names: preview.championshipNames,
                            ),
                            _PreviewRow(
                              icon: Icons.sports_soccer_rounded,
                              label: 'Partidas',
                              count: preview.matchCount,
                              names: const [],
                            ),
                            _PreviewRow(
                              icon: Icons.calendar_month_rounded,
                              label: 'Temporadas',
                              count: preview.seasonCount,
                              names: preview.seasonNames,
                            ),
                            _PreviewRow(
                              icon: Icons.photo_library_rounded,
                              label: 'Imagens',
                              count: preview.imageCount,
                              names: const [],
                            ),
                            _PreviewRow(
                              icon: Icons.settings_rounded,
                              label: 'Configurações',
                              count: preview.hasSettings ? 1 : 0,
                              names: const [],
                              isBool: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ── Checkboxes de categorias ────────────────────────
                    const Text(
                      'Categorias para importar:',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _BackupCheckTile(
                      icon: Icons.done_all_rounded,
                      title: 'Selecionar tudo',
                      subtitle: 'Importa todos os dados e imagens',
                      value: allSelected,
                      onChanged: (value) => setAll(value ?? false),
                    ),
                    const Divider(color: AppColors.surfaceLight),
                    _BackupCheckTile(
                      icon: Icons.groups_rounded,
                      title: 'Jogadores',
                      subtitle: 'Nomes e fotos vinculadas',
                      value: players,
                      onChanged: (value) => setDialogState(() => players = value ?? false),
                    ),
                    _BackupCheckTile(
                      icon: Icons.bar_chart_rounded,
                      title: 'Estatísticas de jogadores',
                      subtitle: 'Gols, vitórias, títulos e stats por temporada',
                      value: playerStats,
                      onChanged: (value) => setDialogState(() => playerStats = value ?? false),
                    ),
                    _BackupCheckTile(
                      icon: Icons.emoji_events_rounded,
                      title: 'Campeonatos',
                      subtitle: 'Chaves, times sorteados e campeões',
                      value: championships,
                      onChanged: (value) => setDialogState(() => championships = value ?? false),
                    ),
                    _BackupCheckTile(
                      icon: Icons.sports_soccer_rounded,
                      title: 'Partidas / jogos',
                      subtitle: 'Placar, gols, substituições e histórico de jogos',
                      value: matches,
                      onChanged: (value) => setDialogState(() => matches = value ?? false),
                    ),
                    _BackupCheckTile(
                      icon: Icons.calendar_month_rounded,
                      title: 'Temporadas',
                      subtitle: 'Temporadas criadas no app',
                      value: seasons,
                      onChanged: (value) => setDialogState(() => seasons = value ?? false),
                    ),
                    _BackupCheckTile(
                      icon: Icons.settings_rounded,
                      title: 'Configurações',
                      subtitle: 'Tempo de partida, limites e preferências',
                      value: settings,
                      onChanged: (value) => setDialogState(() => settings = value ?? false),
                    ),
                    _BackupCheckTile(
                      icon: Icons.photo_library_rounded,
                      title: 'Fotos / imagens',
                      subtitle: 'Fotos de jogadores e imagens salvas pelo app',
                      value: images,
                      onChanged: (value) => setDialogState(() => images = value ?? false),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: canImport
                    ? () => Navigator.pop(
                          context,
                          BackupImportOptions(
                            players: players,
                            playerStats: playerStats,
                            championships: championships,
                            matches: matches,
                            seasons: seasons,
                            settings: settings,
                            images: images,
                            overwrite: overwrite,
                          ),
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.background,
                ),
                child: const Text('Importar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _newSeason() async {
    final ctrl = TextEditingController(text: 'Temporada ${DateTime.now().year}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Nova Temporada', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(labelText: 'Nome da temporada'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Criar')),
        ],
      ),
    );

    if (ok != true) return;

    for (final s in _seasons) {
      if (s.isActive) {
        s.isActive = false;
        await _seasonRepo.save(s);
      }
    }

    final season = Season(
      id: _uuid.v4(),
      name: ctrl.text.trim(),
      year: DateTime.now().year,
    );
    await _seasonRepo.save(season);
    _settings = _settings.copyWith(activeSeasonId: season.id);
    await _settingsRepo.save(_settings);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Opções',
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Salvar', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionTitle(title: '⚽ Configurações de Jogo'),
                _SettingCard(
                  children: [
                    _SliderRow(
                      label: 'Jogadores por time',
                      value: _settings.teamSize.toDouble(),
                      min: 2,
                      max: 7,
                      divisions: 5,
                      format: (v) => '${v.toInt()}',
                      onChanged: (v) => setState(() => _settings = _settings.copyWith(teamSize: v.toInt())),
                    ),
                    const Divider(color: AppColors.surfaceLight, height: 24),
                    _SliderRow(
                      label: 'Tempo de partida',
                      value: _settings.matchDurationSeconds.toDouble(),
                      min: 60,
                      max: 1800,
                      divisions: 29,
                      format: (v) {
                        final m = v.toInt() ~/ 60;
                        final s = v.toInt() % 60;
                        return s == 0 ? '${m}min' : '${m}m${s}s';
                      },
                      onChanged: (v) => setState(() => _settings = _settings.copyWith(matchDurationSeconds: v.toInt())),
                    ),
                    const Divider(color: AppColors.surfaceLight, height: 24),
                    _SliderRow(
                      label: 'Atraso inicial (segundos)',
                      value: _settings.startDelaySeconds.toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      format: (v) => '${v.toInt()}s',
                      onChanged: (v) => setState(() => _settings = _settings.copyWith(startDelaySeconds: v.toInt())),
                    ),
                    const Divider(color: AppColors.surfaceLight, height: 24),
                    _SliderRow(
                      label: 'Limite de gols',
                      value: _settings.goalLimit.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      format: (v) => '${v.toInt()}',
                      onChanged: (v) => setState(() => _settings = _settings.copyWith(goalLimit: v.toInt())),
                    ),
                    const Divider(color: AppColors.surfaceLight, height: 24),
                    _SliderRow(
                      label: 'Limite de gols na final',
                      value: _settings.finalGoalLimit.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      format: (v) => '${v.toInt()}',
                      onChanged: (v) => setState(() => _settings = _settings.copyWith(finalGoalLimit: v.toInt())),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                _SectionTitle(title: '🎛️ Preferências'),
                _SettingCard(
                  children: [
                    _SwitchRow(
                      label: 'Exibir tempo dos gols',
                      subtitle: 'Mostra o minuto de cada gol',
                      value: _settings.showGoalTime,
                      onChanged: (v) => setState(() => _settings = _settings.copyWith(showGoalTime: v)),
                    ),
                    const Divider(color: AppColors.surfaceLight, height: 24),
                    _DropdownRow<DuoRankingMode>(
                      label: 'Ranking de melhores duplas',
                      subtitle: 'Escolha como a dupla será pontuada',
                      value: _settings.duoRankingMode,
                      items: const [
                        DropdownMenuItem(
                          value: DuoRankingMode.sharedGoals,
                          child: Text('Gols juntos'),
                        ),
                        DropdownMenuItem(
                          value: DuoRankingMode.titlesWins,
                          child: Text('Títulos e vitórias'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _settings = _settings.copyWith(duoRankingMode: v));
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                _SectionTitle(title: '💾 Backup'),
                _SettingCard(
                  children: [
                    _ActionRow(
                      icon: Icons.save_alt_rounded,
                      label: 'Exportar backup',
                      subtitle: 'Escolha onde salvar o arquivo .zip',
                      color: AppColors.win,
                      loading: _saving,
                      onTap: _exportBackup,
                    ),
                    const Divider(color: AppColors.surfaceLight, height: 16),
                    _ActionRow(
                      icon: Icons.ios_share_rounded,
                      label: 'Compartilhar backup',
                      subtitle: 'Enviar para Drive, WhatsApp ou outro app',
                      color: AppColors.win,
                      loading: _saving,
                      onTap: _shareBackup,
                    ),
                    const Divider(color: AppColors.surfaceLight, height: 16),
                    _ActionRow(
                      icon: Icons.download_rounded,
                      label: 'Importar backup',
                      subtitle: 'Escolha quais dados e imagens restaurar',
                      color: AppColors.win,
                      loading: _saving,
                      onTap: _importBackup,
                    ),
                    const Divider(color: AppColors.surfaceLight, height: 16),
                    _ActionRow(
                      icon: Icons.cloud_download_rounded,
                      label: 'Importar online',
                      subtitle: 'Baixar backup da pasta configurada do Google Drive',
                      color: AppColors.draw,
                      loading: _saving,
                      onTap: _importOnlineBackup,
                    ),
                    const Divider(color: AppColors.surfaceLight, height: 16),
                    _ActionRow(
                      icon: Icons.cloud_upload_rounded,
                      label: 'Exportar online',
                      subtitle: 'Entrar com Google e enviar para a pasta configurada',
                      color: AppColors.draw,
                      loading: _saving,
                      onTap: _exportOnlineBackup,
                    ),
                    const Divider(color: AppColors.surfaceLight, height: 16),
                    _ActionRow(
                      icon: Icons.link_rounded,
                      label: 'Configurar Drive online',
                      subtitle: 'Alterar link da pasta e e-mail dono',
                      color: AppColors.draw,
                      loading: _saving,
                      onTap: _editGoogleDriveSettings,
                    ),
                  ],
                ),

                const SizedBox(height: 40),
                Center(
                  child: Text(
                    _version.isEmpty ? 'FIFATEC' : 'FIFATEC v$_version',
                    style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
    );
  }
}

// ─── Helpers ────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                format(value),
                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.surfaceLight,
            thumbColor: AppColors.accent,
            overlayColor: AppColors.accent.withOpacity(0.2),
            valueIndicatorColor: AppColors.primary,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.accent,
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.primary.withOpacity(0.4)
                  : AppColors.surfaceLight),
        ),
      ],
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  final String label, subtitle;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _DropdownRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surfaceLight),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.card,
              iconEnabledColor: AppColors.accent,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                  )
                : Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Tile de seleção de modo (radio visual)
// ─────────────────────────────────────────────────────────────────────────────
class _ModeRadioTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeRadioTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? AppColors.accent : AppColors.textSecondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Linha de preview de uma categoria do backup
// ─────────────────────────────────────────────────────────────────────────────
class _PreviewRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final List<String> names;
  final bool isBool;

  const _PreviewRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.names,
    this.isBool = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = count > 0;
    final countText = isBool
        ? (hasData ? 'Sim' : 'Não')
        : '$count ${count == 1 ? 'item' : 'itens'}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: hasData ? AppColors.accent.withOpacity(0.15) : AppColors.loss.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        countText,
                        style: TextStyle(
                          color: hasData ? AppColors.accent : AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (names.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    names.join(', ') + (count > names.length ? '…' : ''),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _BackupCheckTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _BackupCheckTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.trailing,
      activeColor: AppColors.accent,
      checkColor: AppColors.background,
      value: value,
      onChanged: onChanged,
      title: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 27, top: 2),
        child: Text(
          subtitle,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
        ),
      ),
    );
  }
}

class _SeasonRow extends StatelessWidget {
  final Season season;
  final bool isActive;

  const _SeasonRow({required this.season, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
            color: isActive ? AppColors.accent : AppColors.textHint,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              season.name,
              style: TextStyle(
                color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 14,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Ativa', style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}