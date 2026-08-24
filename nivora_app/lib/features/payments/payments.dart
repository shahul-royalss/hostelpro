/// The in-app payment experience's public surface.
///
/// Two screens open something from here: the resident's "Pay rent" sheet, once the server has
/// credited the payment, and the warden's "Record payment" sheet, once `wd_record_payment` has
/// returned a row. Both get the same three things — build a [Receipt] from a server row, get
/// null if that row is not evidence, and call [showReceipt] with what they got.
///
/// Nothing else in this barrel is exported on purpose. The paper, the printer and the exporter
/// are implementation, and a caller that reached past [Receipt] could draw a receipt out of
/// values it chose itself, which is the one thing this feature exists to prevent.
library;

export 'receipt.dart' show Receipt, ReceiptChannel;
export 'receipt_export.dart'
    show
        ReceiptExportFailed,
        ReceiptExportResult,
        ReceiptExporter,
        ReceiptShareDismissed,
        ReceiptShared,
        receiptExporterProvider;
export 'receipt_screen.dart' show ReceiptScreen, showReceipt;
