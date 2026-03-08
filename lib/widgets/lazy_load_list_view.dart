import 'package:flutter/material.dart';

/// A reusable widget for lazy loading lists with pagination
/// Provides infinite scroll functionality with loading indicator
class LazyLoadListView<T> extends StatefulWidget {
  /// Function to load initial data
  final Future<List<T>> Function() loadInitial;
  
  /// Function to load more data with offset
  final Future<List<T>> Function(int offset, int pageSize) loadMore;
  
  /// Function to filter items based on search query
  final List<T> Function(List<T> items, String query)? filterItems;
  
  /// Widget builder for each item
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  
  /// Widget to show when list is empty
  final Widget? emptyWidget;
  
  /// Page size for pagination
  final int pageSize;
  
  /// Whether to show search field
  final bool showSearch;
  
  /// Search hint text
  final String searchHint;
  
  /// Refresh callback
  final Future<void> Function()? onRefresh;
  
  /// Header widget (shown above list)
  final Widget? header;
  
  /// Padding for the list
  final EdgeInsets padding;
  
  /// Whether this list uses filters that require full data load
  /// If true, loadInitial will be called and lazy loading disabled
  final bool requiresFullData;

  const LazyLoadListView({
    super.key,
    required this.loadInitial,
    required this.loadMore,
    required this.itemBuilder,
    this.filterItems,
    this.emptyWidget,
    this.pageSize = 20,
    this.showSearch = true,
    this.searchHint = 'Tìm kiếm...',
    this.onRefresh,
    this.header,
    this.padding = const EdgeInsets.all(16),
    this.requiresFullData = false,
  });

  @override
  State<LazyLoadListView<T>> createState() => _LazyLoadListViewState<T>();
}

class _LazyLoadListViewState<T> extends State<LazyLoadListView<T>> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  
  List<T> _items = [];
  List<T> _filteredItems = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= 
          _scrollController.position.maxScrollExtent - 200) {
        _loadMoreIfNeeded();
      }
    });
    
    _searchController.addListener(() {
      _onSearchChanged(_searchController.text);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _currentOffset = 0;
      _items = [];
      _filteredItems = [];
      _hasMore = !widget.requiresFullData;
    });

    try {
      if (widget.requiresFullData) {
        // Load all data at once (for filtered views)
        final allItems = await widget.loadInitial();
        if (mounted) {
          setState(() {
            _items = allItems;
            _filteredItems = allItems;
            _isLoading = false;
            _hasMore = false;
          });
        }
      } else {
        // Load first page
        final initialItems = await widget.loadMore(0, widget.pageSize);
        if (mounted) {
          setState(() {
            _items = initialItems;
            _filteredItems = initialItems;
            _currentOffset = widget.pageSize;
            _isLoading = false;
            _hasMore = initialItems.length >= widget.pageSize;
          });
        }
      }
    } catch (e) {
      debugPrint('LazyLoadListView: Error loading initial data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreIfNeeded() async {
    if (_isLoadingMore || !_hasMore || _searchQuery.isNotEmpty || widget.requiresFullData) {
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      final newItems = await widget.loadMore(_currentOffset, widget.pageSize);
      if (mounted) {
        setState(() {
          _items.addAll(newItems);
          _filteredItems = _items;
          _currentOffset += widget.pageSize;
          _isLoadingMore = false;
          _hasMore = newItems.length >= widget.pageSize;
        });
      }
    } catch (e) {
      debugPrint('LazyLoadListView: Error loading more data: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredItems = _items;
      } else if (widget.filterItems != null) {
        _filteredItems = widget.filterItems!(_items, query);
      }
    });
  }

  Future<void> _handleRefresh() async {
    if (widget.onRefresh != null) {
      await widget.onRefresh!();
    }
    await _loadInitialData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Header (optional)
          if (widget.header != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(
                  left: widget.padding.left,
                  right: widget.padding.right,
                  top: widget.padding.top,
                ),
                child: widget.header,
              ),
            ),
          
          // Search field (optional)
          if (widget.showSearch)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.padding.left,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: widget.searchHint,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
          
          // List content
          _filteredItems.isEmpty
              ? SliverFillRemaining(
                  child: widget.emptyWidget ?? _buildDefaultEmptyWidget(),
                )
              : SliverPadding(
                  padding: EdgeInsets.only(
                    left: widget.padding.left,
                    right: widget.padding.right,
                    bottom: widget.padding.bottom,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index < _filteredItems.length) {
                          return widget.itemBuilder(
                            context,
                            _filteredItems[index],
                            index,
                          );
                        }
                        return null;
                      },
                      childCount: _filteredItems.length,
                    ),
                  ),
                ),
          
          // Loading indicator
          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          
          // "Load more" hint when at end
          if (!_hasMore && _filteredItems.isNotEmpty && !widget.requiresFullData)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'Đã hiển thị ${_filteredItems.length} mục',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDefaultEmptyWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'Không tìm thấy kết quả'
                : 'Chưa có dữ liệu',
            style: TextStyle(
              fontSize: 17,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
  
  /// Public method to refresh data from outside
  void refresh() {
    _loadInitialData();
  }
  
  /// Public method to access current items
  List<T> get items => _items;
  
  /// Public method to access filtered items
  List<T> get filteredItems => _filteredItems;
}

/// Extension to create LazyLoadListView easily
extension LazyLoadListViewBuilder on Widget {
  static LazyLoadListView<T> create<T>({
    required Future<List<T>> Function() loadInitial,
    required Future<List<T>> Function(int offset, int pageSize) loadMore,
    required Widget Function(BuildContext context, T item, int index) itemBuilder,
    List<T> Function(List<T> items, String query)? filterItems,
    Widget? emptyWidget,
    int pageSize = 20,
    bool showSearch = true,
    String searchHint = 'Tìm kiếm...',
    Future<void> Function()? onRefresh,
    Widget? header,
    EdgeInsets padding = const EdgeInsets.all(16),
    bool requiresFullData = false,
  }) {
    return LazyLoadListView<T>(
      loadInitial: loadInitial,
      loadMore: loadMore,
      itemBuilder: itemBuilder,
      filterItems: filterItems,
      emptyWidget: emptyWidget,
      pageSize: pageSize,
      showSearch: showSearch,
      searchHint: searchHint,
      onRefresh: onRefresh,
      header: header,
      padding: padding,
      requiresFullData: requiresFullData,
    );
  }
}
