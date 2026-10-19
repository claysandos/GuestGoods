import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

String money(num n) => NumberFormat.simpleCurrency().format(n);

class Item {
  int? id;
  String name;
  double cost, price;
  int qty, reorder;
  Item({this.id, required this.name, required this.cost, required this.price, this.qty = 0, this.reorder = 3});
  factory Item.fromMap(Map<String, Object?> m) => Item(
      id: m['id'] as int,
      name: m['name'] as String,
      cost: (m['cost'] as num).toDouble(),
      price: (m['price'] as num).toDouble(),
      qty: m['qty'] as int,
      reorder: m['reorder'] as int);
  Map<String, Object?> toMap() => {'id': id, 'name': name, 'cost': cost, 'price': price, 'qty': qty, 'reorder': reorder};
}

class DB {
  static Database? _db;
  static Future<Database> get db async => _db ??= await openDatabase(
        join(await getDatabasesPath(), 'guestgoods.db'),
        version: 1,
        onCreate: (d, v) async {
          await d.execute('CREATE TABLE items(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, cost REAL, price REAL, qty INTEGER, reorder INTEGER)');
          await d.execute('CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER)');
          await d.execute('CREATE TABLE sale_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER, item_name TEXT, qty INTEGER, price REAL, cost REAL)');
        },
      );

  static Future<List<Item>> items() async =>
      (await (await db).query('items', orderBy: 'name COLLATE NOCASE')).map(Item.fromMap).toList();

  static Future<void> saveItem(Item i) async {
    final d = await db;
    if (i.id == null) {
      await d.insert('items', i.toMap());
    } else {
      await d.update('items', i.toMap(), where: 'id=?', whereArgs: [i.id]);
    }
  }

  static Future<void> deleteItem(int id) async => (await db).delete('items', where: 'id=?', whereArgs: [id]);

  /// Records one sale and reduces stock, all-or-nothing.
  static Future<void> checkout(Map<Item, int> cart) async {
    final d = await db;
    await d.transaction((t) async {
      final sid = await t.insert('sales', {'ts': DateTime.now().millisecondsSinceEpoch});
      for (final e in cart.entries) {
        await t.insert('sale_lines', {'sale_id': sid, 'item_name': e.key.name, 'qty': e.value, 'price': e.key.price, 'cost': e.key.cost});
        await t.rawUpdate('UPDATE items SET qty = qty - ? WHERE id = ?', [e.value, e.key.id]);
      }
    });
  }

  static Future<List<Map<String, Object?>>> monthLines(DateTime m) async {
    final a = DateTime(m.year, m.month).millisecondsSinceEpoch;
    final b = DateTime(m.year, m.month + 1).millisecondsSinceEpoch;
    return (await db).rawQuery(
        'SELECT s.ts, l.sale_id, l.item_name, l.qty, l.price, l.cost FROM sale_lines l JOIN sales s ON s.id = l.sale_id WHERE s.ts >= ? AND s.ts < ? ORDER BY s.ts',
        [a, b]);
  }

  /// Receipt import: matching name adds to stock, otherwise creates the item.
  static Future<void> addOrRestock(String name, int qty, double cost, double price) async {
    final d = await db;
    final ex = await d.query('items', where: 'LOWER(name)=?', whereArgs: [name.toLowerCase()]);
    if (ex.isEmpty) {
      await d.insert('items', {'name': name, 'cost': cost, 'price': price, 'qty': qty, 'reorder': 3});
    } else {
      await d.rawUpdate('UPDATE items SET qty = qty + ?, cost = ? WHERE id = ?', [qty, cost, ex.first['id']]);
    }
  }

  static Future<void> addDemoItems() async {
    for (final r in [
      ['Souvenir Mug', 4.50, 12.99, 12],
      ['Beach Towel', 6.66, 17.99, 8],
      ['Sea Salt Caramels', 3.33, 8.99, 20],
      ['Hotel Logo Tote', 5.00, 14.99, 10],
      ['Sunscreen SPF 50', 4.25, 11.99, 6],
      ['Postcard Pack', 1.20, 4.99, 25],
    ]) {
      await addOrRestock(r[0] as String, r[3] as int, r[1] as double, r[2] as double);
    }
  }
}
