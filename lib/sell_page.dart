import 'package:flutter/material.dart';
import 'db.dart';

class SellPage extends StatefulWidget {
  const SellPage({super.key});
  @override
  State<SellPage> createState() => _SellState();
}

class _SellState extends State<SellPage> {
  List<Item> items = [];
  final cart = <Item, int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i = await DB.items();
    if (mounted) setState(() => items = i);
  }

  double get total => cart.entries.fold(0.0, (a, e) => a + e.key.price * e.value);

  void _add(Item it) {
    if ((cart[it] ?? 0) < it.qty) setState(() => cart[it] = (cart[it] ?? 0) + 1);
  }

  Future<void> _checkout() async {
    final t = total;
    await DB.checkout(cart);
    cart.clear();
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sale recorded: ${money(t)}')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(toolbarHeight: 80, leadingWidth: 100, centerTitle: true, title: const Text('Sell Inventory'), leading: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Image.asset('assets/images/guestgoodslogo.png', scale: 2),
        ),),
        body: Column(children: [
          Expanded(
            child: items.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No items yet.', textAlign: TextAlign.center)))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, childAspectRatio: 1.4, crossAxisSpacing: 10, mainAxisSpacing: 10),
                    itemCount: items.length,
                    itemBuilder: (_, k) {
                      final it = items[k];
                      final out = it.qty - (cart[it] ?? 0) <= 0;
                      return Card(
                        child: InkWell(
                          onTap: out ? null : () => _add(it),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Opacity(
                              opacity: out ? .4 : 1,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const Spacer(),
                                Text('${money(it.price)} · ${it.qty} in stock', style: Theme.of(context).textTheme.bodySmall),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }),
          ),
          if (cart.isNotEmpty)
            Material(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Wrap(spacing: 6, children: [
                    for (final e in cart.entries)
                      InputChip(
                        label: Text('${e.key.name} × ${e.value}'),
                        onDeleted: () => setState(() => cart[e.key] == 1 ? cart.remove(e.key) : cart[e.key] = cart[e.key]! - 1),
                      )
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: _checkout, child: Text('Complete sale · ${money(total)}'))),
                ]),
              ),
            ),
        ]),
      );
}
