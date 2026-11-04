# speak example

A demo of the `speak` package: the installed voices, a language check, speak
(queued or interrupting), stop, pause and resume, rate and pitch, the word
being spoken highlighted, the audio modes, and on Android the engine choice.

To hear ducking, play music in another app, pick "Prompt (duck)" and tap
Speak: the music dips while the text is spoken and comes back after.

```sh
flutter run
```

On macOS the debug build is not sandboxed, so `flutter run` speaks; see
"Known issues" in the package README. The integration tests are in
`integration_test/`.
