library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../shared/clay/app_header.dart';
import '../../shared/glass/glass.dart';
import 'legal_documents.dart';

/// Renders one [LegalDocument] as readable prose.
///
/// Shared deliberately between the consent gate and the always-available reader, so that what a
/// person agrees to and what they can go back and re-read afterwards are the SAME WIDGET over
/// the SAME DATA. Two renderers would be two documents the day one of them was edited.
///
/// Set as reading text, not as interface: the paragraphs are the type scale's reading step
/// (Manrope 15/22) in the body ink rather than the 13px supporting grey, because somebody is
/// being asked to read every word of this, and each section opens on an Outfit heading so the
/// eye can find its way back to "what happens to my ID scan".
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
                Text(
                  document.title,
                  style: t.textTheme.headlineSmall?.copyWith(fontFeatures: const []),
                ),
                const SizedBox(height: Space.xxs),
                Text(document.tagline, style: t.textTheme.bodyMedium),
                const SizedBox(height: Space.xs),
                Text(
                  'Version $kLegalVersion · $kLegalVersionLabel',
                  style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          for (final section in document.sections) ...[
            const SizedBox(height: Space.xl),
            Padding(
              padding: padding ?? EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(section.heading, style: context.textRoles.tileTitle),
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
    final reading = t.textTheme.bodyLarge;
    return switch (block) {
      Para(:final text) => Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Text(text, style: reading),
        ),
      Bullets(:final items) => Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // A small brand dot, centred on the first line's x-height: the bullet
                      // marks where an item starts and says nothing else.
                      ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.only(top: Space.xs + Space.hair),
                          child: Container(
                            width: Space.tight,
                            height: Space.tight,
                            decoration: BoxDecoration(
                              color: t.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(child: Text(item, style: reading)),
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
                        style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary),
                      ),
                      const SizedBox(height: Space.xxs),
                      Text(entry.detail, style: reading),
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
/// four months after joining has no gate left to look at. Reachable from Security, which every
/// role can open, and from the foot of the sign-in screen, before anybody has an account open.
///
/// A sub-page in the new look: the forest header with a back arrow, the two-way switcher on the
/// cream ground under it, then the document.
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(leading: HeaderBackButton(), title: 'Terms & Privacy'),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 0),
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
              padding: EdgeInsets.fromLTRB(
                  Space.md, Space.lg, Space.md, Space.xxl + MediaQuery.paddingOf(context).bottom),
              children: [
                LegalDocumentView(document: document),
                const SizedBox(height: Space.xl),
                // The published copy, printed rather than linked. `url_launcher` is not a
                // dependency of this project (pubspec.yaml records why for its neighbours), and
                // adding one to open text the app is already showing would be a poor trade. The
                // string is selectable here so it can be copied into a browser by hand.
                FlatSurface(
                  borderRadius: Radii.rSurface,
                  padding: const EdgeInsets.all(Space.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Published copy', style: t.textTheme.titleSmall),
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
