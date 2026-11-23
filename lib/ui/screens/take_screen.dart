import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app_state.dart';
import '../../domain/freshness.dart';
import '../../domain/gs1_parser.dart';
import '../../domain/models.dart';
import '../../domain/shelf_life.dart';
import '../../domain/shopping.dart' show nameKey;
import '../labels.dart';
import '../theme.dart';
import '../widgets/item_sheet.dart';

/// "I'm taking something from the fridge": find it by name or barcode and
/// take one piece or all of it, with undo.
class TakeScreen extends ConsumerStatefulWidget {
  const TakeScreen({super.key});

  @override
  ConsumerState<TakeScreen> createState() => _TakeScreenState();
}

class _TakeScreenState extends ConsumerState<TakeScreen> {
  final _query = TextEditingController();
  String? _ean;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: Text(ctx.l.takeScan)),
        body: MobileScanner(onDetect: (c) {
          final raw = c.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
          final gtin = raw == null ? null : parseBarcode(raw).gtin;
          if (gtin != null && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop(gtin);
        }),
      ),
    ));
    if (code != null) {
      setState(() {
        _ean = code;
        _query.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final now = DateTime.now();
    final q = nameKey(_query.text).substring(5);
    final items = sortByUrgency(ref.watch(itemsProvider).value ?? const [], now).where((i) {
      if (_ean != null) return i.ean == _ean;
      return q.isEmpty || nameKey(i.name).contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.takeTitle)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: InputDecoration(labelText: l.takeSearch, prefixIcon: const Icon(Icons.search), isDense: true),
                onChanged: (_) => setState(() => _ean = null),
              ),
            ),
            IconButton(tooltip: l.takeScan, icon: const Icon(Icons.qr_code_scanner), onPressed: _scan),
          ]),
        ),
        if (_ean != null) Chip(label: Text('EAN $_ean'), onDeleted: () => setState(() => _ean = null)),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(l.takeNotFound))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final color = GlebaColors.freshness(freshnessOf(item, now), Theme.of(context).brightness);
                    final one = item.unit == 'ks' && item.quantity > 1;
                    return ListTile(
                      leading: Text(categoryById(item.categoryId).emoji, style: const TextStyle(fontSize: 26)),
                      title: Text(item.name),
                      subtitle: Text(
                        '${relativeExpiry(l, item.expiryDate, now)}'
                        '${item.quantity > 1 ? ' · ${item.quantity.round()} ${item.unit}' : ''}',
                        style: TextStyle(color: color),
                      ),
                      onTap: () => showItemSheet(context, ref, item),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (one)
                          FilledButton.tonal(
                            onPressed: () => ItemActions.of(context, ref)?.finish(item, ItemStatus.consumed, quantity: 1),
                            child: Text(l.takeOne),
                          ),
                        const SizedBox(width: 6),
                        FilledButton(
                          onPressed: () => ItemActions.of(context, ref)?.finish(item, ItemStatus.consumed),
                          child: Text(one ? l.takeAll : '✓'),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
