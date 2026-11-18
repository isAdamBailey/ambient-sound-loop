/// The length picker: a bottom sheet on narrow layouts, a dialog on wide ones.
/// Nothing changes until Done; Cancel discards. Spec #9 §4.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../session/length.dart';
import 'controls.dart';
import 'theme.dart';

/// Shows the picker and returns the chosen length, or null on Cancel.
Future<SessionLength?> showLengthPicker(
  BuildContext context, {
  required SessionLength current,
  required bool wide,
}) {
  if (wide) {
    return showDialog<SessionLength>(
      context: context,
      barrierColor: const Color(0xB3000000),
      builder: (_) => Dialog(
        backgroundColor: SessionColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: SessionColors.border),
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
    backgroundColor: SessionColors.sheet,
    barrierColor: const Color(0xB3000000),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: SessionColors.border),
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
  late SessionLength _preset; // the selected preset, when not exact
  late bool _exact;
  late ExactEntry _entry;
  late final List<TextEditingController> _fields; // wide: hours, minutes, seconds

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    final isPreset = lengthPresets.any((p) => p.length == current);
    _preset = isPreset ? current : lengthPresets.first.length;
    _exact = !isPreset;
    _entry = ExactEntry.of(current.duration ?? Duration.zero);
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

  void _startExact() => setState(() {
    if (!_exact) {
      _entry = const ExactEntry.empty(); // a fresh entry, like a phone timer
      _syncFields();
    }
    _exact = true;
  });

  void _syncFields() {
    final values = [_entry.hours, _entry.minutes, _entry.seconds];
    for (var i = 0; i < 3; i++) {
      _fields[i].text = values[i].toString().padLeft(2, '0');
    }
  }

  void _done() {
    if (_exact && !_entry.isValid) return; // refused; the sheet says why
    Navigator.of(context).pop(_exact ? SessionLength.timed(_entry.duration) : _preset);
  }

  @override
  Widget build(BuildContext context) {
    final refused = _exact && !_entry.isValid;
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
            CellGrid(
              columns: widget.wide ? 4 : 3,
              children: [
                for (final p in lengthPresets)
                  ChoiceButton(
                    label: p.label,
                    fontSize: 15,
                    selected: !_exact && _preset == p.length,
                    onPressed: () => setState(() {
                      _exact = false;
                      _preset = p.length;
                    }),
                  ),
                ChoiceButton(label: 'Exact…', fontSize: 15, selected: _exact, onPressed: _startExact),
              ],
            ),
            if (_exact) ...[
              const SizedBox(height: 16),
              if (widget.wide) _fieldsRow() else ..._keypad(),
            ],
            if (refused) ...[
              const SizedBox(height: 14),
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: SessionColors.border),
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
        style: SessionText.weight(16, strong ? 600 : 400, color: strong ? SessionColors.primary : SessionColors.secondary),
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
    Widget key(String label, VoidCallback onPressed, {String? semanticLabel}) => TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 52),
        backgroundColor: SessionColors.surface,
        foregroundColor: SessionColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: SessionColors.border),
        ),
      ),
      child: Semantics(
        label: semanticLabel,
        excludeSemantics: semanticLabel != null,
        child: Text(label, style: SessionText.weight(22, 400)),
      ),
    );
    return [
      Semantics(
        liveRegion: true,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _entry.readout,
            style: SessionText.clock(34, dimmed: false).copyWith(letterSpacing: 0),
          ),
        ),
      ),
      const SizedBox(height: 12),
      CellGrid(
        columns: 3,
        children: [
          for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0'])
            key(k, () => press((e) => e.press(k))),
          key('⌫', () => press((e) => e.backspace()), semanticLabel: 'Delete last digit'),
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
        style: SessionText.weight(22, 400).copyWith(fontFeatures: SessionText.tabular.fontFeatures),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: SessionText.label(size: 12),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          filled: true,
          fillColor: SessionColors.surface,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: SessionColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: SessionColors.primary),
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
        Text('= $total', style: SessionText.weight(14, 400, color: SessionColors.secondary)),
      ],
    );
  }
}
