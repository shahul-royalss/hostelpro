/// THE CLAY KIT — every new-look shared widget, in one import.
///
///     import 'package:mobile/shared/clay/clay.dart';
///
/// docs/design-system.md says which widget is for what. No name here collides with a role kit
/// any more: the older widgets that shared one were deleted when nothing drew them, or renamed
/// for what makes them different (`WardenEmptyState` in warden_ui.dart, `StillSkeleton` in
/// student/widgets/common.dart), so any screen can import this library whole. Keep it that
/// way — a feature widget that needs its own version takes its own name.
library;

export 'app_header.dart';
export 'banners.dart';
export 'clay_icons.dart';
export 'empty_state.dart';
export 'list_row.dart';
export 'nav_bar.dart';
export 'pill_button.dart';
export 'pressable.dart';
export 'quick_actions.dart';
export 'section_header.dart';
export 'sheet.dart';
export 'skeleton.dart';
export 'stat_tile.dart';
export 'status_chip.dart';
export 'word_fit.dart';
