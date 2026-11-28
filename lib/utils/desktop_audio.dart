// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:matrix/matrix.dart';

/// Initialises the media_kit audio backend used by the call sounds and the
/// desktop notification chime.
///
/// media_kit needs libmpv at runtime and `ensureInitialized()` throws when it
/// cannot load it. On Linux that used to abort [main] before `runApp`, so the
/// GTK window stayed empty - the reported "black screen". Sound is optional,
/// the app is not, so a missing backend is logged and startup continues.
void ensureDesktopAudio() {
  try {
    JustAudioMediaKit.ensureInitialized();
    return;
  } catch (e, s) {
    Logs().w(
      '[audio] no usable libmpv, call and notification sounds are disabled',
      e,
      s,
    );
  }

  // Second chance: the Linux bundle may ship libmpv next to libapp.so, which
  // dlopen does not necessarily find through the runner's RPATH.
  final bundled = _bundledLibmpv();
  if (bundled == null) return;
  try {
    JustAudioMediaKit.ensureInitialized(libmpv: bundled);
    Logs().i('[audio] using the libmpv shipped with the bundle');
  } catch (e, s) {
    Logs().w('[audio] the bundled libmpv is unusable too', e, s);
  }
}

String? _bundledLibmpv() {
  if (kIsWeb || !Platform.isLinux) return null;
  final libDir = '${File(Platform.resolvedExecutable).parent.path}/lib';
  for (final name in const ['libmpv.so.2', 'libmpv.so.1', 'libmpv.so']) {
    final file = File('$libDir/$name');
    if (file.existsSync()) return file.path;
  }
  return null;
}
