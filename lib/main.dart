import 'package:flutter/material.dart';
import 'sell_page.dart';
import 'inventory_page.dart';
import 'import_page.dart';
import 'report_page.dart';

void main() => runApp(const GuestGoods());

class GuestGoods extends StatelessWidget {
  const GuestGoods({super.key});
  static const seed = Color(0x000000);
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GuestGoods',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed)),
        darkTheme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark)),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        // Pages are rebuilt on every tab switch, so they always reload fresh data.
        body: [const SellPage(), const InventoryPage(), const ImportPage(), const ReportPage()][i],
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => setState(() => i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Sell'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Inventory'),
            NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Scan'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Reports'),
          ],
        ),
      );
}
