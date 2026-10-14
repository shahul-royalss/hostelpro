library;

/// One page of rows, plus whether asking for another is worth it.
///
/// WHY PAGINATION IS NOT OPTIONAL HERE. A 200-bed PG has 200 students, 12 months of fee rows
/// each, and a complaints table that only grows. Fetching all of it to render the twenty rows
/// that fit on a phone screen costs the resident's mobile data, the device's memory and the
/// first-paint time — three things this app cannot afford to waste. Every list endpoint in
/// this layer takes a page and uses `.range()`.
///
/// HOW [hasMore] IS KNOWN WITHOUT A COUNT. PostgREST can return an exact count, but that makes
/// the database count every matching row on every page — a full scan to render a "next"
/// button. Instead each query asks for one row more than the page size: if it comes back, there
/// is another page, and the extra row is dropped. One row of overhead, no count query.
class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  /// An empty first page. Used where a query is not applicable rather than not yet loaded.
  const PagedResult.empty({this.pageSize = defaultPageSize})
      : items = const [],
        page = 0,
        hasMore = false;

  /// Twenty rows fills a phone screen and a bit. Small enough to be fast on 3G, large enough
  /// that scrolling does not fire a request every flick.
  static const defaultPageSize = 20;

  final List<T> items;

  /// Zero-based.
  final int page;
  final int pageSize;

  /// True when the server had at least one more row after this page.
  final bool hasMore;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  /// The page number to request next, or null at the end of the list.
  int? get nextPage => hasMore ? page + 1 : null;

  /// Builds a page from a raw result that was fetched with one extra row (see the class doc).
  static PagedResult<T> fromOverfetch<T>(
    List<T> fetched, {
    required int page,
    required int pageSize,
  }) {
    final hasMore = fetched.length > pageSize;
    return PagedResult<T>(
      items: hasMore ? fetched.sublist(0, pageSize) : fetched,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  /// Appends a newly loaded page to what is already on screen, for infinite scroll.
  PagedResult<T> followedBy(PagedResult<T> next) => PagedResult<T>(
        items: [...items, ...next.items],
        page: next.page,
        pageSize: next.pageSize,
        hasMore: next.hasMore,
      );

  PagedResult<R> map<R>(R Function(T) transform) => PagedResult<R>(
        items: items.map(transform).toList(growable: false),
        page: page,
        pageSize: pageSize,
        hasMore: hasMore,
      );
}
