import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../settings/settings.dart';

Future<dynamic> showGameSetupDialog(BuildContext context) {
  return showGeneralDialog<dynamic>(
    context: context,
    pageBuilder: (context, animation, secondaryAnimation) =>
        GameSetupDialog(animation: animation),
  );
}

class GameSetupDialog extends StatefulWidget {
  final Animation<double> animation;

  const GameSetupDialog({required this.animation, super.key});

  @override
  State<GameSetupDialog> createState() => _GameSetupDialogState();
}

class _GameSetupDialogState extends State<GameSetupDialog> {
  final TextEditingController _redController = TextEditingController();
  final TextEditingController _blackController = TextEditingController();
  bool _randomizeColors = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsController>();
      if (mounted) {
        _redController.text = settings.redPlayerName.value;
        _blackController.text = settings.blackPlayerName.value;
      }
    });
  }

  @override
  void dispose() {
    _redController.dispose();
    _blackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsController>();
    return ScaleTransition(
      scale: CurvedAnimation(
        parent: widget.animation,
        curve: Curves.easeOutCubic,
      ),
      child: SimpleDialog(
        title: const Text('Game Setup'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                TextField(
                  controller: _redController,
                  decoration: const InputDecoration(
                    labelText: 'Red player name',
                  ),
                  autofocus: true,
                  maxLength: 12,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (value) => settings.setRedPlayerName(value),
                ),
                TextField(
                  controller: _blackController,
                  decoration: const InputDecoration(
                    labelText: 'Black player name',
                  ),
                  maxLength: 12,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (value) => settings.setBlackPlayerName(value),
                ),
                CheckboxListTile(
                  title: const Text('Randomize who is Red'),
                  value: _randomizeColors,
                  onChanged: (value) {
                    setState(() => _randomizeColors = value ?? false);
                  },
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, {
                    'start': true,
                    'randomize': _randomizeColors,
                  });
                },
                child: const Text('Start'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
