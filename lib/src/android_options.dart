/// Settings that only exist on Android; ignored everywhere else.
///
/// ```dart
/// final engines = await Speak.androidEngines();
/// final speak = Speak(
///   android: AndroidSpeakOptions(engine: engines.first.name),
/// );
/// ```
class AndroidSpeakOptions {
  /// Creates the options.
  const AndroidSpeakOptions({this.engine});

  /// The package name of the text-to-speech engine to speak with, e.g.
  /// `com.google.android.tts`, from [AndroidEngine.name]; `null` for the
  /// engine the user picked in the system settings.
  final String? engine;

  @override
  bool operator ==(Object other) =>
      other is AndroidSpeakOptions && other.engine == engine;

  @override
  int get hashCode => engine.hashCode;
}

/// A text-to-speech engine installed on an Android device.
class AndroidEngine {
  /// Creates an engine description.
  const AndroidEngine({
    required this.name,
    required this.label,
    required this.isDefault,
  });

  /// The engine's package name, e.g. `com.google.android.tts`; what
  /// [AndroidSpeakOptions.engine] takes.
  final String name;

  /// The name to show, e.g. "Speech Services by Google".
  final String label;

  /// Whether this is the engine the user picked in the system settings.
  final bool isDefault;

  @override
  bool operator ==(Object other) =>
      other is AndroidEngine &&
      other.name == name &&
      other.label == label &&
      other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(name, label, isDefault);

  @override
  String toString() =>
      'AndroidEngine($name, $label${isDefault ? ', default' : ''})';
}
