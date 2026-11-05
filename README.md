# speak

[![pub package](https://img.shields.io/pub/v/speak.svg)](https://pub.dev/packages/speak)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

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

- **iOS**: for speech to be heard while the app is in the background, add
  the `audio` background mode to `Info.plist` (and see
  [Running in the background](#running-in-the-background)):
  ```xml
  <key>UIBackgroundModes</key>
  <array><string>audio</string></array>
  ```
  The package does not link CallKit; it loads it at run time to ask about
  calls. For an app sold on the China storefront, where App Review rejects
  apps containing CallKit, pass `Speak(ios: IosSpeakOptions(callKit:
  false))`; see [Calls and other interruptions](#calls-and-other-interruptions).
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

### Calls and other interruptions

When a phone call, Siri, an alarm or another app takes the audio:

- what is being said is cut off and ends as `SpeakOutcome.interrupted`, and
  so does anything waiting;
- an utterance asked for while a call is going on (on Android also while
  another app holds the focus for now) ends at once as
  `SpeakOutcome.blocked`. Nothing is
  kept for after the call: an instruction from during it is out of date by
  then;
- otherwise the next utterance claims the audio afresh, with the usual
  lead-in.

Only what the platform says at that moment blocks an utterance, never a
remembered interruption: iOS does not promise an end for every beginning,
and a flag left set would keep the rest of a ride silent.

| | Interruption begins | Ends | Call in progress |
| --- | --- | --- | --- |
| iOS | `AVAudioSessionInterruptionNotification` (began); from iOS 27 also `DidBecomeInactive` with an interruption context, reported once | the notification's ended, or `ResumptionRecommendation` | CallKit's `CXCallObserver` (phone calls and CallKit VoIP calls, no permission), asked before every utterance since the session is inactive between prompts; CallKit is loaded at run time, not linked, and never with `IosSpeakOptions(callKit: false)` (China storefront), when only the interruption notification catches a call |
| Android | our audio focus lost for now (`AUDIOFOCUS_LOSS_TRANSIENT`) | the focus back (`AUDIOFOCUS_GAIN`) | any audio mode but `MODE_NORMAL` (ringing, in a call, in a VoIP call), or our focus still taken |
| macOS, web | not reported | | |

On Android a permanent focus loss (another app starting music) cuts off
what is being said but blocks nothing after it. A short duck request from
another app (`AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK`, a notification sound or
another app's prompt) is no interruption: the system lowers the speech and
it carries on. With `OtherAudio.mix` no focus is requested, so Android
reports no interruptions; the call-mode check still applies.

A claim refused for any other reason does not block. Android 15 refuses
audio focus to an app that is in the background without a foreground
service (`AUDIOFOCUS_REQUEST_FAILED`; on the API 35 emulator only after a
grace of a few seconds, between 3 and 6 s after leaving the front); then,
with no call going on, the text is spoken without focus, as with
`OtherAudio.mix`, and other audio is not lowered for it. A navigation app that speaks with the screen off keeps
its focus by running a foreground service, as it does for its location
updates anyway. On iOS a session that cannot be activated (from the
background without the `audio` background mode, for instance) is tried
without it as well; whether a call is going on comes from CallKit, never
from the activation error.

`SpeakAudio(duringCalls: SpeakDuringCalls.speak)` speaks anyway: the call
is not asked about and a refused claim does not block. An interruption
still cuts off what it interrupted. On iOS the system decides whether the
speech is heard during a call.

### Running in the background

`speak` claims the audio only while it speaks, so it keeps nothing running
between prompts. Whether the app is still there to speak the next one is up
to the app.

- **iOS**: with the `audio` background mode, speech is heard while the app
  is in the background or the screen is locked. But between prompts the
  session is given back, and an app that plays nothing is suspended a few
  seconds after it leaves the screen. Keep the app running with its own
  reason to (background location updates for navigation, a workout
  session), or use notifications for what it has to say while suspended.
- **Android**: speaking works as long as the process lives. For a long
  stretch in the background the app needs its own foreground service (type
  `location` for navigation, `mediaPlayback` for reading). From Android 15
  an app in the background without one gets no audio focus: `speak` then
  speaks without it, so other audio is not lowered for the prompt.
- **macOS** keeps running apps running; the **web** depends on the browser,
  which may suspend a tab in the background.

### iOS: CallKit and the China storefront

App Review rejects apps that contain CallKit on the China storefront. The
package never links it: `tool/check_no_callkit.sh` holds every build to
that, in CI. It loads the system framework at run time, on the first
utterance, only to ask whether a call is going on.

```dart
final speak = Speak(ios: const IosSpeakOptions(callKit: false));
```

With `callKit: false` it is never loaded by the package. Calls are then
caught only while `speak` holds the audio session (the interruption
notification), so a prompt due during a call that started between two
prompts may be spoken over it. (Once something is spoken, iOS's own speech
synthesis loads CallKit into the process itself: that is Apple's framework,
not part of the app's binary.)

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
| Voice list right after start | as soon as the system answers (asked off the main thread); an utterance waits at most 1 s for it | `voices()` waits up to 10 s after the engine starts while it is still loading its voices; an utterance waits at most 1 s for the list, then is spoken in its language (while loading, in the engine's current voice) | `voices()` waits up to 2 s for `voiceschanged`; an utterance at most 1 s |
| Gender | reported | `unknown` | `unknown` |
| Other audio | lowered/paused (iOS); macOS has no session | lowered/paused through audio focus (API 26+ with attributes, older with the music stream) | not possible |
| Lead-in (on Bluetooth by default) | silent samples through the session; on macOS only with `leadInOnBluetoothOnly: false` | `playSilentUtterance` | none |
| `<`, `>` and `&` in the text | said as written; macOS and iOS before 27 read markup in plain text, so `speak` escapes them there | said as written; a text that starts with `<` would be read as SSML by Google's engine, so `speak` sends it as an SSML document of its words, escaped | said as written; on macOS escaped as there, except for a server voice; Safari before iOS 27 still loses words after a `<`; Chromium on Windows reads `<` and `>` as spaces |

`rate` is relative everywhere: 1 is the platform's normal speed. On iOS and
macOS it scales AVFoundation's default utterance rate, capped at its maximum
(about twice the normal speed).

## Known issues

- **macOS: sandboxed debug builds under `flutter run` / `flutter test`.**
  The system voices are rendered by a speech audio unit that macOS runs as
  an app extension for the app. An app started by the flutter tool (or from
  a shell) is not launched through LaunchServices and has no app identity
  to host it with; AudioToolbox then tries to load the unit inside the app,
  which the App Sandbox refuses. Every utterance ends at once as
  `SpeakException(synthesisFailed)` (the log shows
  `audioUnitInstantiationError`, OSStatus -3000). An app opened from the
  Finder, the Dock or with `open` is not affected, sandboxed or not, and
  neither are release builds. For development, turn the sandbox off in the
  debug entitlements only, as the example does: in
  `macos/Runner/DebugProfile.entitlements`, `com.apple.security.app-sandbox`
  `false`; keep `Release.entitlements` sandboxed.
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
DEVICE=<emulator> tool/android_integration_test.sh  # Android
UDID=<simulator> tool/ios_integration_test.sh       # iOS, in two app launches
tool/macos_integration_test.sh                      # macOS, in one
```

The scripts speak at volume 0 (the engines still synthesise and report as
at full volume); pass `--loud` first to hear them. CI runs at full volume.
`SPEAK_TEST_TRACE=1` prints every scenario's engine trace, passed or not.

The device and browser tests run the same scenarios
(`test/support/scenarios.dart`) against each platform's real engine. A
scenario that fails prints what the engine was told and reported, with
times; one whose engine stalled or never answered is run once more, after a
GitHub `::warning::`, and a wrong answer is never retried. To
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
