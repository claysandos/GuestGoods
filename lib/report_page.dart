import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});
  @override
  State<ReportPage> createState() => _ReportState();
}

class _ReportState extends State<ReportPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, Object?>> lines = [];
  List<Item> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await DB.monthLines(month);
    final i = await DB.items();
    if (mounted) setState(() { lines = l; items = i; });
  }

  void _shift(int d) {
    month = DateTime(month.year, month.month + d);
    _load();
  }

  Widget _stat(String label, String value) => SizedBox(
        width: 150,
        child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]))),
      );

  @override
  Widget build(BuildContext context) {
    double rev = 0, cost = 0;
    int units = 0;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final daily = List<double>.filled(days, 0);
    final by = <String, List<double>>{};
    final sales = <Object?>{};
    for (final l in lines) {
      final q = l['qty'] as int, p = (l['price'] as num).toDouble(), c = (l['cost'] as num).toDouble();
      rev += q * p; cost += q * c; units += q;
      sales.add(l['sale_id']);
      daily[DateTime.fromMillisecondsSinceEpoch(l['ts'] as int).day - 1] += q * p;
      final b = by.putIfAbsent(l['item_name'] as String, () => <double>[0, 0, 0]);
      b[0] += q; b[1] += q * p; b[2] += q * (p - c);
    }
    final top = by.entries.toList()..sort((a, b) => b.value[1].compareTo(a.value[1]));
    final peak = daily.fold<double>(1, (a, b) => b > a ? b : a);
    final low = items.where((i) => i.qty <= i.reorder).toList();
    final margin = rev > 0 ? ' (${((rev - cost) / rev * 100).round()}%)' : '';

    return Scaffold(
      appBar: AppBar(toolbarHeight: 80, leadingWidth: 100, centerTitle: true, title: const Text('Monthly Report'), leading: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Image.asset('assets/images/guestgoodslogo.png', scale: 2),
      ),),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          Text(DateFormat.yMMMM().format(month), style: Theme.of(context).textTheme.titleLarge),
          IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
        if (lines.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No sales recorded this month.', textAlign: TextAlign.center)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _stat('Revenue', money(rev)),
          _stat('Gross Profit$margin', money(rev - cost)),
          _stat('Items Sold', '$units'),
          _stat('Sales', '${sales.length}'),
          _stat('Inventory Cost', money(items.fold<double>(0, (a, i) => a + i.qty * i.cost))),
        ]),
        const SizedBox(height: 16),
        Text('Daily revenue', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 110,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final v in daily)
              Expanded(child: Tooltip(message: money(v), child: Container(margin: const EdgeInsets.symmetric(horizontal: 1), height: 2 + 108 * v / peak, color: Theme.of(context).colorScheme.primary))),
          ]),
        ),
        const SizedBox(height: 16),
        Text('Best sellers', style: Theme.of(context).textTheme.titleMedium),
        for (final e in top)
          ListTile(dense: true, title: Text(e.key), subtitle: Text('${e.value[0].toInt()} sold · profit ${money(e.value[2])}'), trailing: Text(money(e.value[1]))),
        const SizedBox(height: 16),
        Text('Needs restocking', style: Theme.of(context).textTheme.titleMedium),
        if (low.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('All items in stock.')),
        for (final i in low)
          ListTile(dense: true, title: Text(i.name), trailing: Text('${i.qty} left', style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}
