import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/season.dart';
import '../../core/repositories/settings_repository.dart'
    show SettingsRepository, SeasonRepository;
import '../../core/services/backup_service.dart';
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
  final _uuid = const Uuid();

  AppSettings _settings = AppSettings();
  List<Season> _seasons = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
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
      await _backupService.shareBackup();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar: $e'), backgroundColor: AppColors.loss),
        );
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _importBackup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Importar backup?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Isso irá substituir todos os dados atuais. Deseja continuar?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.loss),
            child: const Text('Substituir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.single.path == null) return;

      setState(() => _saving = true);
      await _backupService.importBackup(result.files.single.path!);
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
      setState(() => _saving = false);
    }
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

    // Desativa temporadas antigas
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
                // ─── JOGO ───────────────────────────────────
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

                  ],
                ),

                const SizedBox(height: 20),
                _SectionTitle(title: '💾 Backup'),
                _SettingCard(
                  children: [
                    _ActionRow(
                      icon: Icons.upload_rounded,
                      label: 'Exportar backup',
                      subtitle: 'Salva todos os dados e imagens em .zip',
                      color: AppColors.win,
                      loading: _saving,
                      onTap: _exportBackup,
                    ),
                    const Divider(color: AppColors.surfaceLight, height: 16),
                    _ActionRow(
                      icon: Icons.download_rounded,
                      label: 'Importar backup',
                      subtitle: 'Restaura dados de um arquivo .zip',
                      color: AppColors.draw,
                      loading: _saving,
                      onTap: _importBackup,
                    ),
                  ],
                ),

                const SizedBox(height: 40),
                Center(
                  child: Text(
                    'FIFATEC v1.0.0',
                    style: TextStyle(color: AppColors.textHint, fontSize: 12),
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
