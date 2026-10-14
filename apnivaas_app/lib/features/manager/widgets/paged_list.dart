library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import 'manager_ui.dart';

/// A list that loads the next page as the manager reaches the bottom.
///
/// PAIRED WITH PagedNotifier in lib/data/providers.dart, and it takes that class's contract
/// seriously: [onLoadMore] RETURNS the failure instead of throwing, so a page that fails to
/// load shows a retry line UNDER the rows already on screen rather than replacing eight months
/// of expenses with an error page. Losing your place because a phone lost signal in a store
/// room is the difference between a tool and a toy.
///
/// The trigger is the footer being BUILT rather than a scroll-offset listener: it fires once
/// when the end comes into view, costs nothing while the list is still, and does not need to
/// know the row height.
class PagedList<T> extends StatelessWidget {
  const PagedList({
    super.key,
    required this.value,
    required this.itemBuilder,
    required this.onLoadMore,
    required this.onRefresh,
    required this.empty,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
  });

  final AsyncValue<PagedResult<T>> value;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Returns null on success, or the failure to show without disturbing the rows.
  final Future<AppFailure?> Function() onLoadMore;
  final Future<void> Function() onRefresh;

  /// Shown when the first page came back with nothing.
  final Widget empty;

  /// Pinned above the rows and scrolls with them — filters, a summary.
  final Widget? header;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AsyncSection<PagedResult<T>>(
        value: value,
        onRetry: onRefresh,
        // The loading and failure states are scrollable too, or pull-to-refresh is the one
        // gesture that cannot rescue a screen that failed to load.
        loading: ListView(
          padding: padding,
          // Explicit rather than inherited from ScrollView's `primary` inference — the same
          // reasoning as the empty state below, and as the warden's copy of this file.
          physics: const AlwaysScrollableScrollPhysics(),
          children: [?header, const Spinner()],
        ),
        builder: (page) {
          if (page.isEmpty) {
            // Centred in the viewport rather than stacked at the top — see the same change
            // in the student list. It stays inside the always-scrollable ListView so
            // pull-to-refresh survives on a screen with nothing to scroll, and the minimum
            // height is floored at zero so a short viewport cannot ask for a negative one.
            return LayoutBuilder(
              builder: (context, box) => ListView(
                padding: padding,
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  ?header,
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(0, box.maxHeight - padding.vertical),
                    ),
                    child: Center(child: empty),
                  ),
                ],
              ),
            );
          }
          return _Rows<T>(
            page: page,
            itemBuilder: itemBuilder,
            onLoadMore: onLoadMore,
            header: header,
            padding: padding,
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
  AppFailure? _loadMoreError;

  /// Guards against the footer being built repeatedly while one scroll settles.
  bool _requested = false;

  @override
  void didUpdateWidget(_Rows<T> old) {
    super.didUpdateWidget(old);
    // A new page arrived, or the list was rebuilt from the top: arm the trigger again.
    if (widget.page.items.length != old.page.items.length) {
      _requested = false;
      _loadMoreError = null;
    }
  }

  Future<void> _loadMore() async {
    if (_requested) return;
    _requested = true;
    final failure = await widget.onLoadMore();
    if (!mounted) return;
    if (failure != null) setState(() => _loadMoreError = failure);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.page.items;
    final hasHeader = widget.header != null;
    final hasFooter = widget.page.hasMore;
    final count = items.length + (hasHeader ? 1 : 0) + (hasFooter ? 1 : 0);

    return ListView.separated(
      padding: widget.padding,
      // Always scrollable so pull-to-refresh works even on a list of one row.
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: Space.xs),
      itemBuilder: (context, index) {
        if (hasHeader && index == 0) return widget.header!;
        final row = index - (hasHeader ? 1 : 0);
        if (row < items.length) return widget.itemBuilder(context, items[row]);
        return _LoadMoreFooter(
          error: _loadMoreError,
          onVisible: _loadMore,
          onRetry: () {
            setState(() {
              _loadMoreError = null;
              _requested = false;
            });
            _loadMore();
          },
        );
      },
    );
  }
}

/// The last row. Asks for the next page the moment it is built, unless the last attempt failed
/// — in which case it says so and waits to be asked again, rather than retrying in a loop over
/// a connection that is not working.
class _LoadMoreFooter extends StatefulWidget {
  const _LoadMoreFooter({required this.error, required this.onVisible, required this.onRetry});
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
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Column(
        children: [
          Text(error.message, style: t.textTheme.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: Space.xs),
          TextButton(onPressed: widget.onRetry, child: const Text('Load more')),
        ],
      ),
    );
  }
}
