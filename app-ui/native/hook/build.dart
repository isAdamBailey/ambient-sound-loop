// Builds the native audio layer (libambientsynth + platform-audio/player +
// miniaudio) as one dynamic library for the target platform.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

// Same pin as cmake/miniaudio.cmake.
const _miniaudioVersion = '0.11.21';
const _miniaudioSha256 =
    '6b2029714f8634c4d7c70cc042f45074e0565766113fc064f20cd27c986be9c9';

// Paths are relative to this package (app-ui/native).
const _repo = '../../';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    final apple = os == OS.iOS || os == OS.macOS;
    final logger = Logger('')
      ..level = Level.INFO
      // Hook output is how the build reports progress.
      // ignore: avoid_print
      ..onRecord.listen((record) => print(record.message));

    final miniaudioDir = await _fetchMiniaudio(input.outputDirectoryShared);

    final builder = CBuilder.library(
      name: 'ambient_native',
      assetName: 'ambient_native.dart',
      sources: [
        '${_repo}core-cpp/src/engine/engine.cpp',
        '${_repo}platform-audio/player/ambient_player.cpp',
        // The iOS backend of miniaudio is Objective-C.
        apple
            ? '${_repo}platform-audio/player/miniaudio_impl.mm'
            : '${_repo}platform-audio/player/miniaudio_impl.cpp',
      ],
      includes: [
        '${_repo}core-cpp/include',
        '${_repo}core-cpp/src',
        '${_repo}core-cpp/src/engine',
        '${_repo}platform-audio/player',
        miniaudioDir.path,
      ],
      std: 'c++20',
      // On Apple the sources mix C++ and Objective-C++, so the language is
      // left to each file's extension and libc++ is linked by hand.
      language: apple ? Language.c : Language.cpp,
      libraries: [
        if (apple) 'c++',
        if (os == OS.android || os == OS.linux) ...['dl', 'm'],
        if (os == OS.linux) 'pthread',
      ],
      frameworks: [
        'Foundation',
        if (apple) ...['CoreFoundation', 'AudioToolbox'],
        if (os == OS.macOS) 'CoreAudio',
        if (os == OS.iOS) 'AVFoundation',
      ],
      defines: {
        'MA_NO_DECODING': null,
        'MA_NO_ENCODING': null,
        'MA_NO_GENERATION': null,
        'MA_NO_RESOURCE_MANAGER': null,
        'MA_NO_NODE_GRAPH': null,
        'MA_NO_ENGINE': null,
        // Link the Apple frameworks directly (App Store and notarization).
        if (apple) 'MA_NO_RUNTIME_LINKING': null,
      },
      flags: [if (os == OS.windows) '/EHsc'],
    );
    await builder.run(input: input, output: output, logger: logger);
  });
}

/// Downloads miniaudio.h once into the shared output directory and checks it
/// against the pinned hash.
Future<Uri> _fetchMiniaudio(Uri sharedDir) async {
  final dir = sharedDir.resolve('miniaudio-$_miniaudioVersion/');
  final header = File.fromUri(dir.resolve('miniaudio.h'));
  if (header.existsSync() &&
      sha256.convert(header.readAsBytesSync()).toString() == _miniaudioSha256) {
    return dir;
  }
  final url = Uri.parse(
    'https://raw.githubusercontent.com/mackron/miniaudio/$_miniaudioVersion/miniaudio.h',
  );
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != 200) {
      throw HttpException('Downloading miniaudio failed: ${response.statusCode}', uri: url);
    }
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    final digest = sha256.convert(bytes).toString();
    if (digest != _miniaudioSha256) {
      throw StateError('miniaudio.h hash mismatch: $digest');
    }
    Directory.fromUri(dir).createSync(recursive: true);
    header.writeAsBytesSync(bytes);
  } finally {
    client.close();
  }
  return dir;
}
