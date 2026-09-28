import 'package:flutter/material.dart';

/// A generic "type to search, tap to pick, or add new" field used for
/// the Project, Task and Office pickers.
class SearchablePickerItem {
  final int id;
  final String label;
  const SearchablePickerItem({required this.id, required this.label});
}

/// What the picker came back with.
///
/// [isNew] means the user asked to create something rather than picking an
/// existing row, and [query] carries whatever they had typed so the creation
/// dialog can start from it instead of making them type it twice.
class PickerResult {
  final int id;
  final String query;

  const PickerResult(this.id, this.query);

  const PickerResult.newItem(this.query) : id = -1;

  bool get isNew => id == -1;
}

Future<PickerResult?> showSearchablePicker({
  required BuildContext context,
  required String title,
  required List<SearchablePickerItem> items,
  required String addNewLabel,
  required String searchHint,
  required String emptyLabel,
}) {
  return showModalBottomSheet<PickerResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return _SearchablePickerSheet(
        title: title,
        items: items,
        addNewLabel: addNewLabel,
        searchHint: searchHint,
        emptyLabel: emptyLabel,
      );
    },
  );
}

class _SearchablePickerSheet extends StatefulWidget {
  final String title;
  final List<SearchablePickerItem> items;
  final String addNewLabel;
  final String searchHint;
  final String emptyLabel;

  const _SearchablePickerSheet({
    required this.title,
    required this.items,
    required this.addNewLabel,
    required this.searchHint,
    required this.emptyLabel,
  });

  @override
  State<_SearchablePickerSheet> createState() => _SearchablePickerSheetState();
}

class _SearchablePickerSheetState extends State<_SearchablePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where((i) => i.label.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final typed = _query.trim();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(child: Text(widget.emptyLabel))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return ListTile(
                            title: Text(item.label),
                            onTap: () => Navigator.of(context)
                                .pop(PickerResult(item.id, '')),
                          );
                        },
                      ),
              ),
              // Always offered, not only while searching: adding a task or a
              // project belongs in this flow, without a separate trip to the
              // Tasks or Projects screen.
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(typed.isEmpty
                        ? widget.addNewLabel
                        : '${widget.addNewLabel}: "$typed"'),
                    onPressed: () =>
                        Navigator.of(context).pop(PickerResult.newItem(typed)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
