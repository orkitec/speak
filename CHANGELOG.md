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
