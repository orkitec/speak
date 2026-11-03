// Picks the platform's backend without letting `dart:ffi` (iOS, macOS,
// Android) reach a web build, or `package:web` a native one.
export 'platform_unsupported.dart'
    if (dart.library.js_interop) 'platform_web.dart'
    if (dart.library.ffi) 'platform_native.dart';
