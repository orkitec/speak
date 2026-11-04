// Regenerates lib/src/android/jni_bindings.dart: the Android APIs the
// Android backend calls, and the listener in android/src/main/java.
//
// Needs a JDK (17 to 21) and the Android SDK's platform 36 (ANDROID_SDK_ROOT,
// or ANDROID_HOME). Run from the package root: `dart run tool/jnigen.dart`.
import 'dart:io';

import 'package:jnigen/jnigen.dart';

/// The members bound, per class; a class not listed here is bound whole.
const _members = <String, Set<String>>{
  'android.speech.tts.TextToSpeech': {
    '<init>',
    'speak',
    'playSilentUtterance',
    'stop',
    'shutdown',
    'setSpeechRate',
    'setPitch',
    'setLanguage',
    'isLanguageAvailable',
    'setVoice',
    'getVoices',
    'getEngines',
    'getDefaultEngine',
    'setAudioAttributes',
    'setOnUtteranceProgressListener',
  },
  'android.speech.tts.TextToSpeech\$EngineInfo': {'<init>'},
  'android.speech.tts.TextToSpeech\$Engine': {'<init>'},
  'android.speech.tts.Voice': {
    'getName',
    'getLocale',
    'getQuality',
    'isNetworkConnectionRequired',
    'getFeatures',
  },
  'android.media.AudioAttributes\$Builder': {
    '<init>',
    'setUsage',
    'setContentType',
    'build',
  },
  'android.media.AudioAttributes': {},
  'android.media.AudioFocusRequest\$Builder': {
    '<init>',
    'setAudioAttributes',
    'setOnAudioFocusChangeListener',
    'setWillPauseWhenDucked',
    'build',
  },
  'android.media.AudioFocusRequest': {},
  'android.media.AudioManager': {
    'getMode',
    // Only for the integration tests, which play a VoIP call.
    'setMode',
    'getDevices',
    'getAudioDevicesForAttributes',
    'requestAudioFocus',
    'abandonAudioFocusRequest',
    'abandonAudioFocus',
  },
  'android.media.AudioDeviceInfo': {'getType'},
  'android.content.Context': {'getSystemService'},
  // Only for the integration tests, which put the app in the background.
  'android.app.Activity': {'moveTaskToBack', 'getTaskId'},
  'android.app.ActivityManager': {'moveTaskToFront'},
  'android.os.Bundle': {'<init>', 'putFloat'},
  'android.os.Build\$VERSION': {},
  'java.util.Locale': {'forLanguageTag', 'toLanguageTag'},
  'android.os.Build': {},
  'com.orkitec.speak.SpeakPlugin': {},
};

/// Nested classes bound whole; any other nested class is left out.
const _whole = {
  'android.speech.tts.TextToSpeech\$OnInitListener',
  'android.media.AudioManager\$OnAudioFocusChangeListener',
  'com.orkitec.speak.SpeakPlugin\$Callbacks',
  'com.orkitec.speak.SpeakPlugin\$ProgressListener',
};

/// Fields bound, per class; every other field is left out.
const _fields = <String, Set<String>>{
  'android.speech.tts.TextToSpeech': {
    'SUCCESS',
    'QUEUE_FLUSH',
    'QUEUE_ADD',
    'LANG_AVAILABLE',
    'LANG_COUNTRY_AVAILABLE',
    'LANG_COUNTRY_VAR_AVAILABLE',
    'LANG_MISSING_DATA',
    'LANG_NOT_SUPPORTED',
    'ERROR_NETWORK',
    'ERROR_NETWORK_TIMEOUT',
    'ERROR_NOT_INSTALLED_YET',
    'ERROR_SERVICE',
  },
  'android.speech.tts.TextToSpeech\$EngineInfo': {'name', 'label'},
  'android.speech.tts.TextToSpeech\$Engine': {
    'KEY_FEATURE_NOT_INSTALLED',
    'KEY_FEATURE_NETWORK_SYNTHESIS',
    'KEY_PARAM_VOLUME',
  },
  'android.media.AudioAttributes': {
    'USAGE_ASSISTANCE_NAVIGATION_GUIDANCE',
    'USAGE_ASSISTANT',
    'USAGE_MEDIA',
    'CONTENT_TYPE_SPEECH',
  },
  'android.media.AudioManager': {
    'AUDIOFOCUS_GAIN_TRANSIENT',
    'AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK',
    'STREAM_MUSIC',
    'GET_DEVICES_OUTPUTS',
    'MODE_NORMAL',
    'MODE_IN_COMMUNICATION',
    'AUDIOFOCUS_REQUEST_FAILED',
    'AUDIOFOCUS_GAIN',
    'AUDIOFOCUS_LOSS',
    'AUDIOFOCUS_LOSS_TRANSIENT',
    'AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK',
  },
  'android.media.AudioDeviceInfo': {
    'TYPE_BLUETOOTH_A2DP',
    'TYPE_BLUETOOTH_SCO',
    'TYPE_BLE_HEADSET',
    'TYPE_BLE_SPEAKER',
    'TYPE_HEARING_AID',
  },
  'android.content.Context': {'AUDIO_SERVICE', 'ACTIVITY_SERVICE'},
  'android.os.Build\$VERSION': {'SDK_INT'},
};

final class _Filter extends Visitor {
  _Filter() : super.base();

  String? _class;

  @override
  void visitClass(ClassDecl c) {
    _class = c.binaryName;
    c.isIncluded = _members.containsKey(_class) || _whole.contains(_class);
  }

  @override
  void visitMethod(Method method) {
    final allowed = _members[_class];
    if (allowed == null) return;
    method.isIncluded = allowed.contains(
      method.isConstructor ? '<init>' : method.originalName,
    );
  }

  @override
  void visitField(Field field) {
    if (_class == null || _class!.startsWith('com.orkitec.')) return;
    field.isIncluded = _fields[_class]?.contains(field.originalName) ?? false;
  }
}

Future<void> main() async {
  final root = Platform.script.resolve('../');
  final sdk =
      Platform.environment['ANDROID_SDK_ROOT'] ??
      Platform.environment['ANDROID_HOME'];
  if (sdk == null) {
    stderr.writeln('Set ANDROID_SDK_ROOT to an Android SDK with platform 36.');
    exit(1);
  }
  // FlutterPlugin, which the listener's file also declares, is in the
  // Flutter engine's jar.
  final flutterRoot = File(
    Platform.resolvedExecutable,
  ).parent.parent.parent.parent.parent;
  final flutterJar = flutterRoot.uri.resolve(
    'bin/cache/artifacts/engine/android-arm64/flutter.jar',
  );
  await JniGenerator(
    input: Input(
      // Nested classes come with their outer class.
      classes: [
        for (final c in _members.keys)
          if (!c.contains(r'$')) c,
      ],
      sourcePath: [root.resolve('android/src/main/java/')],
      classPath: [flutterJar],
      androidSdk: AndroidSdk(versions: [36], sdkRoot: Uri.directory(sdk)),
    ),
    output: Output(
      dart: DartOutput(
        path: root.resolve('lib/src/android/jni_bindings.dart'),
        structure: OutputStructure.singleFile,
      ),
    ),
    visitors: [_Filter()],
  ).generate();
}
