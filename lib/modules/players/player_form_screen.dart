import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/player.dart';
import '../../core/repositories/player_repository.dart';
import '../../core/services/image_service.dart';
import '../../shared/widgets/custom_app_bar.dart';
import '../../shared/widgets/player_avatar.dart';

class PlayerFormScreen extends StatefulWidget {
  final String? editPlayerId;
  const PlayerFormScreen({super.key, this.editPlayerId});

  @override
  State<PlayerFormScreen> createState() => _PlayerFormScreenState();
}

class _PlayerFormScreenState extends State<PlayerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _repo = PlayerRepository();
  final _imgService = ImageService();
  final _uuid = const Uuid();

  String? _photoPath;
  bool _loading = false;
  Player? _editPlayer;

  bool get isEditing => widget.editPlayerId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) _loadPlayer();
  }

  Future<void> _loadPlayer() async {
    _editPlayer = await _repo.getById(widget.editPlayerId!);
    if (_editPlayer != null) {
      _nameCtrl.text = _editPlayer!.name;
      _descCtrl.text = _editPlayer!.description ?? '';
      setState(() => _photoPath = _editPlayer!.photoPath);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);
    String? path;
    if (source == ImageSource.gallery) {
      path = await _imgService.pickFromGallery(context: context);
    } else {
      path = await _imgService.pickFromCamera(context: context);
    }
    if (path != null && mounted) setState(() => _photoPath = path);
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppColors.textHint, borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.accent),
              title: const Text('Galeria', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.accent),
              title: const Text('Câmera', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => _pickImage(ImageSource.camera),
            ),
            if (_photoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_rounded, color: AppColors.loss),
                title: const Text('Remover foto', style: TextStyle(color: AppColors.loss)),
                onTap: () {
                  setState(() => _photoPath = null);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      if (isEditing && _editPlayer != null) {
        final updated = _editPlayer!.copyWith(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          photoPath: _photoPath,
        );
        await _repo.update(updated);
      } else {
        final player = Player(
          id: _uuid.v4(),
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          photoPath: _photoPath,
        );
        await _repo.save(player);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: AppColors.loss),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(title: isEditing ? 'Editar Jogador' : 'Novo Jogador'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Avatar
              GestureDetector(
                onTap: _showImagePicker,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 3),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(55),
                        child: _photoPath != null && File(_photoPath!).existsSync()
                            ? Image.file(File(_photoPath!), fit: BoxFit.cover)
                            : PlayerAvatar(
                                name: _nameCtrl.text.isEmpty ? '?' : _nameCtrl.text,
                                size: 110,
                              ),
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Toque para adicionar foto',
                style: TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
              const SizedBox(height: 28),

              // Nome
              TextFormField(
                controller: _nameCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome *',
                  prefixIcon: Icon(Icons.person_rounded, color: AppColors.textHint),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nome obrigatório';
                  if (v.trim().length < 2) return 'Nome muito curto';
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              // Descrição
              TextFormField(
                controller: _descCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descrição (opcional)',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 48),
                    child: Icon(Icons.notes_rounded, color: AppColors.textHint),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          isEditing ? 'Salvar Alterações' : 'Adicionar Jogador',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    _descCtrl.dispose();
    super.dispose();
  }
}