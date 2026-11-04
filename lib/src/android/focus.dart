// What an Android audio focus request means for speaking. Pure, so the
// rule is tested on the VM.
import '../backend/backend.dart';

/// The claim for a focus request that was [granted] or not, while a call is
/// going on ([inCall]) or our focus is still [taken] by a transient loss.
///
/// Only positive evidence refuses: a call, or the focus still with the app
/// that took it. A refusal without either is Android 15 turning down an app
/// in the background without a foreground service; then the speech goes
/// out without focus, as with `OtherAudio.mix`, rather than not at all.
AudioClaim focusClaim({
  required bool granted,
  required bool inCall,
  required bool taken,
}) {
  if (taken) return AudioClaim.refused;
  if (granted) return AudioClaim.granted;
  return inCall ? AudioClaim.refused : AudioClaim.unclaimed;
}
