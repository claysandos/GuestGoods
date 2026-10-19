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
    version: 2,
    onCreate: (d, v) async {
      await d.execute('CREATE TABLE items(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, cost REAL, price REAL, qty INTEGER, reorder INTEGER)');
      await d.execute('CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER)');
      await d.execute('CREATE TABLE sale_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER, item_name TEXT, qty INTEGER, price REAL, cost REAL, item_id INTEGER)');
    },
    onUpgrade: (d, oldV, newV) async {
      if (oldV < 2) await d.execute('ALTER TABLE sale_lines ADD COLUMN item_id INTEGER');
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
        await t.insert('sale_lines', {'sale_id': sid, 'item_id': e.key.id, 'item_name': e.key.name, 'qty': e.value, 'price': e.key.price, 'cost': e.key.cost});
        await t.rawUpdate('UPDATE items SET qty = qty - ? WHERE id = ?', [e.value, e.key.id]);
      }
    });
  }

  static Future<List<Map<String, Object?>>> recentSales({int limit = 15}) async => (await db).rawQuery(
      "SELECT s.id, s.ts, SUM(l.qty * l.price) AS total, GROUP_CONCAT(l.item_name || ' × ' || l.qty, ', ') AS summary "
          'FROM sales s JOIN sale_lines l ON l.sale_id = s.id GROUP BY s.id ORDER BY s.ts DESC LIMIT ?',
      [limit]);

  static Future<List<Map<String, Object?>>> saleLines(int saleId) async =>
      (await db).query('sale_lines', where: 'sale_id=?', whereArgs: [saleId], orderBy: 'id');

  // Puts units back in stock (n > 0) or takes them out (n < 0). Matches by item id, falling back to name for older sales.
  static Future<void> _restock(DatabaseExecutor t, Map<String, Object?> l, int n) async {
    if (l['item_id'] != null) {
      await t.rawUpdate('UPDATE items SET qty = qty + ? WHERE id = ?', [n, l['item_id']]);
    } else {
      await t.rawUpdate('UPDATE items SET qty = qty + ? WHERE LOWER(name) = ?', [n, (l['item_name'] as String).toLowerCase()]);
    }
  }

  /// Undo a whole sale: returns all its items to stock and deletes it.
  static Future<void> undoSale(int saleId) async {
    final d = await db;
    await d.transaction((t) async {
      for (final l in await t.query('sale_lines', where: 'sale_id=?', whereArgs: [saleId])) {
        await _restock(t, l, l['qty'] as int);
      }
      await t.delete('sale_lines', where: 'sale_id=?', whereArgs: [saleId]);
      await t.delete('sales', where: 'id=?', whereArgs: [saleId]);
    });
  }

  /// Change quantities on a sale (keyed by sale_lines.id). Stock is adjusted by the difference.
  /// A sale whose lines all reach zero is deleted. Throws StateError if stock can't cover an increase.
  static Future<void> updateSale(int saleId, Map<int, int> newQty) async {
    final d = await db;
    await d.transaction((t) async {
      for (final l in await t.query('sale_lines', where: 'sale_id=?', whereArgs: [saleId])) {
        final old = l['qty'] as int, nq = newQty[l['id'] as int] ?? old;
        if (nq == old) continue;
        if (nq > old) {
          final r = await t.query('items',
              columns: ['qty'],
              where: l['item_id'] != null ? 'id=?' : 'LOWER(name)=?',
              whereArgs: [l['item_id'] ?? (l['item_name'] as String).toLowerCase()]);
          if (r.isEmpty || (r.first['qty'] as int) < nq - old) throw StateError('Not enough stock for ${l['item_name']}');
        }
        await _restock(t, l, old - nq);
        if (nq <= 0) {
          await t.delete('sale_lines', where: 'id=?', whereArgs: [l['id']]);
        } else {
          await t.update('sale_lines', {'qty': nq}, where: 'id=?', whereArgs: [l['id']]);
        }
      }
      final left = Sqflite.firstIntValue(await t.rawQuery('SELECT COUNT(*) FROM sale_lines WHERE sale_id=?', [saleId])) ?? 0;
      if (left == 0) await t.delete('sales', where: 'id=?', whereArgs: [saleId]);
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