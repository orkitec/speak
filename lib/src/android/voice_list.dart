// How long Android's engine is given to list its voices. Pure, so the rule
// is tested on the VM.
import 'package:clock/clock.dart';

/// How long after the engine starts an empty voice list is asked for again:
/// Google's engine reports `onInit` before it has loaded its voices, and
/// lists none (or `null`) for a moment after.
const voicesSettle = Duration(seconds: 3);

/// How often an empty voice list is asked for again meanwhile.
const voicesPoll = Duration(milliseconds: 200);

/// The engine's voices from [list], asked for again every [voicesPoll] while
/// it lists none, until [voicesSettle] after [startedAt]; then whatever it
/// lists, which may be nothing.
Future<List<T>> listVoices<T>(
  List<T>? Function() list, {
  required DateTime startedAt,
}) async {
  final until = startedAt.add(voicesSettle);
  while (true) {
    final voices = list();
    if (voices != null && voices.isNotEmpty) return voices;
    if (!clock.now().isBefore(until)) return voices ?? [];
    await Future<void>.delayed(voicesPoll);
  }
}
