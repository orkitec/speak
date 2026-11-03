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
  audio focus claimed only while speaking, or held with `holdAudio`.
- Android engine choice (`Speak.androidEngines`, `AndroidSpeakOptions`).
- Per-utterance timeouts, and a `stop` that never waits on a silent engine.
