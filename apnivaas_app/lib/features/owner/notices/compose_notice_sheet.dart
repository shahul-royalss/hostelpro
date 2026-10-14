library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/glass/glass.dart';
import '../widgets/states.dart';
import 'notice_draft.dart';
import 'notice_providers.dart';

/// Write a notice and post it to a hostel.
///
/// ── WHAT THIS SHEET DECIDES, AND WHAT IT DOES NOT ────────────────────────────────────────
///
/// It decides what to DRAW: which audience is selected, which field carries a message, whether
/// Post is tappable. None of that is a permission. `announcements_insert` re-checks all of it
/// — that the caller owns this hostel, that the hostel is writable under §4.4, and that
/// `author_user_id` really is `auth.uid()` — so a notice cannot be published under another
/// name even by a caller who edits the request. Deleting every check in this file would change
/// the error messages and nothing else.
///
/// ── POSTING NOTIFIES PEOPLE, AND THAT IS WHY THIS SHEET IS CAREFUL ───────────────────────
///
/// `app.announcements_after_insert` writes one `notifications` row per person in the audience,
/// in the same transaction as the insert. THE CLIENT MUST NOT ALSO DO THIS — the trigger is the
/// only fan-out, it is measured (four notices to a hostel of manager + warden + one resident
/// produced exactly six rows, the author excluded from all of them), and a second pass from
/// here would double every one of them.
///
/// It is also why the confirm/`_busy` handling matters more than it would on an ordinary form:
/// a double tap is not a duplicate row, it is a second buzz on everybody's phone. The button
/// is disabled while in flight, [PopScope] refuses a drag-to-dismiss mid-request, and the
/// repository's `guardWrite` carries the "check before posting again" sentence for the one case
/// nobody can resolve from here — a request that was sent and never answered.
Future<bool?> showComposeNoticeSheet(
  BuildContext context, {
  required String hostelId,
  String? hostelName,
}) {
  return showGlassSheet<bool>(
    context: context,
    builder: (_) => _ComposeNoticeSheet(hostelId: hostelId, hostelName: hostelName),
  );
}

class _ComposeNoticeSheet extends ConsumerStatefulWidget {
  const _ComposeNoticeSheet({required this.hostelId, required this.hostelName});

  final String hostelId;
  final String? hostelName;

  @override
  ConsumerState<_ComposeNoticeSheet> createState() => _ComposeNoticeSheetState();
}

class _ComposeNoticeSheetState extends ConsumerState<_ComposeNoticeSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  NoticeAudience _audience = NoticeAudience.all;
  bool _busy = false;

  /// Field messages, keyed by the names [validateNoticeDraft] uses.
  Map<String, String> _errors = const {};

  /// Anything that was not about the input: offline, refused, subscription lapsed, a write
  /// whose outcome nobody can state. Drawn with the owner's own error card.
  AppFailure? _failure;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  NoticeDraft get _draft =>
      NoticeDraft(title: _title.text, body: _body.text, audience: _audience);

  /// Clears one field's message — it described the value that has just changed.
  void _touched(String field) {
    if (!_errors.containsKey(field) && _failure == null) return;
    setState(() {
      _errors = {
        for (final e in _errors.entries)
          if (e.key != field) e.key: e.value,
      };
      _failure = null;
    });
  }

  void _pickAudience(NoticeAudience audience) {
    if (_busy || audience == _audience) return;
    // No message is cleared here: neither field error is about who the notice is addressed to,
    // and wiping "Give the notice a title" because the owner changed their mind about the
    // audience would hide the thing still standing between them and posting.
    setState(() => _audience = audience);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final draft = _draft;

    // Local validation first, so a typo costs nothing. It refuses only what the server would
    // also refuse — except the blank-after-trim case, which Postgres would happily store and
    // then notify the whole hostel about. See validateNoticeDraft.
    final errors = validateNoticeDraft(draft);
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _failure = null;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errors = const {};
      _failure = null;
    });

    try {
      await ref.read(noticeWritesProvider).create(
            hostelId: widget.hostelId,
            title: draft.trimmedTitle,
            body: draft.trimmedBody,
            audience: draft.audience,
          );
      if (!mounted) return;

      // The noticeboard, the dashboard's activity feed and every warmed copy of this list read
      // the same family instance, so one invalidation refreshes all of them. Done BEFORE the
      // pop so the screen behind is already rebuilding as the sheet slides away.
      ref.invalidate(noticesProvider(widget.hostelId));
      setState(() => _busy = false);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = AppFailure.from(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.88 - media.padding.top;

    return PopScope(
      // A drag-to-dismiss mid-request would abandon a post that is already in flight — and if
      // it succeeded, the owner would be looking at a sheet that told them nothing while every
      // phone in the hostel buzzed.
      canPop: !_busy,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEW NOTICE',
                        style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.primary),
                      ),
                      const SizedBox(height: Space.xxs / 2),
                      Text(
                        'Post a notice',
                        style: t.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: Space.xxs),
            Text(
              widget.hostelName == null
                  ? 'Everyone you choose gets a notification straight away.'
                  : 'Posted to ${widget.hostelName}. Everyone you choose gets a notification '
                      'straight away.',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _title,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      // Hard-capped at the column's own ceiling so the field cannot hold a
                      // value the database would reject. The validator still checks it: the
                      // formatter counts the untrimmed string, and what gets stored is trimmed.
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(noticeTitleMaxLength),
                      ],
                      onChanged: (_) => _touched('title'),
                      decoration: InputDecoration(
                        labelText: 'Title',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        hintText: 'What the notice is about',
                        errorText: _errors['title'],
                      ),
                    ),
                    const SizedBox(height: Space.sm),

                    TextField(
                      controller: _body,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.sentences,
                      // A notice is a paragraph, not a line. Enter inserts a newline rather
                      // than submitting — posting is the button's job, and a notice sent by a
                      // stray Enter key is a notification nobody can recall.
                      keyboardType: TextInputType.multiline,
                      minLines: 4,
                      maxLines: 8,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(noticeBodyMaxLength),
                      ],
                      onChanged: (_) => _touched('body'),
                      decoration: InputDecoration(
                        labelText: 'Notice',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        alignLabelWithHint: true,
                        hintText: 'The dates, the details, what to do',
                        errorText: _errors['body'],
                      ),
                    ),
                    const SizedBox(height: Space.md),

                    Text('WHO SEES IT', style: t.textTheme.labelSmall),
                    const SizedBox(height: Space.xs),
                    for (final audience in noticeAudienceChoices) ...[
                      if (audience != noticeAudienceChoices.first)
                        const SizedBox(height: Space.xs),
                      NoticeAudienceCard(
                        audience: audience,
                        selected: audience == _audience,
                        enabled: !_busy,
                        onTap: () => _pickAudience(audience),
                      ),
                    ],

                    if (_failure != null) ...[
                      const SizedBox(height: Space.md),
                      // No retry button: pressing Post again IS the retry, and a second control
                      // that does the same thing beside it is a second way to notify everyone
                      // twice.
                      ErrorNote(error: _failure!, compact: true),
                    ],

                    const SizedBox(height: Space.md),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      child: _busy
                          ? const SizedBox(
                              height: IconSize.md,
                              width: IconSize.md,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Post notice'),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'A notice cannot be edited into a second notification — posting is what '
                      'notifies people, so it only happens once.',
                      style: t.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One choosable audience.
///
/// PUBLIC because owner_notices_test.dart drives the targeting through it: the test taps the
/// "Wardens" card and asserts the repository was called with [NoticeAudience.warden], which is
/// the only part of targeting this app decides. (Which rows each role then reads is
/// `announcements_select`'s, and is measured against the live database rather than in Dart.)
class NoticeAudienceCard extends StatelessWidget {
  const NoticeAudienceCard({
    super.key,
    required this.audience,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final NoticeAudience audience;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  IconData get _icon => switch (audience) {
        NoticeAudience.all => Icons.groups_rounded,
        NoticeAudience.students => Icons.people_alt_rounded,
        NoticeAudience.warden => Icons.shield_rounded,
        NoticeAudience.manager => Icons.manage_accounts_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    // Same anatomy as StaffRoleCard in add_staff_sheet.dart: the choice is carried by the
    // radio and the title's colour, not by a second fill or a thicker edge. The two sheets
    // sit one tap apart in the same tab, so they read as one control or as two.
    final accent = selected ? scheme.primary : scheme.outline;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${audience.label}. ${noticeAudienceDescription(audience)}',
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: FlatSurface(
          weight: GlassWeight.regular,
          borderRadius: Radii.rControl,
          padding: const EdgeInsets.all(Space.sm),
          onTap: enabled ? onTap : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ToneBadge(icon: _icon, tone: accent, tinted: selected),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audience.label,
                      style: t.textTheme.titleMedium
                          ?.copyWith(color: selected ? scheme.primary : null),
                    ),
                    const SizedBox(height: Space.xxs / 2),
                    Text(
                      noticeAudienceDescription(audience),
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: IconSize.lg,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
