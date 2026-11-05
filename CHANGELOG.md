## 0.2.2

- Android: `voices()` no longer comes back empty when it is the first thing
  asked of a new `Speak`. Google's engine reports itself started before it
  has loaded its voices; for up to three seconds after the start, an empty
  list is asked for again.
- iOS and macOS: the voice list is read off the main thread. While the
  system cannot answer (a device or simulator setting up its voices),
  `voices()` waits, but the app's UI no longer does.
- Text with `<`, `>` or `&` is said as written. On macOS, before iOS 27,
  and in browsers on macOS, the system read markup in plain text: from a
  `<` on, words were lost. On Android, a text starting with `<` could be
  read as SSML.
- No word progress is reported while paused. An engine may report words it
  has prepared but not yet played (the iOS simulator under load did); they
  are reported on `resume()`, in order, or dropped if the utterance is
  stopped or interrupted instead.

## 0.2.1

- CallKit is no longer linked (App Review rejects apps containing CallKit on
  the China storefront). It is loaded at run time on the first question
  about calls; `Speak(ios: IosSpeakOptions(callKit: false))` never loads
  it, and calls are then caught only by the session's interruption
  notification.

## 0.2.0

- Calls and other interruptions (Siri, alarms, another app taking the
  audio): what is being said ends as `SpeakOutcome.interrupted`, and an
  utterance asked for during a call ends as the new
  `SpeakOutcome.blocked`; nothing is replayed after the call. Only current
  evidence blocks, never a remembered interruption: iOS asks CallKit
  whether a call is going on and observes the session's interruption
  notifications (and their iOS 27 replacements); Android watches its audio
  focus and the audio mode.
- A claim refused for another reason (Android 15 in the background without
  a foreground service, an iOS session that cannot be activated) is no
  call: the text is spoken without it.
- `SpeakAudio.duringCalls`: `SpeakDuringCalls.skip` (the default) or
  `.speak`.
- Breaking: a `switch` over `SpeakOutcome` needs a `blocked` case.
- README: running in the background, per platform; the exact cause of the
  macOS failure under `flutter run`, and the debug-entitlement workaround.

## 0.1.3

- A clearer package description.

## 0.1.2

- The lead-in is played only when the audio goes to Bluetooth or a car
  (`SpeakAudio.leadInOnBluetoothOnly`, on by default): through the phone's
  speaker or wired headphones speech starts at once. The route is read right
  after the audio is claimed, on iOS from the audio session, on Android from
  where the speech's attributes route (Android 13+) or the connected
  Bluetooth outputs.
- Includes 0.1.1, which was tagged but never published: the README's guide
  for moving from flutter_tts, call by call.

## 0.1.1

- README: a guide for moving from flutter_tts, call by call.

## 0.1.0

- First release: text-to-speech on iOS, macOS, Android and the web.
- Awaitable utterances with an outcome (`completed`, `interrupted`,
  `expired`); queue or interrupt; `expireAfter`; `stop`.
- Voices with BCP-47 language, quality, network and install state; the best
  voice chosen for a language; `availability` for a language.
- Rate, pitch and volume, per call or as defaults.
- Word progress, pause and resume on every platform (Android resumes from
  the last reported word).
- Audio sharing per platform (`SpeakAudio`): iOS audio session and Android
  audio focus claimed right before speaking and given back after a short
  `linger`, or held with `holdAudio`. Modes `mix`, `duck`,
  `duckAndPauseSpoken` (`SpeakAudio.navigation`: music lowered, podcasts
  paused), `pauseSpoken` and `pause`.
- A silent `leadIn` before the first utterance after the audio is claimed,
  so Bluetooth headsets do not swallow the first syllable.
- Android engine choice (`Speak.androidEngines`, `AndroidSpeakOptions`).
- Per-utterance timeouts, and a `stop` that never waits on a silent engine.
