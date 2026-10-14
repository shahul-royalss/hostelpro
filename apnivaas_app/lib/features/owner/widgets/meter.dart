/// Moved to `shared/meter.dart`.
///
/// [ProportionMeter] depends on nothing but Flutter and the design tokens, and the shared
/// dashboard tile needs it — a widget in shared/ cannot import a feature folder, which is the
/// third time that dependency has pointed the wrong way in this rework (AccountAvatar and the
/// staff profile sheet were the other two).
///
/// This file stays as a re-export rather than being deleted so the ten existing call sites in
/// features/owner and features/manager keep working. Deleting it would have turned a two-line
/// move into a ten-file edit for no benefit.
library;

export '../../../shared/meter.dart';
