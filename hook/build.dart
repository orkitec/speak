// Compiles the Objective-C glue that ffigen generates beside the AVFAudio
// bindings (protocol and block trampolines) for iOS and macOS. Nothing is
// built for any other platform.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    if (os != OS.iOS && os != OS.macOS) return;
    await CBuilder.library(
      name: 'speak_darwin',
      assetName: 'src/darwin/av_bindings.dart',
      sources: ['darwin/av_bindings.m'],
      language: Language.objectiveC,
      flags: ['-fobjc-arc'],
      frameworks: ['Foundation', 'AVFAudio'],
    ).run(input: input, output: output);
  });
}
