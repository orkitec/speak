/// Text-to-speech for short spoken prompts over other audio, on iOS, macOS,
/// Android and the web.
///
/// ```dart
/// import 'package:speak/speak.dart';
///
/// final speak = Speak();
/// await speak('In two hundred metres, turn left.');
/// ```
library;

export 'src/android_options.dart';
export 'src/audio.dart';
export 'src/ios_options.dart';
export 'src/outcome.dart';
export 'src/speak.dart' show Speak;
export 'src/voice.dart';
