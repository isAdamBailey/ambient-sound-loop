/// Exact length entry, opened from the dial: a keypad in a bottom sheet on
/// narrow layouts, typed fields in a dialog on wide ones. Nothing changes until
/// Done; Cancel discards. Spec #9 §4.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../session/length.dart';
import 'theme.dart';

/// Shows exact entry and returns the length entered, or null on Cancel.
Future<SessionLength?> showExactLength(
  BuildContext context, {
  required SessionLength current,
  required bool wide,
}) {
  if (wide) {
    return showDialog<SessionLength>(
      context: context,
      barrierColor: const Color(0xB3000000),
      builder: (_) => Dialog(
        backgroundColor: SessionColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: SessionColors.rule),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LengthPicker(current: current, wide: true),
        ),
      ),
    );
  }
  return showModalBottomSheet<SessionLength>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SessionColors.raised,
    barrierColor: const Color(0xB3000000),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: SessionColors.rule),
    ),
    builder: (_) => LengthPicker(current: current, wide: false),
  );
}

class LengthPicker extends StatefulWidget {
  const LengthPicker({super.key, required this.current, required this.wide});

  final SessionLength current;
  final bool wide;

  @override
  State<LengthPicker> createState() => _LengthPickerState();
}

class _LengthPickerState extends State<LengthPicker> {
  late ExactEntry _entry;
  late final List<TextEditingController> _fields; // wide: hours, minutes, seconds

  @override
  void initState() {
    super.initState();
    // A preset or Until I stop starts a fresh entry, like a phone timer.
    final current = widget.current;
    final isPreset = lengthPresets.any((p) => p.length == current);
    _entry = isPreset ? const ExactEntry.empty() : ExactEntry.of(current.duration ?? Duration.zero);
    _fields = [
      for (final v in [_entry.hours, _entry.minutes, _entry.seconds])
        TextEditingController(text: v.toString().padLeft(2, '0')),
    ];
  }

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  void _done() {
    if (!_entry.isValid) return; // refused; the sheet says why
    Navigator.of(context).pop(SessionLength.timed(_entry.duration));
  }

  @override
  Widget build(BuildContext context) {
    final refused = !_entry.isValid;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: widget.wide ? const EdgeInsets.fromLTRB(20, 16, 20, 20) : const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 16),
            if (widget.wide) _fieldsRow() else ..._keypad(),
            if (refused) ...[
              const SizedBox(height: 14),
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: SessionColors.rule),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Enter a length, or choose Until I stop.', style: SessionText.weight(14, 400)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    TextButton action(String label, VoidCallback onPressed, {required bool strong}) => TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
      child: Text(
        label,
        style: SessionText.weight(16, strong ? 600 : 400, color: strong ? SessionColors.ink : SessionColors.dim),
      ),
    );
    return Row(
      children: [
        action('Cancel', () => Navigator.of(context).pop(), strong: false),
        Expanded(
          child: Semantics(
            header: true,
            child: Text('Session length', textAlign: TextAlign.center, style: SessionText.weight(17, 600)),
          ),
        ),
        action('Done', _done, strong: true),
      ],
    );
  }

  List<Widget> _keypad() {
    void press(ExactEntry Function(ExactEntry) f) => setState(() => _entry = f(_entry));
    Widget key(String label, VoidCallback onPressed, {String? semanticLabel, IconData? icon}) => TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 52),
        backgroundColor: Colors.transparent,
        overlayColor: SessionColors.seaDeep,
        foregroundColor: SessionColors.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: SessionColors.rule),
        ),
      ),
      child: Semantics(
        label: semanticLabel,
        excludeSemantics: semanticLabel != null,
        child: icon != null ? Icon(icon, size: 22) : Text(label, style: SessionText.figures(22)),
      ),
    );
    return [
      Semantics(
        liveRegion: true,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _entry.readout,
            style: SessionText.clock(36, dimmed: false).copyWith(letterSpacing: 0),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _CellGrid(
        columns: 3,
        children: [
          for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0'])
            key(k, () => press((e) => e.press(k))),
          key('', () => press((e) => e.backspace()), semanticLabel: 'Delete last digit', icon: Icons.backspace_outlined),
        ],
      ),
    ];
  }

  Widget _fieldsRow() {
    Widget field(int index, String label) => SizedBox(
      width: 96,
      child: TextField(
        controller: _fields[index],
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
        style: SessionText.figures(22),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: SessionText.label(),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          filled: true,
          fillColor: SessionColors.raised,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: SessionColors.rule),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: SessionColors.ink),
          ),
        ),
        onChanged: (text) => setState(() {
          final v = int.tryParse(text) ?? 0;
          _entry = switch (index) {
            0 => _entry.withFields(hours: v),
            1 => _entry.withFields(minutes: v),
            _ => _entry.withFields(seconds: v),
          };
        }),
      ),
    );
    final total = _entry.isValid ? SessionLength.timed(_entry.duration).tileText : '0 s';
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        field(0, 'Hours'),
        field(1, 'Minutes'),
        field(2, 'Seconds'),
        Text('= $total', style: SessionText.weight(14, 400, color: SessionColors.dim)),
      ],
    );
  }
}

/// Lays children out in rows of [columns] equal cells.
class _CellGrid extends StatelessWidget {
  const _CellGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;
  static const gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        if (j > 0) cells.add(SizedBox(width: gap));
        cells.add(Expanded(child: i + j < children.length ? children[i + j] : const SizedBox()));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)));
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}
