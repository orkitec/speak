# speak

Text-to-speech for Flutter on iOS, macOS, Android and the web, made for short
spoken prompts over other audio: turn-by-turn directions, workout cues, timers.

```dart
final speak = Speak(audio: SpeakAudio.navigation);

await speak('In two hundred metres, turn left.');
await speak('Turn left now.', queue: SpeakQueue.interrupt);
```

- **Awaitable.** Every call completes when the text has been spoken, or tells
  you how it ended instead: `completed`, `interrupted` or `expired`.
- **Queue or interrupt.** Utterances wait their turn by default. An urgent one
  cuts in, and the ones it displaces complete as `interrupted`. A
  distance announcement that waited too long can expire unsaid.
- **Plays well with other audio.** Music is lowered (and podcasts paused)
  only while something is spoken, and comes back afterwards: iOS's audio
  session and Android's audio focus are claimed right before speaking and
  released shortly after. A short silent lead-in keeps Bluetooth headsets
  from eating the first syllable.
- **Voices.** List them with their language (BCP-47) and quality, pick one or
  let `speak` pick the best for a language, and check whether a language
  can be spoken before you try.
- **Word progress, pause and resume** on every platform.
- **No native code to write or set up**: no Podfile, no Swift package, no
  Kotlin. iOS and macOS call AVFoundation from Dart through FFI, Android calls
  `TextToSpeech` through JNI, the web uses the Web Speech API. See
  [How it works](#how-it-works) for what is compiled for you.

| Platform | Support |
| --- | --- |
| iOS 13+ | AVSpeechSynthesizer, AVAudioSession |
| macOS 10.15+ | AVSpeechSynthesizer |
| Android 7+ (API 24) | TextToSpeech, audio focus |
| Web | Web Speech API, also compiled to Wasm |
| Windows, Linux | Not supported: `Speak.isSupported` is `false` |

## Install

```sh
flutter pub add speak
```

This needs Flutter 3.38 or later, the first release where build hooks run
for you.

- **iOS**: to keep speaking with the screen locked, add the `audio`
  background mode to `Info.plist`:
  ```xml
  <key>UIBackgroundModes</key>
  <array><string>audio</string></array>
  ```
- **Android**: nothing to add. The `TTS_SERVICE` query that Android 11+ needs
  to see the installed engines is merged into your manifest from the package.
- **macOS** and **web**: nothing to add.

## Usage

### Speak and wait

```dart
final speak = Speak();

final outcome = await speak('Your timer is done.');
// SpeakOutcome.completed, or .interrupted if stop() or an interrupting
// utterance cut it off.
```

A `Speak` is one speaker. Create it once for the feature that talks, and
`dispose()` it when that feature goes away.

### Queue, interrupt, expire

```dart
speak('In 500 metres, turn right.');            // waits its turn
speak('In 200 metres, turn right.',
    expireAfter: const Duration(seconds: 6));    // dropped if still waiting
speak('Turn right now.', queue: SpeakQueue.interrupt); // cuts in

await speak.stop(); // everything ends as interrupted
```

### Voices and languages

```dart
final german = await speak.voices(language: 'de'); // best first
await speak('Links abbiegen.', voice: german.first);

// Or let speak choose the best installed voice for a language:
await speak('Tournez à gauche.', language: 'fr-FR');

// Defaults for every call:
speak
  ..language = 'en-GB'
  ..rate = 1.1; // 1 is normal speed
```

A `Voice` has an `id` (store this to remember a choice), a `name`, a
`language`, a `quality` (`low` to `premium`), `requiresNetwork` and
`isInstalled`. When `speak` chooses for a language, it prefers the asked
region, voices that work offline, and better quality, in that order.

### Is a language available?

```dart
switch (await speak.availability('de-DE')) {
  case VoiceAvailability.available:
    break;
  case VoiceAvailability.needsNetwork:
    // Only an online voice speaks it.
  case VoiceAvailability.notInstalled:
    // Android: the voice data has to be downloaded in the system settings.
  case VoiceAvailability.unsupported:
    // No voice for it at all.
}
```

Speaking a language no installed voice speaks fails with
`SpeakException(SpeakError.languageUnavailable)`.

### Word progress

```dart
await speak(
  text,
  onProgress: (progress) => setState(() => highlighted = progress),
);
// progress.start, progress.end: offsets into text; progress.word
```

### Pause and resume

```dart
await speak.pause();
await speak.resume();
```

### Sharing audio with other apps

```dart
final guidance = Speak(audio: SpeakAudio.navigation);

final custom = Speak(
  audio: const SpeakAudio(
    otherAudio: OtherAudio.pauseSpoken, // music plays on, podcasts pause
    usage: AudioUsage.navigation,
    leadIn: Duration(milliseconds: 500),
    linger: Duration(seconds: 2),
  ),
);
```

The audio is claimed right before speaking and given back shortly after, as
navigation apps do: on iOS the session is activated (category first, then
`setActive(true)`) and later deactivated with `notifyOthersOnDeactivation`,
so other apps raise their volume or resume; on Android transient audio
focus is requested and then abandoned. Nothing is held while the app is
quiet, which is also what costs the least battery.

#### What happens to music and podcasts

| `OtherAudio` | iOS: music | iOS: podcasts, audiobooks | Android (music and podcasts alike) |
| --- | --- | --- | --- |
| `mix` | plays on at full volume | plays on | no audio focus: plays on |
| `duck` (`SpeakAudio.prompt`, the default) | lowered | lowered | lowered (`AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`) |
| `duckAndPauseSpoken` (`SpeakAudio.navigation`) | lowered | paused, resumed after | lowered; see below |
| `pauseSpoken` | plays on at full volume | paused, resumed after | lowered; see below |
| `pause` (`SpeakAudio.exclusive`) | paused, resumed after | paused, resumed after | paused, resumed after (`AUDIOFOCUS_GAIN_TRANSIENT`) |

On iOS the options are `mixWithOthers`, plus `duckOthers` for the modes that
lower, plus `interruptSpokenAudioAndMixWithOthers` for those that pause
spoken audio; `pause` sets no mixing option. Android has no "spoken audio"
category to pause: an app can only ask for focus that may duck. A podcast
player that prefers pausing to being lowered pauses itself
(`setWillPauseWhenDucked`), and nothing can make another app do so; the
rest are lowered. On macOS other apps are never affected. A web page cannot
touch other audio at all.

| `AudioUsage` | iOS mode | Android usage |
| --- | --- | --- |
| `navigation` | `voicePrompt` | `USAGE_ASSISTANCE_NAVIGATION_GUIDANCE` |
| `prompt` (default) | `voicePrompt` | `USAGE_ASSISTANT` |
| `spokenContent` | `spokenAudio` | `USAGE_MEDIA` |

On iOS speech uses the `playback` category, so it is heard with the
Ring/Silent switch on silent. On Android the attributes are always
`CONTENT_TYPE_SPEECH`.

#### Lead-in and linger: Bluetooth without lost syllables

A Bluetooth headset or car stereo mutes its stream while nothing plays and
takes a moment to open it again, so speech that starts at once loses its
first syllables. `leadIn` (350 ms by default) plays silence first, but
only where it helps, and only before the first utterance after the audio
is claimed.

Where: with `leadInOnBluetoothOnly` (on by default), only when the audio
goes to Bluetooth or a car. Right after claiming the audio, `speak` reads
the route:

| | Lead-in when the output is |
| --- | --- |
| iOS | Bluetooth A2DP, HFP or LE, or car audio (CarPlay) in the session's current route |
| Android 13+ | Bluetooth A2DP, SCO, LE headset or speaker, or a hearing aid, among the devices the speech's audio attributes route to |
| Android 7 to 12 | any such output connected (there is no asking where a stream would go) |
| macOS | never: there is no session to ask, so it counts as no Bluetooth |
| Web | never: there is no lead-in |

Through the phone's speaker or wired headphones speech starts at once.
Set `leadInOnBluetoothOnly: false` to play the lead-in everywhere. If the
route cannot be read, the lead-in is played: a short wait is better than a
lost word.

When: only before the first utterance after the audio is claimed: utterances
queued behind it, or arriving within `linger`, follow straight on. `linger`
(1.5 s by default) keeps the audio claimed after the last utterance, so
prompts close together are not each preceded by a lead-in, and music is not
raised and lowered again in between. `stop()`, `pause()` and `dispose()`
give the audio back at once. On iOS and macOS the lead-in is real silent
samples played through the session; on Android it is
`playSilentUtterance`; the web has none. It is not counted against an
utterance's timeout.

This is the recommended setup for navigation: the radio path is only open
while speaking, plus a second and a half.

#### Holding the audio

`await speak.holdAudio()` claims the audio at once and keeps it until
`releaseAudio()`, however long the gaps. It costs battery: the audio path,
and on Bluetooth the A2DP stream, stays active the whole time, and other
audio stays lowered or paused the whole time. Use it only for a short
stretch of continuous prompts; the lead-in and a short linger cover the
rest.

### Android: choose the engine

```dart
final engines = await Speak.androidEngines(); // the user's default first
final speak = Speak(android: AndroidSpeakOptions(engine: engines.last.name));
```

`Speak.androidEngines()` returns an empty list on every other platform.

### Errors

Interruptions are outcomes, not errors. Failures complete the call with a
`SpeakException` whose `error` says what went wrong:
`languageUnavailable`, `voiceUnavailable`, `engineUnavailable`, `notAllowed`
(web, see below), `timeout` or `synthesisFailed`. A failed utterance never
blocks the ones queued after it. On Windows and Linux every call throws
`UnsupportedError`.

## Coming from flutter_tts

Most calls map one to one. The main difference: every `speak(...)` is
awaitable and tells you how it ended, so the completion, cancel and error
handlers go away.

| flutter_tts | speak |
| --- | --- |
| `final tts = FlutterTts();` | `final speak = Speak();` |
| `await tts.awaitSpeakCompletion(true);` then `await tts.speak(text)` | `await speak(text)`, which returns a `SpeakOutcome` |
| `setCompletionHandler`, `setCancelHandler` | the outcome: `completed`, `interrupted`, `expired` |
| `setErrorHandler` | `try` / `on SpeakException catch (e)`, with `e.error` |
| `setQueueMode(1)` / the default flush | `queue: SpeakQueue.append` (the default) / `SpeakQueue.interrupt` |
| `stop()`, `pause()` | `stop()`, `pause()` and `resume()` (also on Android) |
| `setLanguage('de-DE')` | `speak.language = 'de-DE'`, or `language:` per call |
| `getVoices` (a list of maps) | `voices({language})`, a `List<Voice>`, best first |
| `setVoice({'name': ..., 'locale': ...})` | `speak.voice = voice`, or `voice:` per call |
| `isLanguageAvailable`, `isLanguageInstalled` | `availability(language)` |
| `setSpeechRate`, `setPitch`, `setVolume` | `rate`, `pitch`, `volume`, as defaults or per call |
| `setProgressHandler` | `onProgress:` per call |
| `setIosAudioCategory`, `setSharedInstance`, `autoStopSharedSession`, `setAudioAttributesForNavigation` | `Speak(audio: SpeakAudio.navigation)`, or another `SpeakAudio` |
| `getEngines`, `setEngine` (Android) | `Speak.androidEngines()`, `Speak(android: AndroidSpeakOptions(engine: ...))` |
| `synthesizeToFile`, Windows | not supported |

Two things to watch when switching:

- **Rate.** flutter_tts passes each platform's own scale through (on iOS,
  0.5 is normal speed). In speak, 1 is normal on every platform, so an iOS
  rate of 0.5 becomes 1.
- **Audio session.** Remove any code of your own that activates or
  deactivates the iOS audio session around speech: speak claims it right
  before speaking and gives it back afterwards.

## Platform differences

| | iOS / macOS | Android | Web |
| --- | --- | --- | --- |
| Word progress | every word | `onRangeStart`: Android 8+, and only from engines that report it | `boundary` events where the browser sends them; when a browser gives only where a word starts, `speak` finds its end |
| Pause | native, at the end of a word | stops, and resumes from the start of the last word reported (from the beginning when none was) | native; in Chrome on Android `pause()` acts as a stop |
| Voice quality | compact = `normal`, enhanced, premium; novelty and Eloquence voices are `low` | from the engine's quality grade | `unknown` |
| Online voices | none | `requiresNetwork` from the engine | `requiresNetwork` for non-local voices |
| Voices not installed | not listed | listed, `isInstalled: false` | not listed |
| Gender | reported | `unknown` | `unknown` |
| Other audio | lowered/paused (iOS); macOS has no session | lowered/paused through audio focus (API 26+ with attributes, older with the music stream) | not possible |
| Lead-in (on Bluetooth by default) | silent samples through the session; on macOS only with `leadInOnBluetoothOnly: false` | `playSilentUtterance` | none |

`rate` is relative everywhere: 1 is the platform's normal speed. On iOS and
macOS it scales AVFoundation's default utterance rate, capped at its maximum
(about twice the normal speed).

## Known issues

- **macOS under `flutter run` / `flutter test`.** When the app is started as
  a child of the flutter tool, AVSpeechSynthesizer cannot load its speech
  audio unit (OSStatus -3000, `invalidComponentID`), and every utterance ends
  at once as `SpeakException(synthesisFailed)`. Started normally (from the
  Finder, or with `open`), the same app speaks. To run the integration
  tests on macOS, use `tool/macos_integration_test.sh`, which builds the test
  app and starts it with `open`.
- **Web: a user gesture first.** Browsers refuse to speak until the user has
  interacted with the page. Before that, a call fails with
  `SpeakError.notAllowed`.
- **Web: word progress depends on the browser's voice.** `onProgress` is
  only called for the `boundary` events the browser sends. Chrome on Linux
  sends none, so there the callback is never called (the text is still
  spoken, and pause still works).
- **Web: Chrome's online voices may stop after about 15 seconds** of
  continuous speech. Short prompts are not affected; split long text into
  sentences.
- **iOS Simulator** has only compact voices installed.

## How it works

There is no plugin code of the usual kind: no method channel and no Swift,
Kotlin or Objective-C to maintain. What does ship natively:

- **iOS and macOS**: the Dart bindings to AVFAudio are generated by `ffigen`.
  For the synthesizer's delegate, `ffigen` also generates a small
  Objective-C trampoline file (`darwin/av_bindings.m`). A build hook
  (`hook/build.dart`) compiles it for you during the app's build, as
  `package:objective_c` does for its own glue.
- **Android**: the bindings to `TextToSpeech` and `AudioManager` are generated
  by `jnigen`. One hand-written Java file
  (`android/src/main/java/com/orkitec/speak/SpeakPlugin.java`) subclasses
  `UtteranceProgressListener`. Dart can implement Java interfaces but not
  extend abstract classes, so this class forwards each callback to an
  interface that Dart implements. Gradle compiles it with your app.
- **Web**: `package:web`, behind conditional imports, so `dart:ffi` and JNI
  never reach a web build.

### Design notes

- **`Speak` is an instance, not a static API.** A speaker owns state: its
  queue, its engine (on Android, a bound `TextToSpeech` service, possibly a
  non-default engine), its audio configuration and its defaults. Two
  features can each have their own speaker. Facts about the platform, which
  are the same for every speaker, are static: `Speak.isSupported` and
  `Speak.androidEngines()`.
- **Calling the speaker speaks.** `speak('text')` reads as what it does, and
  everything else is a named method on the same object.
- **Outcomes are values, failures are exceptions.** Being cut off by `stop()`
  or by an urgent prompt is normal flow in a navigation app, and should not
  need a `try`. An engine that fails is not normal flow, so it throws a
  `SpeakException`.
- **One utterance on the engine at a time.** `speak` keeps the queue itself
  and gives the engine the next utterance only when the previous one has
  ended. Interrupting, expiring and pausing then work the same on every
  platform.
- **"Interrupted" is decided in Dart**, from the speaker's own `stop()` or
  interrupting call, never from which callback the platform sends. After a
  stop, macOS reports "finished", not "cancelled".
- **Nothing waits forever.** Each utterance has a timeout scaled to its
  length and rate (10 s plus 150 ms per character at normal speed). `stop()`
  gives the engine one second to confirm, then ends the utterance anyway.
- **The audio is held only while speaking**, plus a short linger, unless
  you ask for more with `holdAudio()`. Whether a lead-in is due is decided
  in Dart from when the audio was claimed, so it is the same on every
  platform.

## Testing

```sh
flutter test                         # the core, against a fake engine
tool/web_test.sh                     # the same, plus the real engine, in Chrome
tool/web_test.sh --wasm              # ... compiled to Wasm
cd example && flutter test integration_test -d <iOS simulator or Android emulator>
tool/macos_integration_test.sh       # macOS, see Known issues
```

The device and browser tests run the same scenarios
(`test/support/scenarios.dart`) against each platform's real engine. To
regenerate the bindings, run `tool/generate.sh` (Xcode for ffigen; a JDK and
`ANDROID_SDK_ROOT` with platform 36 for jnigen).

## Releasing

Tagged versions are published by GitHub Actions; see
[RELEASING.md](RELEASING.md).

## Contributing

Issues and pull requests are welcome at
[github.com/orkitec/speak](https://github.com/orkitec/speak). See
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

BSD-3-Clause. See [LICENSE](LICENSE).

---

Built for Velorki, a free bike GPS planner and tracker:
[velorki.com](https://velorki.com)
