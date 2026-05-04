import 'package:intl/intl.dart';

class AppDateUtils {
  static String formatDate(DateTime dt) =>
      DateFormat('dd/MM/yyyy', 'pt_BR').format(dt);

  static String formatTime(DateTime dt) =>
      DateFormat('HH:mm', 'pt_BR').format(dt);

  static String formatDateTime(DateTime dt) =>
      DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(dt);

  static String formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return formatDate(dt);
    if (diff.inDays > 0) return 'há ${diff.inDays}d';
    if (diff.inHours > 0) return 'há ${diff.inHours}h';
    if (diff.inMinutes > 0) return 'há ${diff.inMinutes}min';
    return 'agora';
  }
}