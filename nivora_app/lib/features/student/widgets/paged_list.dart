library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import 'common.dart';

/// A list that asks for the next page when the resident reaches the bottom.
///
/// PAIRED WITH `PagedNotifier` in lib/data/providers.dart, and it honours that class's central
/// promise: [onLoadMore] RETURNS the failure instead of throwing, so a page that fails to load
/// shows a retry line UNDER the rows already on screen. Publishing it as an error would replace
/// a resident's place in their complaint history with a full-screen apology because the lift
/// lost signal for one second.
///
/// The trigger is the footer being BUILT rather than a scroll-offset listener: it fires once
/// when the end comes into view, costs nothing while the list is still, and never needs to know
/// how tall a row is.
class StudentPagedList<T> extends StatelessWidget {
  const StudentPagedList({
    super.key,
    required this.value,
    required this.itemBuilder,
    required this.onLoadMore,
    required this.onRefresh,
    required this.empty,
    this.header,
  });

  final AsyncValue<PagedResult<T>> value;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Returns null on success, or the failure to show without disturbing the rows.
  final Future<AppFailure?> Function() onLoadMore;
  final Future<void> Function() onRefresh;

  /// Shown when the first page came back with nothing.
  final Widget empty;

  /// Scrolls with the rows rather than pinning above them.
  final Widget? header;

  static const _padding =
      EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxxl);

  @override
  Widget build(BuildContext context) {
    // EVERY STATE OF THIS SCREEN IS AN ALWAYS-SCROLLABLE LIST, and that is load-bearing twice
    // over. A [RefreshIndicator] only fires for a child that reports an over-scroll, so a state
    // drawn as a plain box makes pull-to-refresh — the one gesture that could rescue a screen
    // that failed to load — silently inert; and default physics refuse to over-scroll content
    // that already fits, which three skeletons on a phone do. The failure state is therefore
    // spelled out here rather than delegated to [AsyncSection], whose panel is a Container:
    // this list is the one place where "which widget draws the error" changes what the user
    // can DO about it.
    return RefreshIndicator(
      onRefresh: onRefresh,
      // The same two flags [AsyncSection] uses: keep the rows a resident is reading on screen
      // through a pull-to-refresh instead of blanking the list under them.
      child: value.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => ListView(
          padding: _padding,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SkeletonCard(lines: 2),
            SizedBox(height: Space.xs),
            SkeletonCard(lines: 2),
            SizedBox(height: Space.xs),
            SkeletonCard(lines: 2),
          ],
        ),
        // The failure, and nothing else — no [header]. The loudest thing on a screen that
        // failed to load should be the failure, not the primary action sitting on top of it.
        // [ErrorNote] decides for itself whether a Try again button belongs; the pull gesture
        // works either way, so the "pull down to refresh" its non-retryable copy suggests is
        // now a real instruction rather than one this list used to ignore.
        error: (error, _) => ListView(
          padding: _padding,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [ErrorNote(error: error, onRetry: onRefresh)],
        ),
        data: (page) {
          if (page.isEmpty) {
            return ListView(
              padding: _padding,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [?header, empty],
            );
          }
          return _Rows<T>(
            page: page,
            itemBuilder: itemBuilder,
            onLoadMore: onLoadMore,
            header: header,
            padding: _padding,
          );
        },
      ),
    );
  }
}

class _Rows<T> extends StatefulWidget {
  const _Rows({
    required this.page,
    required this.itemBuilder,
    required this.onLoadMore,
    required this.header,
    required this.padding,
  });

  final PagedResult<T> page;
  final Widget Function(BuildContext, T) itemBuilder;
  final Future<AppFailure?> Function() onLoadMore;
  final Widget? header;
  final EdgeInsets padding;

  @override
  State<_Rows<T>> createState() => _RowsState<T>();
}

class _RowsState<T> extends State<_Rows<T>> {
  AppFailure? _error;

  /// Guards against the footer being rebuilt several times while one scroll settles.
  bool _requested = false;

  @override
  void didUpdateWidget(_Rows<T> old) {
    super.didUpdateWidget(old);
    // A new page arrived, or the list was rebuilt from the top: arm the trigger again.
    if (widget.page.items.length != old.page.items.length) {
      _requested = false;
      _error = null;
    }
  }

  Future<void> _loadMore() async {
    if (_requested) return;
    _requested = true;
    final failure = await widget.onLoadMore();
    if (!mounted) return;
    if (failure != null) setState(() => _error = failure);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.page.items;
    final hasHeader = widget.header != null;
    final hasFooter = widget.page.hasMore;

    return ListView.separated(
      padding: widget.padding,
      // Always scrollable, so pull-to-refresh works even on a list of one row.
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length + (hasHeader ? 1 : 0) + (hasFooter ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: Space.xs),
      itemBuilder: (context, index) {
        if (hasHeader && index == 0) return widget.header!;
        final row = index - (hasHeader ? 1 : 0);
        if (row < items.length) return widget.itemBuilder(context, items[row]);
        return _LoadMoreFooter(
          // A fresh State per page, so the "ask once" latch resets with the row it belongs to.
          key: ValueKey(items.length),
          error: _error,
          onVisible: _loadMore,
          onRetry: () {
            setState(() {
              _error = null;
              _requested = false;
            });
            _loadMore();
          },
        );
      },
    );
  }
}

/// The last row. Asks for the next page the moment it is built — unless the last attempt
/// failed, in which case it says so and waits to be asked again rather than retrying in a loop
/// over a connection that is not working.
class _LoadMoreFooter extends StatefulWidget {
  const _LoadMoreFooter({super.key, required this.error, required this.onVisible, required this.onRetry});
  final AppFailure? error;
  final VoidCallback onVisible;
  final VoidCallback onRetry;

  @override
  State<_LoadMoreFooter> createState() => _LoadMoreFooterState();
}

class _LoadMoreFooterState extends State<_LoadMoreFooter> {
  @override
  void initState() {
    super.initState();
    if (widget.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onVisible();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final error = widget.error;
    if (error == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.lg),
        child: Center(
          child: SizedBox(
            width: IconSize.lg,
            height: IconSize.lg,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Column(
        children: [
          Text(errorGuidance(error).next,
              style: t.textTheme.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: Space.xs),
          TextButton(onPressed: widget.onRetry, child: const Text('Load more')),
        ],
      ),
    );
  }
}
