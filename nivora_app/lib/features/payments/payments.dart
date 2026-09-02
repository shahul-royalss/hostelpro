/// The in-app payment experience's public surface.
///
/// [PayRentButton] is how a resident pays: it opens a Razorpay order the SERVER priced, hands it
/// to the native sheet, and then waits for the ledger rather than believing the callback. Read
/// pay_rent.dart before changing anything about it — the reason it never writes is the whole
/// security property of the money path.
///
/// Two screens open a receipt from here: the resident's rent card, once the server has credited
/// the payment, and the warden's "Record payment" sheet, once `wd_record_payment` has
/// returned a row. Both get the same three things — build a [Receipt] from a server row, get
/// null if that row is not evidence, and call [showReceipt] with what they got.
///
/// Nothing else in this barrel is exported on purpose. The paper, the printer and the exporter
/// are implementation, and a caller that reached past [Receipt] could draw a receipt out of
/// values it chose itself, which is the one thing this feature exists to prevent.
library;

export 'pay_rent.dart' show PayRentButton, PayRentResult, payRent;
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
