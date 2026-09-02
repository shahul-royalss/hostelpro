library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

// ═══════════════════════════════════════════════════════════════════════════════════════════
// THE PASSWORD POLICY, AND THE METER THAT DRAWS IT — WRITTEN ONCE
// ═══════════════════════════════════════════════════════════════════════════════════════════
//
// This file is an EXTRACTION, not a new rule. Every string, every predicate and every number
// below was lifted verbatim out of change_password_screen.dart, which still uses them and is
// still the screen the router sends a forced change to. Nothing about that path changed.
//
// It moved here because a THIRD screen now sets a password — the one a recovery link lands on
// (reset_password_screen.dart), where the person cannot supply their current password because
// forgetting it is the reason they are there. Three screens, one server rule; the alternative
// was a second copy of the policy, and a second copy is how a meter starts saying "GOOD" about
// a password the server then refuses. That failure is named in the doc on
// [PasswordStrengthMeter] as the specific thing this design exists to avoid, so duplicating it
// in order to add a screen would have been the one change this code most explicitly warns
// against.

/// The floor the web app, every form here and `AuthController.changePassword` all enforce.
const passwordMinLength = 8;

/// The ceiling. Not a strength rule — a storage guard, and the one reason a password can be
/// refused for being too much rather than too little.
const passwordMaxLength = 200;

/// THE FIVE RULES, WRITTEN ONCE.
///
/// This enum is the only place the policy is expressed. [validateNewPassword] walks it to
/// produce the message under the field, and [PasswordStrengthMeter] walks the same list to draw
/// the bars — so the meter cannot say "good" about a password the form then refuses, which is
/// the specific failure a strength indicator invites. There is no scoring model here and there
/// must not be one: an entropy estimate (zxcvbn and friends) rates passwords on an axis nothing
/// in this system enforces, and a bar that fills for reasons the validator ignores is a lie
/// with a progress bar attached.
///
/// [requirement] is what the meter says is still missing. [failure] is what the validator says
/// when the form is submitted; it is the web app's own wording, kept verbatim so a user who
/// sets their password on the website and on the phone meets the same sentences.
///
/// ═══ 2026-09-01: THE LIST GREW, BECAUSE THE SERVER'S LIST WAS ALWAYS LONGER ═══
/// It held three rules — length, a letter, a digit — and Supabase Auth holds five. Measured
/// against the live project by walking a real account's password through PUT /auth/v1/user:
///
///     "correct1horse"   -> 422 weak_password (characters)
///     "Correct1horse"   -> 422 weak_password (characters)
///     "correct1horse!"  -> 422 weak_password (characters)
///     "CORRECT1HORSE!"  -> 422 weak_password (characters)
///     "Correct1horse!"  -> 200
///
/// The project requires one character from each of lower case, upper case, digits and symbols.
/// So the meter filled to "GOOD", the form accepted the password, and the server refused it —
/// which is precisely the failure the doc on [PasswordStrengthMeter] says a strength indicator
/// invites and this design exists to avoid. Worse, the sentence that came back said "at least 6
/// characters" while the screen had just insisted on eight.
///
/// `length` stays at 8 even though GoTrue would take 6: a client may be STRICTER than the
/// server without lying to anybody, and 8 is the number the web app, the reset flow and every
/// screen here have always shown.
enum PasswordRule {
  length('$passwordMinLength or more characters', 'Use at least $passwordMinLength characters'),
  letter('a letter', 'Include at least one letter'),
  digit('a number', 'Include at least one number'),
  upper('a capital letter', 'Include at least one capital letter'),
  symbol('a symbol', 'Include at least one symbol, like ! or @');

  const PasswordRule(this.requirement, this.failure);

  final String requirement;
  final String failure;

  bool isMetBy(String value) => switch (this) {
        PasswordRule.length => value.length >= passwordMinLength,
        // `letter` is the LOWER-CASE rule. It kept its old name and its old sentence because
        // both are already on people's screens, and because a password with a capital and no
        // small letter is the rarer mistake to have to explain.
        PasswordRule.letter => RegExp(r'[a-z]').hasMatch(value),
        PasswordRule.digit => RegExp(r'\d').hasMatch(value),
        PasswordRule.upper => RegExp(r'[A-Z]').hasMatch(value),
        // Anything that is not a letter, a digit or whitespace. Deliberately wider than the set
        // GoTrue names in its error text, because that set is its own default and a password
        // built from a character just outside it would be refused HERE, where the message is
        // written for a person, rather than there.
        PasswordRule.symbol => RegExp(r'[^A-Za-z0-9\s]').hasMatch(value),
      };
}

/// Mirrors lib/validators/auth.ts, by walking [PasswordRule] rather than by restating it. The
/// order is the order the rules are declared in, which is why a three-character password is
/// told about its length before it is told about its digits.
String? validateNewPassword(String? v) {
  final value = v ?? '';
  // Checked first because it is the only rule a LONGER password can fail; everything below asks
  // for more, and reporting "use at least 8" to someone who typed 300 would be absurd.
  if (value.length > passwordMaxLength) return 'That password is too long';
  for (final rule in PasswordRule.values) {
    if (!rule.isMetBy(value)) return rule.failure;
  }
  return null;
}

/// The password strength indicator the design puts on 4:89 — labelled bars.
///
/// ── IT COUNTS RULES, NOT ENTROPY, AND THAT IS THE WHOLE DESIGN ───────────────────────────
///
/// One bar per rule in [PasswordRule], filled when that rule is satisfied. So the meter is full
/// at exactly the moment the form would accept the password, and empty-ish at exactly the
/// moment it would not. The alternative — a character-class or dictionary score — would light
/// three bars for `correcthorsebattery` (long, mixed, memorable, genuinely strong) while the
/// validator refuses it for having no digit, and a user watching a full green meter get
/// rejected learns not to trust the meter.
///
/// The words are a human summary of the same count; the line underneath is the precise truth,
/// naming what is still missing. Nothing here is advisory: every requirement it lists is
/// enforced on submit and again by the server.
///
/// WHAT THIS CANNOT KNOW: Supabase also refuses passwords that appear in a breach corpus, and
/// refuses reusing the previous one. Those verdicts only exist server-side — there is no local
/// corpus and the old password is never in this client's hands — so the meter cannot anticipate
/// them and does not pretend to. The controller turns both into their own sentences under the
/// button.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;

    final tooLong = password.length > passwordMaxLength;
    final unmet = PasswordRule.values.where((r) => !r.isMetBy(password)).toList();
    final met = tooLong ? 0 : PasswordRule.values.length - unmet.length;

    // The tone ladder. Muted while the field is empty, because a red meter over a field nobody
    // has typed in yet is the interface telling somebody off for doing nothing. Counted against
    // [PasswordRule.values.length] rather than against a literal, so adding a rule moves the
    // meter with the policy instead of quietly capping it.
    final (Color accent, String label) = switch (met) {
      _ when password.isEmpty => (tones.muted, 'Password strength'),
      _ when tooLong => (tones.error, 'Too long'),
      _ when met == PasswordRule.values.length => (tones.success, 'Good'),
      _ when met == PasswordRule.values.length - 1 => (tones.warning, 'Almost'),
      _ => (tones.error, 'Weak'),
    };

    final String hint;
    if (tooLong) {
      hint = 'Use $passwordMaxLength characters or fewer.';
    } else if (password.isEmpty) {
      hint = 'Needs ${PasswordRule.values.map((r) => r.requirement).join(', ')}.';
    } else if (unmet.isEmpty) {
      hint = 'Meets every rule this app enforces.';
    } else {
      hint = 'Still needed: ${unmet.map((r) => r.requirement).join(', ')}.';
    }

    return Semantics(
      container: true,
      label: 'Password strength',
      value: '$label. $hint',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < PasswordRule.values.length; i++) ...[
                  if (i > 0) const SizedBox(width: Space.xxs),
                  Expanded(
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      curve: Motion.move,
                      height: Space.xxs,
                      decoration: BoxDecoration(
                        // The design's meter track is the hairline as a filled channel — the
                        // same token theme.dart gives LinearProgressIndicator.
                        color: i < met ? accent : t.colorScheme.outlineVariant,
                        borderRadius: Radii.rPill,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Space.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(hint, style: t.textTheme.bodySmall),
                ),
                const SizedBox(width: Space.xs),
                // labelSmall is the design's chip step, 10/600. A TextStyle cannot uppercase, so
                // the string does.
                Text(
                  label.toUpperCase(),
                  style: t.textTheme.labelSmall?.copyWith(color: accent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
