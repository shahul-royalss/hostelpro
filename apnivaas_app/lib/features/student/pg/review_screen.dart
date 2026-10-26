/// Tenant → Profile → Rate your PG (R5): 1–5 stars and an optional comment, one review per
/// tenant per PG, editable while they live there. The average is the server's.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/pg_profile.dart';
import '../../../data/repositories/pg_profile_repository.dart';
import '../../../data/repositories/signup_repository.dart' show SignupFailure;
import '../../../shared/clay/clay.dart';
import '../../common/form_parts.dart';
import '../stay_screens.dart' show stayErrorText;
import 'pg_profile_page.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key, required this.hostelId});

  final String hostelId;

  static Route<void> route(String hostelId) =>
      MaterialPageRoute<void>(builder: (_) => ReviewScreen(hostelId: hostelId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myReviewProvider);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(
            title: 'Rate your PG',
            subtitle: 'Help others choose',
            leading: HeaderBackButton(),
          ),
          Expanded(
            child: switch (mine) {
              AsyncData(:final value) => _Form(hostelId: hostelId, current: value),
              AsyncError(:final error) => ListView(
                  padding: const EdgeInsets.all(Space.md),
                  children: [
                    EmptyState.error(
                      message: stayErrorText(error),
                      onRetry: () => ref.invalidate(myReviewProvider),
                    ),
                  ],
                ),
              _ => ListView(
                  padding: const EdgeInsets.all(Space.md),
                  children: const [ListSkeleton(rows: 2, semanticLabel: 'Loading your review')],
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.hostelId, required this.current});
  final String hostelId;
  final MyReview? current;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late int _rating = widget.current?.rating ?? 0;
  late final _comment = TextEditingController(text: widget.current?.comment ?? '');
  String? _ratingError;
  String? _commentError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _ratingError = _rating < 1 ? 'Choose 1 to 5 stars.' : null;
      _commentError = _comment.text.trim().length > reviewCommentMax
          ? 'Keep the review under 300 characters.'
          : null;
      _error = null;
    });
    if (_ratingError != null || _commentError != null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(pgProfileApiProvider).saveReview(rating: _rating, comment: _comment.text);
      ref.invalidate(myReviewProvider);
      ref.invalidate(pgPublicProfileProvider(widget.hostelId));
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Thanks. Your review is saved.'),
      ));
      if (mounted) Navigator.of(context).maybePop();
    } on SignupFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        switch (f.field) {
          case 'rating':
            _ratingError = f.message;
          case 'comment':
            _commentError = f.message;
          default:
            _error = f.message;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = stayErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md, Space.huge),
      children: [
        Text('How is living here?', style: t.textTheme.titleMedium),
        const SizedBox(height: Space.xs),
        Wrap(
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: i == 1 ? '1 star' : '$i stars',
                isSelected: i <= _rating,
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _rating = i;
                          _ratingError = null;
                        }),
                iconSize: 40,
                icon: Icon(Icons.star_outline_rounded, color: t.colorScheme.onSurfaceVariant),
                selectedIcon: Icon(Icons.star_rounded, color: context.tones.warning),
              ),
          ],
        ),
        if (_ratingError != null) FormNote(_ratingError!),
        const SizedBox(height: Space.md),
        TextField(
          controller: _comment,
          enabled: !_busy,
          minLines: 3,
          maxLines: 6,
          maxLength: reviewCommentMax,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Your review (optional)',
            hintText: 'Food, cleanliness, safety, staff',
            errorText: _commentError,
            errorMaxLines: 3,
          ),
        ),
        if (_error != null) ...[const SizedBox(height: Space.xs), FormNote(_error!)],
        const SizedBox(height: Space.md),
        BusyFilledButton(
          label: widget.current == null ? 'Post review' : 'Update review',
          busy: _busy,
          onPressed: _save,
        ),
        const SizedBox(height: Space.md),
        const InfoNote(
          icon: Icons.visibility_outlined,
          message: 'People looking for a PG on Apnivaas see your first name, stars and review. '
              'The owner can read it but cannot change or delete it.',
        ),
        const SizedBox(height: Space.sm),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(PgProfilePage.route(widget.hostelId)),
            child: const Text('See your PG\'s page'),
          ),
        ),
      ],
    );
  }
}
