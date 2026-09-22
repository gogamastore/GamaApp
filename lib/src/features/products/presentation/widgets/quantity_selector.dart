import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// --- REFACTORED to a StatefulWidget to handle direct text input ---
class QuantitySelector extends StatefulWidget {
  final int quantity;
  final int stock;
  final ValueChanged<int> onChanged;

  const QuantitySelector({
    super.key,
    required this.quantity,
    required this.stock,
    required this.onChanged,
  });

  @override
  State<QuantitySelector> createState() => _QuantitySelectorState();
}

class _QuantitySelectorState extends State<QuantitySelector> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.quantity.toString());
  }

  // Sync the controller if the parent widget rebuilds with a new quantity
  @override
  void didUpdateWidget(QuantitySelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.quantity != oldWidget.quantity) {
      _controller.text = widget.quantity.toString();
      // Move cursor to the end
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateAndSubmit(String value) {
    final int newQuantity = int.tryParse(value) ?? 0;
    if (newQuantity > widget.stock) {
      _controller.text = widget.stock.toString(); // Reset to max stock if exceeded
      widget.onChanged(widget.stock);
    } else if (newQuantity < 1 && widget.stock > 0) {
      _controller.text = '1'; // Reset to 1 if below
      widget.onChanged(1);
    } else {
      widget.onChanged(newQuantity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min, // ringkas agar muat di samping tombol
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(), // buang min-size 48x48
          visualDensity: VisualDensity.compact,
          onPressed: widget.quantity > 1 ? () => widget.onChanged(widget.quantity - 1) : null,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 42, // kolom angka yang ringkas
          child: TextFormField(
            controller: _controller,
            textAlign: TextAlign.center,
            // Ukuran huruf diperkecil sesuai permintaan.
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 5),
            ),
            onFieldSubmitted: _validateAndSubmit,
            onTapOutside: (_) => _validateAndSubmit(_controller.text),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(), // buang min-size 48x48
          visualDensity: VisualDensity.compact,
          onPressed: widget.quantity < widget.stock ? () => widget.onChanged(widget.quantity + 1) : null,
          color: theme.colorScheme.primary,
        ),
      ],
    );
  }
}
