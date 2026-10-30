/// R4.1: a resident's monthly rent and due day — the fields (shared with the join-request
/// accept sheet) and the editor that calls `wd_set_tenant_rent`. The server validates both
/// values and decides from which month the new rent applies; paid history never changes.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/tenant_admin.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../../data/repositories/tenant_admin_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../common/form_parts.dart';
import '../data/warden_providers.dart';

const defaultRentDueDay = 5;
const rentRangeMessage = 'Enter the monthly rent (₹1 to ₹10,00,000).';
const dueDayRangeMessage = 'Choose a due day from 1 to 28.';

/// 1 to 10,00,000, at most 2 decimals; null otherwise.
double? parseRent(String raw) {
  final t = raw.replaceAll(',', '').trim();
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(t)) return null;
  final v = double.parse(t);
  return v >= 1 && v <= 1000000 ? v : null;
}

/// 1 to 28; null when empty or out of range.
int? parseDueDay(String raw) {
  final v = int.tryParse(raw.trim());
  return v != null && v >= 1 && v <= 28 ? v : null;
}

/// `2026-12` → `December 2026`.
String appliesFromLabel(String yyyyMm) {
  final d = DateTime.tryParse('$yyyyMm-01');
  return d == null ? yyyyMm : DateFormat('MMMM yyyy').format(d);
}

/// Monthly rent (₹) and due day of month, side by side; stacked when text is large.
class RentFields extends StatelessWidget {
  const RentFields({
    super.key,
    required this.rent,
    required this.dueDay,
    this.rentError,
    this.dueDayError,
    this.enabled = true,
    this.dueDayHelper = '1 to 28 of each month',
  });

  final TextEditingController rent;
  final TextEditingController dueDay;
  final String? rentError;
  final String? dueDayError;
  final bool enabled;
  final String dueDayHelper;

  @override
  Widget build(BuildContext context) {
    final rentField = TextField(
      key: const ValueKey('rent-amount'),
      controller: rent,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: 'Monthly rent',
        prefixText: '₹ ',
        hintText: 'e.g. 6500',
        errorText: rentError,
        errorMaxLines: 3,
      ),
    );
    final dueField = TextField(
      key: const ValueKey('rent-due-day'),
      controller: dueDay,
      enabled: enabled,
      keyboardType: TextInputType.number,
      maxLength: 2,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: 'Due day',
        helperText: dueDayHelper,
        helperMaxLines: 2,
        counterText: '',
        errorText: dueDayError,
        errorMaxLines: 3,
      ),
    );
    final big = MediaQuery.textScalerOf(context).scale(14) > 17;
    if (big) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [rentField, const SizedBox(height: Space.sm), dueField],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: rentField),
        const SizedBox(width: Space.sm),
        Expanded(flex: 2, child: dueField),
      ],
    );
  }
}

/// Sets or changes the rent. Returns the server's answer, or null when backed out. The caller
/// shows "New rent applies from …" ([appliesFromLabel]).
Future<RentChange?> showRentEditorSheet(
  BuildContext context, {
  required String studentId,
  required String studentName,
  required double currentFee,
  int? currentDueDay,
}) =>
    showApnivaasSheet<RentChange>(
      context: context,
      title: currentFee > 0 ? 'Change rent' : 'Set monthly rent',
      subtitle: currentFee > 0
          ? 'For $studentName. The new rent applies from the next unbilled month; payments '
              'already recorded keep their amount.'
          : '$studentName has no rent yet, so no dues are created until you set it.',
      builder: (_) => _RentEditor(
        studentId: studentId,
        currentFee: currentFee,
        currentDueDay: currentDueDay,
      ),
    );

class _RentEditor extends ConsumerStatefulWidget {
  const _RentEditor({required this.studentId, required this.currentFee, this.currentDueDay});
  final String studentId;
  final double currentFee;
  final int? currentDueDay;

  @override
  ConsumerState<_RentEditor> createState() => _RentEditorState();
}

class _RentEditorState extends ConsumerState<_RentEditor> {
  late final _rent = TextEditingController(
      text: widget.currentFee > 0
          ? (widget.currentFee % 1 == 0
              ? widget.currentFee.toStringAsFixed(0)
              : widget.currentFee.toStringAsFixed(2))
          : '');
  // Empty means "keep": the resident's own day, or the PG's when they have none.
  late final _dueDay = TextEditingController(text: widget.currentDueDay?.toString() ?? '');
  String? _rentError;
  String? _dueError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _rent.dispose();
    _dueDay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final fee = parseRent(_rent.text);
    final day = parseDueDay(_dueDay.text);
    setState(() {
      _rentError = fee == null ? rentRangeMessage : null;
      _dueError = _dueDay.text.trim().isNotEmpty && day == null ? dueDayRangeMessage : null;
      _error = null;
    });
    if (_rentError != null || _dueError != null) return;
    setState(() => _busy = true);
    try {
      final change = await ref
          .read(tenantAdminApiProvider)
          .setRent(widget.studentId,
              monthlyFee: fee!, dueDay: day == widget.currentDueDay ? null : day);
      refreshAfterRentChange(ref, widget.studentId);
      if (mounted) Navigator.of(context).pop(change);
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        switch (f.field) {
          case 'monthly_fee':
            _rentError = f.message;
          case 'due_day':
            _dueError = f.message;
          default:
            _error = f.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RentFields(
              rent: _rent,
              dueDay: _dueDay,
              rentError: _rentError,
              dueDayError: _dueError,
              enabled: !_busy,
              dueDayHelper: widget.currentDueDay == null
                  ? "1 to 28. Leave empty for the PG's due day."
                  : '1 to 28 of each month',
            ),
            if (_error != null) ...[const SizedBox(height: Space.xs), FormNote(_error!)],
            const SizedBox(height: Space.md),
            BusyFilledButton(
              label: widget.currentFee > 0 ? 'Save rent' : 'Set rent',
              busy: _busy,
              busyLabel: 'Saving…',
              onPressed: _save,
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
}

/// Everything that shows a rent or a due.
void refreshAfterRentChange(WidgetRef ref, String studentId) {
  ref.invalidate(studentProvider(studentId));
  ref.invalidate(tenantProfileProvider(studentId));
  ref.invalidate(rentlessResidentsProvider);
  refreshResidents(ref);
  ref.invalidate(feeLedgerProvider);
  ref.invalidate(hostelStatsProvider);
}

/// Opens the editor and, on a save, says from when the new rent applies.
Future<RentChange?> editRent(
  BuildContext context, {
  required String studentId,
  required String studentName,
  required double currentFee,
  int? currentDueDay,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final change = await showRentEditorSheet(context,
      studentId: studentId,
      studentName: studentName,
      currentFee: currentFee,
      currentDueDay: currentDueDay);
  if (change == null) return null;
  final from = change.appliesFrom;
  messenger?.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: Motion.readMessage,
    content: Text(from == null
        ? 'Rent saved for $studentName.'
        : 'Rent saved. The new rent applies from ${appliesFromLabel(from)}.'),
  ));
  return change;
}
