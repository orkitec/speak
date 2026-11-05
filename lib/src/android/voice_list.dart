// How long Android's engine is given to list its voices. Pure, so the rule
// is tested on the VM.
import 'package:clock/clock.dart';

/// How long after the engine starts its voice list may still be filling
/// in: Google's engine reports `onInit` before it has loaded its voices,
/// and for a while lists none, or some, or none installed. Measured on CI,
/// the first full list came 0.2 to 1.4 s after the start on API 31 and 34,
/// and after more than 3 s (but before a second speaker started seconds
/// later had it) on slower API 35 emulators, three to a runner; ten seconds
/// is three times the window that was too short. Only [listVoices] waits that long, once per speaker;
/// an utterance does not wait for the list (`voiceLookupWait`).
const voicesSettle = Duration(seconds: 10);

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

/// Whether the engine started at [startedAt] may still be loading its
/// voices: within [voicesSettle] of its start.
bool voicesLoading(DateTime startedAt) =>
    clock.now().isBefore(startedAt.add(voicesSettle));
