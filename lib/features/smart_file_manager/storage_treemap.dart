import 'package:flutter/material.dart';
import '../../core/models.dart';

class StorageTreemap extends StatelessWidget {
  const StorageTreemap({
    super.key,
    required this.categories,
    required this.onSelect,
  });
  final Map<String, int> categories;
  final void Function(String) onSelect;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 220,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final values = categories.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final boxes = <Widget>[];
        void split(List<MapEntry<String, int>> items, Rect rectangle) {
          if (items.isEmpty || rectangle.width <= 4 || rectangle.height <= 4) {
            return;
          }
          if (items.length == 1) {
            final entry = items.single;
            boxes.add(
              Positioned.fromRect(
                rect: rectangle.deflate(2),
                child: Material(
                  color: Colors
                      .primaries[categories.keys.toList().indexOf(entry.key) %
                          Colors.primaries.length]
                      .shade800,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelect(entry.key),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          '${entry.key}\n${bytes(entry.value)}',
                          maxLines: 3,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            return;
          }
          final midpoint = (items.length / 2).ceil();
          final left = items.take(midpoint).toList(),
              right = items.skip(midpoint).toList();
          final total = items.fold<int>(0, (n, e) => n + e.value);
          final fraction = left.fold<int>(0, (n, e) => n + e.value) / total;
          if (rectangle.width >= rectangle.height) {
            split(
              left,
              Rect.fromLTWH(
                rectangle.left,
                rectangle.top,
                rectangle.width * fraction,
                rectangle.height,
              ),
            );
            split(
              right,
              Rect.fromLTWH(
                rectangle.left + rectangle.width * fraction,
                rectangle.top,
                rectangle.width * (1 - fraction),
                rectangle.height,
              ),
            );
          } else {
            split(
              left,
              Rect.fromLTWH(
                rectangle.left,
                rectangle.top,
                rectangle.width,
                rectangle.height * fraction,
              ),
            );
            split(
              right,
              Rect.fromLTWH(
                rectangle.left,
                rectangle.top + rectangle.height * fraction,
                rectangle.width,
                rectangle.height * (1 - fraction),
              ),
            );
          }
        }

        split(values, Offset.zero & constraints.biggest);
        return Stack(children: boxes);
      },
    ),
  );
}
