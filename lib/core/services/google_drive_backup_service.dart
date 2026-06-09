import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_service.dart';

class GoogleDriveBackupFile {
  final String id;
  final String name;
  final DateTime? modifiedTime;
  final int? sizeBytes;

  const GoogleDriveBackupFile({
    required this.id,
    required this.name,
    this.modifiedTime,
    this.sizeBytes,
  });

  factory GoogleDriveBackupFile.fromJson(Map<String, dynamic> json) {
    return GoogleDriveBackupFile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'backup.zip',
      modifiedTime: DateTime.tryParse(json['modifiedTime']?.toString() ?? ''),
      sizeBytes: int.tryParse(json['size']?.toString() ?? ''),
    );
  }
}

class GoogleDriveUploadResult {
  final String id;
  final String name;
  final String? webViewLink;

  const GoogleDriveUploadResult({
    required this.id,
    required this.name,
    this.webViewLink,
  });

  factory GoogleDriveUploadResult.fromJson(Map<String, dynamic> json) {
    return GoogleDriveUploadResult(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      webViewLink: json['webViewLink']?.toString(),
    );
  }
}

class GoogleDriveBackupService {
  GoogleDriveBackupService({BackupService? backupService})
      : _backupService = backupService ?? BackupService();

  /// Configure sua API Key assim:
  /// flutter run --dart-define=GOOGLE_DRIVE_API_KEY=SUA_API_KEY
  /// flutter build apk --dart-define=GOOGLE_DRIVE_API_KEY=SUA_API_KEY
  static const String _apiKey = String.fromEnvironment('GOOGLE_DRIVE_API_KEY');

  /// Obrigatório no Android quando o projeto não usa google-services.json
  /// com um OAuth Client Web configurado.
  ///
  /// Valor esperado: Client ID do tipo Web Application, exemplo:
  /// 1234567890-abc.apps.googleusercontent.com
  static const String _serverClientId =
      String.fromEnvironment('GOOGLE_DRIVE_SERVER_CLIENT_ID');

  /// Use estes 2 valores se sua API Key estiver restrita para Android.
  /// Isso evita o erro: Requests from this Android client application <empty> are blocked.
  static const String _androidPackageName =
      String.fromEnvironment('GOOGLE_DRIVE_ANDROID_PACKAGE_NAME');
  static const String _androidCertSha1 =
      String.fromEnvironment('GOOGLE_DRIVE_ANDROID_CERT_SHA1');

  static const List<String> _driveScopes = <String>[
    'email',
    'profile',
    'https://www.googleapis.com/auth/drive.file',
  ];

  final BackupService _backupService;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _initialized = false;

  Future<List<GoogleDriveBackupFile>> listOnlineBackups(String folderLink) async {
    if (_apiKey.trim().isEmpty) {
      throw Exception(
        'API Key do Google Drive não configurada. Use --dart-define=GOOGLE_DRIVE_API_KEY=SUA_API_KEY.',
      );
    }

    final folderId = extractFolderId(folderLink);
    final query = "'$folderId' in parents and trashed = false and mimeType = 'application/zip'";

    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files',
      {
        'q': query,
        'fields': 'files(id,name,modifiedTime,size)',
        'orderBy': 'modifiedTime desc',
        'pageSize': '20',
      },
    );

    final response = await http.get(uri, headers: _apiKeyHeaders());
    if (response.statusCode != 200) {
      throw Exception(_friendlyGoogleError(response, 'Erro ao listar backups online'));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files = (data['files'] as List? ?? [])
        .whereType<Map>()
        .map((item) => GoogleDriveBackupFile.fromJson(Map<String, dynamic>.from(item)))
        .where((file) => file.id.isNotEmpty && file.name.toLowerCase().endsWith('.zip'))
        .toList();

    return files;
  }

  Future<File> downloadOnlineBackup(GoogleDriveBackupFile file) async {
    if (_apiKey.trim().isEmpty) {
      throw Exception(
        'API Key do Google Drive não configurada. Use --dart-define=GOOGLE_DRIVE_API_KEY=SUA_API_KEY.',
      );
    }

    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files/${file.id}',
      {
        'alt': 'media',
      },
    );

    final response = await http.get(uri, headers: _apiKeyHeaders());
    if (response.statusCode != 200) {
      throw Exception(_friendlyGoogleError(response, 'Erro ao baixar backup online'));
    }

    final tempDir = await getTemporaryDirectory();
    final safeName = _sanitizeFileName(file.name.isEmpty ? 'fifatec_backup_online.zip' : file.name);
    final output = File(p.join(tempDir.path, safeName));
    await output.writeAsBytes(response.bodyBytes, flush: true);
    return output;
  }

  Future<GoogleDriveUploadResult> exportOnlineBackup({
    required String folderLink,
    required String ownerEmail,
  }) async {
    final folderId = extractFolderId(folderLink);
    final account = await _authenticate();

    final expectedOwner = ownerEmail.trim().toLowerCase();
    if (expectedOwner.isNotEmpty && account.email.trim().toLowerCase() != expectedOwner) {
      throw Exception(
        'Esta conta não pode exportar online. Entre com a conta dona configurada: $ownerEmail.',
      );
    }

    final token = await _getAccessToken(account);
    final backupFile = await _backupService.exportBackup();
    final fileBytes = await backupFile.readAsBytes();
    final fileName = p.basename(backupFile.path);

    final metadata = <String, dynamic>{
      'name': fileName,
      'parents': [folderId],
      'mimeType': 'application/zip',
    };

    final boundary = 'fifatec_${DateTime.now().microsecondsSinceEpoch}';
    final body = <int>[
      ...utf8.encode('--$boundary\r\n'),
      ...utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'),
      ...utf8.encode(jsonEncode(metadata)),
      ...utf8.encode('\r\n--$boundary\r\n'),
      ...utf8.encode('Content-Type: application/zip\r\n\r\n'),
      ...fileBytes,
      ...utf8.encode('\r\n--$boundary--'),
    ];

    final uri = Uri.https(
      'www.googleapis.com',
      '/upload/drive/v3/files',
      {
        'uploadType': 'multipart',
        'fields': 'id,name,webViewLink',
      },
    );

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_friendlyGoogleError(response, 'Erro ao enviar backup para o Drive'));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return GoogleDriveUploadResult.fromJson(data);
  }

  String extractFolderId(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      throw Exception('Link da pasta do Google Drive está vazio.');
    }

    final folderMatch = RegExp(r'/folders/([a-zA-Z0-9_-]+)').firstMatch(text);
    if (folderMatch != null) return folderMatch.group(1)!;

    final idMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(text);
    if (idMatch != null) return idMatch.group(1)!;

    final rawIdMatch = RegExp(r'^[a-zA-Z0-9_-]{20,}$').firstMatch(text);
    if (rawIdMatch != null) return text;

    throw Exception('Link da pasta do Google Drive inválido.');
  }

  Future<void> _initializeGoogleSignIn() async {
    if (_initialized) return;

    final serverClientId = _serverClientId.trim();
    if (Platform.isAndroid && serverClientId.isEmpty) {
      throw Exception(
        'Client ID Web do Google não configurado. Gere um OAuth Client do tipo Web Application no Google Cloud e rode o app com --dart-define=GOOGLE_DRIVE_SERVER_CLIENT_ID=SEU_CLIENT_ID_WEB.apps.googleusercontent.com.',
      );
    }

    await _googleSignIn.initialize(
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    _initialized = true;
  }

  Future<GoogleSignInAccount> _authenticate() async {
    await _initializeGoogleSignIn();

    try {
      final lightweightFuture = _googleSignIn.attemptLightweightAuthentication();
      if (lightweightFuture != null) {
        final lightweightAccount = await lightweightFuture;
        if (lightweightAccount != null) return lightweightAccount;
      }
    } catch (_) {
      // Se o login leve falhar, abrimos o seletor normal.
    }

    if (!_googleSignIn.supportsAuthenticate()) {
      throw Exception('Login Google por botão personalizado não está disponível nesta plataforma.');
    }

    return _googleSignIn.authenticate(scopeHint: _driveScopes);
  }

  Future<String> _getAccessToken(GoogleSignInAccount account) async {
    GoogleSignInClientAuthorization? authorization =
        await account.authorizationClient.authorizationForScopes(_driveScopes);

    authorization ??= await account.authorizationClient.authorizeScopes(_driveScopes);

    final token = authorization.accessToken;
    if (token.isEmpty) {
      throw Exception('Não foi possível obter autorização para acessar o Google Drive.');
    }

    return token;
  }


  Map<String, String> _apiKeyHeaders() {
    final headers = <String, String>{
      'x-goog-api-key': _apiKey.trim(),
    };

    final packageName = _androidPackageName.trim();
    final certSha1 = _normalizeSha1(_androidCertSha1);

    if (packageName.isNotEmpty && certSha1.isNotEmpty) {
      headers['X-Android-Package'] = packageName;
      headers['X-Android-Cert'] = certSha1;
    }

    return headers;
  }

  String _normalizeSha1(String value) {
    return value.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toUpperCase();
  }

  String _sanitizeFileName(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
  }

  String _friendlyGoogleError(http.Response response, String prefix) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final error = data['error'];
      if (error is Map) {
        final message = error['message']?.toString();
        if (message != null && message.trim().isNotEmpty) {
          return '$prefix (${response.statusCode}): $message';
        }
      }
    } catch (_) {}

    return '$prefix (${response.statusCode}).';
  }
}
