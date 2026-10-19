import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'db.dart';

class _Row {
  bool on = true;
  String name;
  int qty = 1;
  double cost, price;
  _Row(this.name, this.cost, this.price);
}

const _sample = '''E 1234567 KS ALMOND 3LB 14.99 A
1450033 TRAVEL MUG 12.49 A
/1450033 2.00- A
1623450 SEA SALT CARAMEL 9.99 A
7788123 BEACH TOWEL 3PK 19.99 A
SUBTOTAL 57.46
TAX 3.12''';

class ImportPage extends StatefulWidget {
  const ImportPage({super.key});
  @override
  State<ImportPage> createState() => _ImportState();
}

class _ImportState extends State<ImportPage> {
  final text = TextEditingController();
  final markup = TextEditingController(text: '60');
  List<_Row> rows = [];
  bool busy = false;

  Future<void> _scan(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src);
    if (x == null) return;
    setState(() => busy = true);
    final rec = TextRecognizer();
    try {
      final r = await rec.processImage(InputImage.fromFilePath(x.path));
      text.text = r.text;
      _parse();
    } finally {
      await rec.close();
      if (mounted) setState(() => busy = false);
    }
  }

  /// Costco lines look like "E 1234567 KS ALMOND 3LB 14.99 A"; discounts like "/1234567 2.00-".
  void _parse() {
    final item = RegExp(r'^(?:E\s+)?(\d{5,8})\s+(.+?)\s+(\d+\.\d{2})\s*[A-Z]?$');
    final disc = RegExp(r'^/\s*(\d{5,8})\s+(\d+\.\d{2})-');
    final m = (double.tryParse(markup.text) ?? 0) / 100;
    final codes = <String, int>{};
    final totals = <double>[];
    final names = <String>[];
    for (final line in text.text.split('\n').map((l) => l.trim())) {
      final d = disc.firstMatch(line);
      if (d != null && codes.containsKey(d.group(1))) {
        totals[codes[d.group(1)]!] -= double.parse(d.group(2)!);
        continue;
      }
      final i = item.firstMatch(line);
      if (i != null) {
        codes[i.group(1)!] = totals.length;
        names.add(i.group(2)!.split(' ').map((w) => w.length > 2 ? w[0] + w.substring(1).toLowerCase() : w).join(' '));
        totals.add(double.parse(i.group(3)!));
      }
    }
    setState(() => rows = [
          for (var k = 0; k < names.length; k++)
            _Row(names[k], totals[k], (totals[k] * (1 + m)).ceilToDouble() - 0.01)
        ]);
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No item lines found. Check the text and try again.')));
    }
  }

  Future<void> _commit() async {
    final chosen = rows.where((r) => r.on && r.name.trim().isNotEmpty).toList();
    for (final r in chosen) {
      await DB.addOrRestock(r.name.trim(), r.qty, r.cost / r.qty, r.price);
    }
    setState(() => rows = []);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${chosen.length} items to stock')));
  }

  Widget _num(String label, String init, void Function(String) f) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextFormField(
              initialValue: init,
              decoration: InputDecoration(labelText: label, isDense: true),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: f),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(toolbarHeight: 80, leadingWidth: 100, centerTitle: true, title: const Text('Scan Inventory'), leading: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Image.asset('assets/images/guestgoodslogo.png', scale: 2),
      ),),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: busy ? null : () => _scan(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: const Text('Scan'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => _scan(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('Choose photo'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: text, maxLines: 5, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Receipt text (edit if the scan missed anything)')),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 120, child: TextField(controller: markup, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Markup %', isDense: true))),
            const Spacer(),
            TextButton(onPressed: () => text.text = _sample, child: const Text('Try sample')),
            FilledButton(onPressed: _parse, child: const Text('Read items')),
          ]),
          if (busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          for (final r in rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  Row(children: [
                    Checkbox(value: r.on, onChanged: (v) => setState(() => r.on = v ?? true)),
                    Expanded(child: TextFormField(initialValue: r.name, decoration: const InputDecoration(labelText: 'Item name', isDense: true), onChanged: (v) => r.name = v)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _num('Qty', '${r.qty}', (v) => r.qty = (int.tryParse(v) ?? 1).clamp(1, 9999)),
                    _num('Total cost', r.cost.toStringAsFixed(2), (v) => r.cost = double.tryParse(v) ?? r.cost),
                    _num('Sell price', r.price.toStringAsFixed(2), (v) => r.price = double.tryParse(v) ?? r.price),
                  ]),
                ]),
              ),
            ),
          if (rows.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Rename items to what guests will see. An existing name adds to its stock.')),
            FilledButton(onPressed: _commit, child: const Text('Add checked items to stock')),
          ],
        ]),
      );
}
