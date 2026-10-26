/// The receipt screen: a machine prints the resident's receipt, and they take it away.
///
/// Reached only with a [Receipt] in hand, and a [Receipt] can only be built from a row the
/// server wrote — see receipt.dart. There is deliberately no route that can be opened with an
/// id and left to fetch its own data: that shape is how a receipt screen ends up rendering a
/// spinner, then a payment that turned out not to have settled.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../shared/clay/app_header.dart';
import '../common/form_parts.dart';
import '../common/refresh.dart' show snackbarErrorInk;
import 'receipt.dart';
import 'receipt_export.dart';
import 'receipt_printer.dart';

/// Print a receipt and hand it over.
///
/// A full page rather than a sheet: the paper is 500-odd pixels of it and a modal that tall is
/// a page wearing a costume.
Future<void> showReceipt(BuildContext context, Receipt receipt) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ReceiptScreen(receipt: receipt),
    ),
  );
}

class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key, required this.receipt});

  final Receipt receipt;

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  /// Attached to the [RepaintBoundary] around the paper. The export reads the pixels through
  /// it, which is why the picture the resident sends is the picture they were shown.
  final _paperKey = GlobalKey();

  /// Anchors the iPad share popover to the button that opened it.
  final _shareButtonKey = GlobalKey();

  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    final result = await ref.read(receiptExporterProvider).share(
          paperKey: _paperKey,
          receipt: widget.receipt,
          origin: _originOf(_shareButtonKey),
        );

    if (!mounted) return;
    setState(() => _sharing = false);

    switch (result) {
      // Silence on success, on purpose. The share sheet has already shown the resident what it
      // did, and the plugin cannot always tell whether they sent the file or saved it — so a
      // confirmation here would either repeat the OS or claim something unverified.
      case ReceiptShared():
      case ReceiptShareDismissed():
        break;
      case ReceiptExportFailed(:final message):
        // The tone is carried by an icon, NOT by the bar's fill. `ApnivaasColors.error` was
        // painted here as a background under the snackbar theme's own light content colour,
        // which measures 2.4:1 — the one place in the resident app where a failure was harder
        // to read than a success. The snackbar's text is measured against the bar itself, and
        // so is the glyph's red ([snackbarErrorInk]: the bar is the inverse of the page).
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, size: IconSize.md, color: snackbarErrorInk(context)),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(message)),
            ],
          ),
          duration: Motion.readMessage,
        ));
    }
  }

  /// The button's rectangle in global coordinates, or null before it has been laid out.
  Rect? _originOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The forest header of every sub-page, with a close rather than a back arrow: this is
          // a full-screen dialog over whatever the resident was looking at.
          AppHeader(
            leading: HeaderIconButton(
              icon: Icons.close_rounded,
              label: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: 'Your receipt',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md,
                  Space.xxl + MediaQuery.paddingOf(context).bottom),
              child: ReceiptPrinterStage(
                receipt: widget.receipt,
                paperKey: _paperKey,
                actions: (context, phase, tear) => _Actions(
                  phase: phase,
                  sharing: _sharing,
                  onTear: tear,
                  onShare: _share,
                  shareButtonKey: _shareButtonKey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the resident can do, and when.
///
/// Sharing is NOT gated behind tearing the sheet off. The tear is a flourish; a person who
/// wants the file should never have to discover a gesture to reach it.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.phase,
    required this.sharing,
    required this.onTear,
    required this.onShare,
    required this.shareButtonKey,
  });

  final PrinterPhase phase;
  final bool sharing;
  final VoidCallback onTear;
  final VoidCallback onShare;
  final GlobalKey shareButtonKey;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    if (!phase.isComplete) {
      return Column(
        children: [
          Text('Printing your receipt', style: t.textTheme.titleMedium),
          const SizedBox(height: Space.xxs),
          Text(
            'One moment.',
            style: t.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    // Keeps its forest while it prepares the image, so the spinner in it reads as working
    // rather than as a button that has gone grey and dead.
    final shareButton = BusyFilledButton(
      key: shareButtonKey,
      label: 'Share or save',
      icon: Icons.ios_share_rounded,
      busy: sharing,
      busyLabel: 'Preparing',
      onPressed: onShare,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        // Stretch: the design's actions run the width of the block they are in, rather than
        // hugging their labels in the middle of a 420-point column.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (phase == PrinterPhase.printed) ...[
            OutlinedButton.icon(
              onPressed: onTear,
              icon: const Icon(Icons.content_cut_rounded, size: IconSize.md),
              label: const Text('Tear off'),
            ),
            const SizedBox(height: Space.sm),
          ],
          shareButton,
          const SizedBox(height: Space.xs),
          Text(
            // Says exactly what the button produces. "Share" alone leaves people guessing
            // whether they are about to send a link, a page, or their whole rent history.
            'Sends the receipt as a PNG image — message it to someone, or save it to your '
            'phone from the same menu.',
            style: t.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
