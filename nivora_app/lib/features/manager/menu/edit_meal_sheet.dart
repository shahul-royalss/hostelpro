library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/glass/glass.dart';
import '../data/manager_models.dart';
import '../data/manager_providers.dart';
import '../widgets/manager_ui.dart';

/// Write what is being served.
///
/// TABLE: public.menus, upserted on its own unique key (hostel_id, day_of_week, meal). The
/// manager is the ONLY role that may write it; everyone in the hostel may read it
/// (menus_select is `can_read_hostel`), which is why a careless save here is visible to every
/// resident immediately.
///
/// `items` is one free-text column, not a list of dishes. This form matches the column rather
/// than inventing structure the database cannot store: a chip editor here would have to
/// serialise its chips into that one string, and the web app — which writes the same rows —
/// would then show a resident a line of JSON.
Future<bool?> showEditMealSheet(
  BuildContext context, {
  required String hostelId,
  required MenuDay day,
  required Meal meal,
  required String? current,
}) {
  return showGlassSheet<bool>(
    context: context,
    builder: (_) => _EditMealSheet(
      hostelId: hostelId,
      day: day,
      meal: meal,
      current: current,
    ),
  );
}

class _EditMealSheet extends ConsumerStatefulWidget {
  const _EditMealSheet({
    required this.hostelId,
    required this.day,
    required this.meal,
    required this.current,
  });

  final String hostelId;
  final MenuDay day;
  final Meal meal;
  final String? current;

  @override
  ConsumerState<_EditMealSheet> createState() => _EditMealSheetState();
}

class _EditMealSheetState extends ConsumerState<_EditMealSheet> {
  late final TextEditingController _items = TextEditingController(text: widget.current ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _items.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final items = _items.text.trim();
    final ok = await runAction(
      context,
      success: items.isEmpty
          ? '${widget.meal.label} cleared for ${widget.day.label}'
          : '${widget.day.label} ${widget.meal.label.toLowerCase()} saved',
      // An empty string is a real value in this column (it is NOT NULL, default ''), so
      // clearing a meal is a save rather than a delete — and the row keeps its updated_at, so
      // the week still shows when somebody last touched it.
      action: () => ref.read(managerRepositoryProvider).saveMeal(
            hostelId: widget.hostelId,
            day: widget.day,
            meal: widget.meal,
            items: items,
          ),
    );

    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      refreshMenu(ref);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SheetBody(
      title: '${widget.day.label} ${widget.meal.label.toLowerCase()}',
      subtitle: 'Every resident of this hostel can read it',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _items,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What is being served',
              hintText: 'Idli, sambar, coconut chutney',
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Leave it empty to clear this meal.',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
