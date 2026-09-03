/// Everything the data layer returns, in one import.
///
/// Screens import this rather than reaching into individual files, so a model can be split or
/// merged without touching a single feature directory.
library;

export 'checkout.dart';
export 'complaint.dart';
export 'enums.dart';
export 'failure.dart';
export 'fee.dart';
export 'finance.dart';
export 'floor_plan.dart';
export 'hostel.dart';
export 'menu.dart';
export 'notice.dart';
export 'paged_result.dart';
export 'refund.dart';
// The row-shape coercers themselves stay private to the data layer; only the wire formatters
// and the error a shape mismatch raises are of any use outside it.
export 'parse.dart' show RowShapeError, toDateWire, toPeriodMonth;
export 'stats.dart';
export 'structure.dart';
export 'student.dart';
export 'task.dart';
