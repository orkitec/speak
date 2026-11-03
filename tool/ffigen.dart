// Regenerates lib/src/darwin/av_bindings.dart from the iOS SDK's AVFAudio
// headers. Run from the package root: `dart run tool/ffigen.dart`.
import 'dart:io';

import 'package:ffigen/ffigen.dart';

const _interfaces = <String, Set<String>>{
  'AVSpeechSynthesizer': {
    'new',
    'delegate',
    'setDelegate:',
    'speakUtterance:',
    'stopSpeakingAtBoundary:',
    'isSpeaking',
    'isPaused',
    'pauseSpeakingAtBoundary:',
    'continueSpeaking',
    'usesApplicationAudioSession',
    'setUsesApplicationAudioSession:',
  },
  'AVSpeechUtterance': {
    'speechUtteranceWithString:',
    'voice',
    'setVoice:',
    'rate',
    'setRate:',
    'pitchMultiplier',
    'setPitchMultiplier:',
    'volume',
    'setVolume:',
    'speechString',
  },
  'AVSpeechSynthesisVoice': {
    'speechVoices',
    'voiceWithIdentifier:',
    'voiceWithLanguage:',
    'language',
    'identifier',
    'name',
    'quality',
    'gender',
  },
  // Plays the silent lead-in: AVSpeechUtterance.preUtteranceDelay is
  // ignored by the iOS 26 simulator, and nothing says it reaches the audio
  // output as sound a Bluetooth link would wake up for.
  'AVAudioPlayer': {
    'alloc',
    'initWithData:error:',
    'prepareToPlay',
    'play',
    'stop',
    'setVolume:',
  },
  'AVAudioSession': {
    'sharedInstance',
    'setCategory:mode:options:error:',
    'setActive:withOptions:error:',
  },
};

const _protocolMethods = {
  'speechSynthesizer:didStartSpeechUtterance:',
  'speechSynthesizer:didFinishSpeechUtterance:',
  'speechSynthesizer:didCancelSpeechUtterance:',
  'speechSynthesizer:willSpeakRangeOfSpeechString:utterance:',
};

const _globals = {
  'AVSpeechUtteranceDefaultSpeechRate',
  'AVSpeechUtteranceMinimumSpeechRate',
  'AVSpeechUtteranceMaximumSpeechRate',
  'AVAudioSessionCategoryPlayback',
  'AVAudioSessionCategoryAmbient',
  'AVAudioSessionModeDefault',
  'AVAudioSessionModeVoicePrompt',
  'AVAudioSessionModeSpokenAudio',
};

Future<void> main() async {
  final root = Platform.script.resolve('../');
  final headers = iosSdkUri.resolve(
    'System/Library/Frameworks/AVFAudio.framework/Headers/',
  );
  await FfiGenerator(
    input: Input(
      entryPoints: [
        headers.resolve('AVSpeechSynthesis.h'),
        headers.resolve('AVAudioSession.h'),
        headers.resolve('AVAudioPlayer.h'),
      ],
      compilerOptions: [
        '-isysroot',
        iosSdkUri.toFilePath(),
        '-target',
        'arm64-apple-ios13.0',
      ],
      appendCompilerOptions: true,
    ),
    output: Output(
      dart: DartOutput(path: root.resolve('lib/src/darwin/av_bindings.dart')),
      objectiveCFile: root.resolve('darwin/av_bindings.m'),
      preamble: '// ignore_for_file: type=lint, unused_field\n',
    ),
    objectiveC: ObjectiveC(
      externalVersions: ExternalVersions(
        ios: Versions(min: Version(13, 0, 0)),
        macos: Versions(min: Version(10, 15, 0)),
      ),
    ),
    visitors: [
      Visitor(
        objCInterface: (node) {
          if (_interfaces.containsKey(node.originalName)) {
            node.isIncluded = true;
            // Categories are taken one by one below, so a framework update
            // does not pull new ones in.
            node.includeCategories = false;
          }
        },
        objCCategory: (node) {
          if (node.interface.originalName == 'AVAudioSession' &&
              node.originalName == 'Activation') {
            node.isIncluded = true;
          }
        },
        objCProtocol: (node) {
          if (node.originalName == 'AVSpeechSynthesizerDelegate') {
            node.isIncluded = true;
          }
        },
        objCMethod: (node) {
          final parent = node.parent;
          final name = switch (parent) {
            ObjCInterface() => parent.originalName,
            ObjCProtocol() => parent.originalName,
            ObjCCategory() => parent.interface.originalName,
            _ => null,
          };
          if (name == 'AVSpeechSynthesizerDelegate') {
            node.isIncluded = _protocolMethods.contains(node.selector);
          } else if (_interfaces[name] case final allowed?) {
            node.isIncluded = allowed.contains(node.selector);
          }
        },
        global: (node) {
          if (_globals.contains(node.originalName)) node.isIncluded = true;
        },
        enumClass: (node) {
          // NS_ENUMs over NSInteger/NSUInteger: 64 bits on every Apple
          // target this package builds for.
          node.silenceWarning = true;
          if (const {
            'AVSpeechBoundary',
            'AVSpeechSynthesisVoiceQuality',
            'AVSpeechSynthesisVoiceGender',
            'AVAudioSessionCategoryOptions',
            'AVAudioSessionSetActiveOptions',
          }.contains(node.originalName)) {
            node.isIncluded = true;
          }
        },
      ),
    ],
  ).generate();
}
