import 'action_result.dart';
import 'intent.dart';

/// Test/bağlantı ekranlarında gösterilen, işlenmiş bir komutun geçmiş kaydı.
class LogEntry {
  final DateTime time;
  final PatikaIntent intent;
  final String? entity;
  final ActionResult result;

  LogEntry({
    required this.time,
    required this.intent,
    required this.entity,
    required this.result,
  });
}
