// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';

/// Describes a build as `1.2.3 (45)`.
///
/// The build number is left out when it repeats the version, or when there is
/// no build number at all, and an unreadable platform reports `unknown`.
String formatVersion({required String version, required String buildNumber}) {
  final v = version.trim();
  final b = buildNumber.trim();
  if (v.isEmpty) {
    return b.isEmpty ? 'unknown' : b;
  }
  return b.isEmpty || b == v ? v : '$v ($b)';
}

/// Shows the game's name, who it belongs to, and which build is running.
///
/// The version and build number are read from the running package rather than
/// being written down here, so they always match `pubspec.yaml` and whatever
/// the store actually shipped.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<String> _version = _readVersion();

  /// Asks the platform what build is running, formatted for display.
  Future<String> _readVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return formatVersion(
        version: info.version,
        buildNumber: info.buildNumber,
      );
    } on Object {
      return formatVersion(version: '', buildNumber: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    const smallStyle = TextStyle(fontSize: 14, height: 1.3);

    return Scaffold(
      backgroundColor: palette.backgroundSettings,
      body: ResponsiveScreen(
        squarishMainArea: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Classic Checkers',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Permanent Marker',
                    fontSize: 34,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Copyright (c) 2026 Neward & Associates, LLC',
                  textAlign: TextAlign.center,
                  style: smallStyle.copyWith(color: palette.ink),
                ),
                const SizedBox(height: 6),
                FutureBuilder<String>(
                  future: _version,
                  builder: (context, snapshot) {
                    final version = snapshot.data;
                    return Text(
                      version == null ? 'Version' : 'Version $version',
                      textAlign: TextAlign.center,
                      style: smallStyle.copyWith(color: palette.ink),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        rectangularMenuArea: MyButton(
          onPressed: () => GoRouter.of(context).pop(),
          child: const Text('Back'),
        ),
      ),
    );
  }
}
