// Lists the speech voices on an iOS simulator, so that
// tool/ios_integration_test.sh knows they can be listed before it starts the
// tests: +[AVSpeechSynthesisVoice speechVoices] blocks its thread while the
// system cannot answer (see the script), and in the test app that thread is
// the main thread. Run with `xcrun simctl spawn <udid> <binary>`.
#import <AVFoundation/AVFoundation.h>

int main(void) {
  @autoreleasepool {
    NSDate *start = [NSDate date];
    NSArray<AVSpeechSynthesisVoice *> *voices =
        [AVSpeechSynthesisVoice speechVoices];
    printf("%lu speech voices after %.1f s\n", (unsigned long)voices.count,
           -[start timeIntervalSinceNow]);
    return voices.count > 0 ? 0 : 1;
  }
}
