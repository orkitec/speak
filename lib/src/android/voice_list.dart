// How long Android's engine is given to list its voices. Pure, so the rule
// is tested on the VM.
import 'package:clock/clock.dart';

/// How long after the engine starts its voice list may still be filling
/// in: Google's engine reports `onInit` before it has loaded its voices,
/// and for a moment lists none, or some, or none installed (seen on the
/// API 31 Google APIs image).
const voicesSettle = Duration(seconds: 3);

/// How often the voice list is looked at again meanwhile.
const voicesPoll = Duration(milliseconds: 200);

/// The engine's voices from [list]. Until [voicesSettle] after [startedAt]
/// they are taken only once they hold an [installed] one and two looks
/// [voicesPoll] apart agree; after that, whatever the engine lists, which
/// may be nothing.
Future<List<T>> listVoices<T>(
  List<T>? Function() list, {
  required DateTime startedAt,
  required bool Function(T voice) installed,
}) async {
  final until = startedAt.add(voicesSettle);
  (int, int)? before;
  while (true) {
    final voices = list() ?? [];
    if (!clock.now().isBefore(until)) return voices;
    final now = (voices.length, voices.where(installed).length);
    if (now.$2 > 0 && now == before) return voices;
    before = now;
    await Future<void>.delayed(voicesPoll);
  }
}
