import 'package:flutter/material.dart';
import 'db.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InvState();
}

class _InvState extends State<InventoryPage> {
  List<Item> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i = await DB.items();
    if (mounted) setState(() => items = i);
  }

  Future<void> _edit([Item? it]) async {
    final n = TextEditingController(text: it?.name ?? '');
    final c = TextEditingController(text: it?.cost.toStringAsFixed(2) ?? '');
    final p = TextEditingController(text: it?.price.toStringAsFixed(2) ?? '');
    final q = TextEditingController(text: '${it?.qty ?? 0}');
    final r = TextEditingController(text: '${it?.reorder ?? 3}');
    Widget f(String l, TextEditingController t, {bool number = true}) => TextField(
        controller: t,
        decoration: InputDecoration(labelText: l),
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text);
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(it == null ? 'Add item' : 'Edit item'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [f('Name', n, number: false), f('Cost', c), f('Price', p), f('In stock', q), f('Reorder at', r)])),
        actions: [
          if (it != null) TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('Delete')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (res == 'delete') await DB.deleteItem(it!.id!);
    if (res == 'save' && n.text.trim().isNotEmpty) {
      await DB.saveItem(Item(
          id: it?.id,
          name: n.text.trim(),
          cost: double.tryParse(c.text) ?? 0,
          price: double.tryParse(p.text) ?? 0,
          qty: int.tryParse(q.text) ?? 0,
          reorder: int.tryParse(r.text) ?? 0));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(toolbarHeight: 80, leadingWidth: 100, centerTitle: true, title: const Text('Inventory'), leading: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Image.asset('assets/images/guestgoodslogo.png', scale: 2),
      ),),
        floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
        body: items.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Nothing here yet. Tap + to add your first item.'),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () async { await DB.addDemoItems(); _load(); }, child: const Text('Add demo items')),
                ]),
              )
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, k) {
                  final it = items[k];
                  final low = it.qty <= it.reorder;
                  return ListTile(
                    title: Text(it.name),
                    subtitle: Text('Cost ${money(it.cost)} · Price ${money(it.price)}'),
                    trailing: Text('${it.qty}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: low ? Theme.of(context).colorScheme.error : null)),
                    onTap: () => _edit(it),
                  );
                }),
      );
}
