import 'package:flutter/material.dart';

/// A text field whose contents follow an external value without stealing an
/// in-progress edit.
///
/// The same rule `CoordinateField` applies to numbers, generalised to text:
/// the field re-syncs from [value] only while it does not have focus, so
/// state written from elsewhere (renaming a team rewrites every player's team,
/// for instance) never overwrites what someone is halfway through typing.
///
/// Commits on blur and on submit rather than on every keystroke, which keeps
/// one edit from producing a state update per character.
class SyncedTextField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onCommitted;
  final bool enabled;
  final TextInputType? keyboardType;
  final String? hintText;

  const SyncedTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onCommitted,
    this.enabled = true,
    this.keyboardType,
    this.hintText,
  });

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocusChange);

  @override
  void didUpdateWidget(SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit(_controller.text);
  }

  void _commit(String raw) {
    if (raw == widget.value) return;
    widget.onCommitted(raw);
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
      enabled: widget.enabled,
      keyboardType: widget.keyboardType,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: _commit,
    );
  }
}
