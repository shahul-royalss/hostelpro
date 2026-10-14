library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';
import 'legal_documents.dart';

/// Renders one [LegalDocument] as readable prose.
///
/// Shared deliberately between the consent gate and the always-available reader, so that what a
/// person agrees to and what they can go back and re-read afterwards are the SAME WIDGET over
/// the SAME DATA. Two renderers would be two documents the day one of them was edited.
///
/// The text is selectable. Somebody who wants to keep a copy of what they agreed to, quote a
/// clause in an email, or paste the grievance address into their mail app should not have to
/// retype it off a screen.
class LegalDocumentView extends StatelessWidget {
  const LegalDocumentView({super.key, required this.document, this.padding});

  final LegalDocument document;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: padding ?? EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(document.title, style: t.textTheme.headlineSmall),
                const SizedBox(height: Space.xxs),
                Text(document.tagline, style: t.textTheme.bodyMedium),
                const SizedBox(height: Space.xxs),
                Text(
                  'Version $kLegalVersion · $kLegalVersionLabel',
                  style: t.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          for (final section in document.sections) ...[
            const SizedBox(height: Space.lg),
            Padding(
              padding: padding ?? EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(section.heading, style: t.textTheme.titleMedium),
                  const SizedBox(height: Space.xs),
                  for (final block in section.blocks) _block(context, block),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Total over the sealed [LegalBlock], so a block type added later is a compile error here
  /// rather than a paragraph that silently renders as nothing.
  Widget _block(BuildContext context, LegalBlock block) {
    final t = Theme.of(context);
    return switch (block) {
      Para(:final text) => Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Text(text, style: t.textTheme.bodyMedium),
        ),
      Bullets(:final items) => Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xxs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('·  ', style: t.textTheme.bodyMedium),
                      Expanded(child: Text(item, style: t.textTheme.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      // A two-column shape drawn as stacked pairs rather than a Table: a real table of this
      // width on a phone either scrolls sideways or squeezes the right column into a ribbon,
      // and every row here is "a label and a sentence" rather than data to be compared down a
      // column.
      Rows(:final entries) => Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.term,
                        style: t.textTheme.labelLarge
                            ?.copyWith(color: t.colorScheme.primary),
                      ),
                      const SizedBox(height: Space.xxs),
                      Text(entry.detail, style: t.textTheme.bodyMedium),
                    ],
                  ),
                ),
            ],
          ),
        ),
    };
  }
}

/// Both documents, readable at any time — not only at the gate.
///
/// WHY THIS EXISTS SEPARATELY FROM THE GATE. A policy you can only read in the second before
/// you agree to it is not a policy anyone has actually read. Play's own guidance assumes the
/// documents stay reachable, and a resident who wants to check what happens to their ID scan
/// four months after joining has no gate left to look at. Reachable from every role's header,
/// next to Security — see features/shell/role_shell.dart and each role's own shell.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, this.initial});

  /// Which document to open on. Null starts on the privacy policy, which is the one people
  /// come looking for.
  final String? initial;

  static Route<void> route({String? initial}) =>
      MaterialPageRoute<void>(builder: (_) => LegalScreen(initial: initial));

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late int _index = _resolveInitial();

  /// An unknown id falls back to the first document rather than throwing. A caller asking for
  /// something this build does not have is a wrong argument, not a reason to show nothing.
  int _resolveInitial() {
    if (widget.initial == null) return 0;
    final i = kLegalDocuments.indexWhere((d) => d.id == widget.initial);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final document = kLegalDocuments[_index];

    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Privacy')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
            child: SegmentedButton<int>(
              segments: [
                for (var i = 0; i < kLegalDocuments.length; i++)
                  ButtonSegment<int>(value: i, label: Text(kLegalDocuments[i].title)),
              ],
              selected: {_index},
              onSelectionChanged: (s) => setState(() => _index = s.first),
              showSelectedIcon: false,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxl),
              children: [
                LegalDocumentView(document: document),
                const SizedBox(height: Space.xl),
                // The published copy, printed rather than linked. `url_launcher` is not a
                // dependency of this project (pubspec.yaml records why for its neighbours), and
                // adding one to open text the app is already showing would be a poor trade. The
                // string is selectable inside LegalDocumentView's SelectionArea above.
                FlatSurface(
                  padding: const EdgeInsets.all(Space.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Published copy', style: t.textTheme.labelSmall),
                      const SizedBox(height: Space.xxs),
                      SelectableText(document.url, style: t.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Open the documents from anywhere. Mirrors `openSecurity(context)`.
void openLegal(BuildContext context, {String? initial}) {
  Navigator.of(context).push(LegalScreen.route(initial: initial));
}
