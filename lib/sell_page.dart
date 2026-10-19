import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db.dart';

class SellPage extends StatefulWidget {
  const SellPage({super.key});
  @override
  State<SellPage> createState() => _SellState();
}

class _SellState extends State<SellPage> {
  List<Item> items = [];
  List<Map<String, Object?>> recent = [];
  final cart = <Item, int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i = await DB.items();
    final r = await DB.recentSales();
    if (!mounted) return;
    final old = {for (final e in cart.entries) e.key.id: e.value};
    setState(() {
      items = i;
      recent = r;
      cart.clear(); // re-link the cart to the freshly loaded items
      for (final it in i) {
        final q = (old[it.id] ?? 0).clamp(0, it.qty).toInt();
        if (q > 0) cart[it] = q;
      }
    });
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  double get total => cart.entries.fold(0.0, (a, e) => a + e.key.price * e.value);

  void _add(Item it) {
    if ((cart[it] ?? 0) < it.qty) setState(() => cart[it] = (cart[it] ?? 0) + 1);
  }

  Future<void> _checkout() async {
    final t = total;
    await DB.checkout(cart);
    cart.clear();
    await _load();
    _snack('Sale recorded: ${money(t)}');
  }

  String _when(int ts) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts), n = DateTime.now();
    return (t.year == n.year && t.month == n.month && t.day == n.day) ? 'Today ${DateFormat.jm().format(t)}' : DateFormat.MMMd().add_jm().format(t);
  }

  Future<void> _undo(Map<String, Object?> sale) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Undo this sale?'),
        content: Text('${money(sale['total'] as num)} will be removed and the items returned to stock.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Undo sale')),
        ],
      ),
    );
    if (ok == true) {
      await DB.undoSale(sale['id'] as int);
      await _load();
      _snack('Sale undone');
    }
  }

  Future<void> _editSale(Map<String, Object?> sale) async {
    final lines = await DB.saleLines(sale['id'] as int);
    final qty = {for (final l in lines) l['id'] as int: l['qty'] as int};
    if (!mounted) return;
    Widget tile(Map<String, Object?> l, StateSetter set) {
      final id = l['id'] as int;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l['item_name'] as String),
        subtitle: Text(money(l['price'] as num)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: qty[id]! > 0 ? () => set(() => qty[id] = qty[id]! - 1) : null),
          SizedBox(width: 24, child: Text('${qty[id]}', textAlign: TextAlign.center)),
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => set(() => qty[id] = qty[id]! + 1)),
        ]),
      );
    }

    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final sum = lines.fold<double>(0, (a, l) => a + qty[l['id'] as int]! * (l['price'] as num).toDouble());
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Edit sale · ${_when(sale['ts'] as int)}', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final l in lines) tile(l, set),
              const Divider(),
              Text('New total: ${money(sum)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [
                TextButton(onPressed: () => Navigator.pop(ctx, 'undo'), child: Text('Undo whole sale', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
              ]),
            ]),
          );
        },
      ),
    );
    try {
      if (res == 'undo') await DB.undoSale(sale['id'] as int);
      if (res == 'save') await DB.updateSale(sale['id'] as int, qty);
      if (res != null) _snack(res == 'undo' ? 'Sale undone' : 'Sale updated');
    } on StateError catch (e) {
      _snack(e.message);
    }
    await _load();
  }

  Widget _itemCard(Item it) {
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
  }

  Widget _saleTile(Map<String, Object?> s) => ListTile(
    title: Text(s['summary'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(_when(s['ts'] as int)),
    onTap: () => _editSale(s),
    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(money(s['total'] as num), style: const TextStyle(fontWeight: FontWeight.w600)),
      IconButton(tooltip: 'Undo sale', icon: const Icon(Icons.undo), onPressed: () => _undo(s)),
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 80,
      leadingWidth: 100,
      centerTitle: true,
      title: const Text('Sell Inventory'),
      leading: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Image.asset('assets/images/guestgoodslogo.png', scale: 2),
      ),
    ),
    body: Column(children: [
      Expanded(
        child: CustomScrollView(slivers: [
          if (items.isEmpty)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Text('No items yet.', textAlign: TextAlign.center))),
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, childAspectRatio: 1.4, crossAxisSpacing: 10, mainAxisSpacing: 10),
              delegate: SliverChildBuilderDelegate((_, k) => _itemCard(items[k]), childCount: items.length),
            ),
          ),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Recent sales', style: Theme.of(context).textTheme.titleMedium))),
          if (recent.isEmpty)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 16), child: Text('No sales yet.')))
          else
            SliverList(delegate: SliverChildBuilderDelegate((_, k) => _saleTile(recent[k]), childCount: recent.length)),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ]),
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
