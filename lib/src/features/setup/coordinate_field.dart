import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A numeric metre input for one receiver coordinate.
///
/// Dragging and typing both write to the same state, so the field must accept
/// external updates *without* stealing or corrupting an in-progress edit.
/// The rule applied here: the text is re-synced from [value] only while the
/// field does not have focus. While the user is typing, their text wins.
class CoordinateField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  /// Suffix shown after the number.
  final String unit;

  const CoordinateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.unit = 'm',
  });

  @override
  State<CoordinateField> createState() => _CoordinateFieldState();
}

class _CoordinateFieldState extends State<CoordinateField> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocusChange);

  static String _format(double v) => v.toStringAsFixed(2);

  @override
  void didUpdateWidget(CoordinateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only follow external changes (e.g. a drag) when not being edited.
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = _format(widget.value);
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      // Normalise whatever was typed back to canonical form on blur, and
      // discard unparseable input rather than silently writing garbage.
      _commit(_controller.text);
      _controller.text = _format(widget.value);
    }
  }

  void _commit(String raw) {
    final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (parsed != null && parsed != widget.value) widget.onChanged(parsed);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.unit,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(
          decimal: true, signed: true),
      inputFormatters: [
        // Metres, optionally negative (receivers sit outside the court).
        FilteringTextInputFormatter.allow(RegExp(r'^-?[0-9]*[.,]?[0-9]*')),
      ],
      textInputAction: TextInputAction.done,
      onSubmitted: _commit,
    );
  }
}
