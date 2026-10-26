/// Book a free demo (docs/self-signup-onboarding-spec.md, Flow 3; design canvas BookDemo.dc.html).
///
/// Shown once after the free-month sheet, with "Skip for now", and reusable from the owner's
/// More screen: `Navigator.push(context, BookDemoScreen.route())`.
///
/// The slot is an exact hour from 10 AM to 6 PM ASIA/KOLKATA, in the next 14 days and at least
/// two hours away, whatever zone this phone is in. The server enforces the same rule and its
/// sentence is shown if a slot goes stale while the screen is open.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/signup.dart';
import '../../../data/repositories/signup_repository.dart';
import '../../../shared/clay/clay.dart';
import '../../auth/auth_scaffold.dart';
import '../../common/form_parts.dart';
import '../signup_widgets.dart';

/// "Now" on the Asia/Kolkata wall clock, as a UTC-flagged DateTime whose fields ARE the
/// Kolkata date and time. India has no daylight saving, so the offset is constant.
DateTime kolkataNow([DateTime? clock]) =>
    (clock ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));

/// The bookable hours of one Kolkata day: 10:00 to 18:00, each at least 2 hours after [now].
List<DateTime> demoSlotsFor(DateTime day, DateTime now) => [
      for (var h = 10; h <= 18; h++)
        if (!DateTime.utc(day.year, day.month, day.day, h)
            .isBefore(now.add(const Duration(hours: 2))))
          DateTime.utc(day.year, day.month, day.day, h),
    ];

/// The next 14 Kolkata days that still have a bookable hour.
List<DateTime> demoDaysFrom(DateTime now) => [
      for (var i = 0; i < 14; i++)
        if (demoSlotsFor(DateTime.utc(now.year, now.month, now.day + i), now).isNotEmpty)
          DateTime.utc(now.year, now.month, now.day + i),
    ];

const _bedLabels = <String, String>{
  '1-20': '1–20',
  '21-50': '21–50',
  '51-100': '51–100',
  '100+': '100+',
};

class BookDemoScreen extends ConsumerStatefulWidget {
  const BookDemoScreen({super.key, this.onDone, this.pgName, this.city, this.clock});

  /// Called after booking or skipping. Null: the screen pops itself (the More entry).
  final VoidCallback? onDone;
  final String? pgName;
  final String? city;

  /// Tests pin the clock.
  final DateTime Function()? clock;

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const BookDemoScreen());

  @override
  ConsumerState<BookDemoScreen> createState() => _BookDemoScreenState();
}

class _BookDemoScreenState extends ConsumerState<BookDemoScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _pg;
  late final TextEditingController _city;
  DateTime? _day;
  DateTime? _slot;
  String? _beds;
  bool _busy = false;
  bool _booked = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  DateTime get _now => kolkataNow(widget.clock?.call());

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    _name = TextEditingController(text: session?.fullName ?? '');
    _phone = TextEditingController(text: session?.phone ?? '');
    _pg = TextEditingController(text: widget.pgName ?? '');
    _city = TextEditingController(text: widget.city ?? '');
    final days = demoDaysFrom(_now);
    _day = days.isEmpty ? null : days.first;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _pg, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  void _finish() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _fieldErrors = {
        if (_slot == null) 'slot_start': 'Pick a day and a time.',
        if (_beds == null) 'bed_band': 'Choose how many beds your PG has.',
      };
    });
    if (!(_form.currentState?.validate() ?? false) || _fieldErrors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(signupApiProvider).bookDemo(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            pgName: _pg.text.trim(),
            city: _city.text.trim(),
            bedBand: _beds!,
            slotKolkata: _slot!,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _booked = true;
      });
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (const {'name', 'phone', 'pg_name', 'city'}.contains(f.field)) {
          _fieldErrors = {f.field!: f.message};
          _form.currentState?.validate();
        } else if (f.field == 'slot_start' || f.field == 'bed_band') {
          _fieldErrors = {f.field!: f.message};
        } else {
          _error = f.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (_booked) {
      final when = DateFormat('EEE d MMM, h:mm a').format(_slot!);
      return SignupPage(
        children: [
          const SizedBox(height: Space.xxl),
          const Center(child: ClayIcon(ClayIcons.success, size: 120)),
          const SizedBox(height: Space.lg),
          AuthHeading(
            title: 'Demo booked',
            message: 'We will call you on ${_phone.text.trim()} on $when. '
                'You can cancel any time.',
          ),
          const SizedBox(height: Space.xl),
          BusyFilledButton(label: 'Go to my PG', onPressed: _finish),
        ],
      );
    }

    final now = _now;
    final days = demoDaysFrom(now);
    final slots = _day == null ? const <DateTime>[] : demoSlotsFor(_day!, now);
    String? server(String f) => _fieldErrors[f];
    Widget gap() => const SizedBox(height: Space.sm);

    return SignupPage(
      showSignOut: widget.onDone != null,
      onBack: widget.onDone == null ? () => Navigator.of(context).maybePop() : null,
      children: [
        const SizedBox(height: Space.md),
        const AuthHeading(
          title: 'Book a free demo',
          message: 'A free 20-minute video call. We set up your first PG with you.',
          icon: ClayIcons.calendar,
        ),
        GroupLabel('Pick a day', error: server('slot_start')),
        SizedBox(
          height: 64 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.xs),
            itemBuilder: (context, i) {
              final d = days[i];
              final on = _day == d;
              return ChoiceChip(
                selected: on,
                onSelected: _busy
                    ? null
                    : (_) => setState(() {
                          _day = d;
                          _slot = null;
                        }),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(DateFormat('EEE').format(d)),
                    Text(DateFormat('d MMM').format(d), style: t.textTheme.labelSmall),
                  ],
                ),
              );
            },
          ),
        ),
        const GroupLabel('Pick a time'),
        if (slots.isEmpty)
          Text('No times left on this day. Pick another day.', style: t.textTheme.bodyMedium)
        else
          ChoicePills<DateTime>(
            options: {for (final s in slots) s: DateFormat('h:mm a').format(s)},
            selected: _slot,
            enabled: !_busy,
            onSelected: (s) => setState(() => _slot = s),
          ),
        const GroupLabel('Your details'),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Your name'),
                validator: (v) =>
                    server('name') ??
                    ((v ?? '').trim().length < 2 ? 'Enter your name (2 to 80 characters).' : null),
              ),
              gap(),
              TextFormField(
                controller: _phone,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: const InputDecoration(labelText: 'Mobile number'),
                validator: (v) =>
                    server('phone') ??
                    (looksLikeIndianMobile(v ?? '') ? null : 'Enter a valid 10-digit mobile number.'),
              ),
              gap(),
              TextFormField(
                controller: _pg,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'PG name'),
                validator: (v) =>
                    server('pg_name') ??
                    ((v ?? '').trim().length < 2
                        ? 'Enter the PG name (2 to 120 characters).'
                        : null),
              ),
              gap(),
              TextFormField(
                controller: _city,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'City'),
                validator: (v) =>
                    server('city') ??
                    ((v ?? '').trim().length < 2 ? 'Enter the city (2 to 80 characters).' : null),
              ),
            ],
          ),
        ),
        GroupLabel('Beds in your PG', error: server('bed_band')),
        ChoicePills<String>(
          options: {for (final b in demoBedBands) b: _bedLabels[b] ?? b},
          selected: _beds,
          enabled: !_busy,
          onSelected: (b) => setState(() => _beds = b),
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.sm),
          FormNote(_error!),
        ],
        const SizedBox(height: Space.lg),
        BusyFilledButton(
          label: _slot == null
              ? 'Book my free demo'
              : 'Book for ${DateFormat('EEE d MMM, h:mm a').format(_slot!)}',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
        const SizedBox(height: Space.xxs),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _finish,
            child: Text(widget.onDone != null ? 'Skip for now' : 'Not now'),
          ),
        ),
        Text(
          "We call you on this number at the time you pick. It's free, and you can cancel any "
          'time.',
          textAlign: TextAlign.center,
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
