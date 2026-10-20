import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../repositories/engagement_repository.dart';
import '../../theme/app_theme.dart';

/// Opening Moves editor: up to three user-authored prompts the server may
/// attach when they initiate a conversation. Backed by the `opening_moves`
/// table (migration 032); the database validates slot bounds and prompt
/// length, and this save only reports rows that came back as written.
class OpeningMovesDialog extends StatefulWidget {
  const OpeningMovesDialog({super.key});

  @override
  State<OpeningMovesDialog> createState() => _OpeningMovesDialogState();
}

class _OpeningMovesDialogState extends State<OpeningMovesDialog> {
  final OpeningMoveRepository _repository = OpeningMoveRepository();

  static const _slotCount = 3;

  bool _busy = false;
  bool _loading = true;
  List<OpeningMove> _moves = const [];
  final Map<int, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final moves = await _repository.fetchMine();
    if (!mounted) return;
    setState(() {
      _moves = moves;
      for (var slot = 1; slot <= _slotCount; slot++) {
        _controllers[slot] ??= TextEditingController(
          text: moves
              .where((m) => m.sortOrder == slot)
              .fold<String>('', (_, m) => m.prompt),
        );
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final outgoing = <OpeningMove>[
      for (final move in _moves)
        OpeningMove(
          id: move.id,
          sortOrder: move.sortOrder,
          prompt: _controllers[move.sortOrder]?.text ?? '',
          photoId: move.photoId,
        ),
      // Slots the user filled for the first time (no stored row yet).
      for (var slot = 1; slot <= _slotCount; slot++)
        if (!_moves.any((m) => m.sortOrder == slot))
          OpeningMove(
            id: '',
            sortOrder: slot,
            prompt: _controllers[slot]?.text ?? '',
          ),
    ];
    final ok = await _repository.upsertAll(outgoing);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opening moves saved on the server.'),
          backgroundColor: AppTheme.onlineGreen,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your opening moves were rejected. Keep prompts within 160 '
            'characters and free of links or social handles.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Opening Moves',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18)),
            SizedBox(height: 4),
            Text(
              'Up to 3 lines the server may use when you match. Leave one '
              'blank to clear it.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            SizedBox(height: 12),
            if (_loading)
              Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              for (var slot = 1; slot <= _slotCount; slot++)
                Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _controllers[slot],
                    maxLength: 160,
                    maxLines: 2,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Opening move $slot',
                      counterStyle:
                          TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
            Align(
              alignment: Alignment.centerRight,
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: _save,
                      child: Text('Save',
                          style: TextStyle(color: Theme.of(context).colorScheme.tertiary)),
                    ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    Text('Close', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
