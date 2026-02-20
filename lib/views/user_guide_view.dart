import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../data/user_guide_repository.dart';
import '../services/notification_service.dart';

/// Complete User Guide View - Professional in-app documentation viewer
class UserGuideView extends StatefulWidget {
  final String userRole;
  const UserGuideView({super.key, this.userRole = 'all'});

  @override
  State<UserGuideView> createState() => _UserGuideViewState();
}

class _UserGuideViewState extends State<UserGuideView> with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late TabController _tabController;
  
  String? _selectedModuleId;
  List<GuideSection> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim();
    setState(() {
      _isSearching = query.isNotEmpty;
      if (_isSearching) {
        _searchResults = UserGuideRepository.searchSections(query, userRole: widget.userRole);
      }
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _isSearching = false;
      _searchResults = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('📚 UserGuideView.build() called');
    debugPrint('📚 _isSearching=$_isSearching, _selectedModuleId=$_selectedModuleId');
    
    // Debug: kiểm tra data
    final modules = UserGuideRepository.modules;
    debugPrint('📚 Total modules: ${modules.length}');
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          _buildSliverAppBar(false),
          SliverToBoxAdapter(
            child: _isSearching
                ? _buildSearchResults()
                : _selectedModuleId != null
                    ? _buildModuleDetail()
                    : _buildModuleList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(bool innerBoxIsScrolled) {
    return SliverAppBar(
      expandedHeight: _selectedModuleId != null ? 120 : 200,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF6A1B9A),
      foregroundColor: Colors.white,
      leading: _selectedModuleId != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _selectedModuleId = null),
            )
          : null,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0), Color(0xFFBA68C8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedModuleId == null) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.menu_book, size: 32, color: Colors.white),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.userGuide,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(context)!.learnHowToUseApp,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        collapseMode: CollapseMode.parallax,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.searchGuides,
                hintStyle: TextStyle(color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search, color: Colors.purple),
                suffixIcon: _isSearching
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: _clearSearch,
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModuleList() {
    debugPrint('📚 _buildModuleList() called');
    final modules = UserGuideRepository.getModules(userRole: widget.userRole);
    final popularSections = UserGuideRepository.getPopularSections(userRole: widget.userRole);
    final newSections = UserGuideRepository.getNewSections(userRole: widget.userRole);
    
    debugPrint('📚 modules.length=${modules.length}');
    debugPrint('📚 popularSections.length=${popularSections.length}');
    debugPrint('📚 newSections.length=${newSections.length}');
    debugPrint('📚 sections.length=${UserGuideRepository.sections.length}');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
        // Quick Stats
        _buildQuickStats(modules.length, UserGuideRepository.sections.length),
        const SizedBox(height: 20),

        // Popular Sections
        if (popularSections.isNotEmpty) ...[
          _buildSectionHeader('📌 Được xem nhiều nhất', null),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: popularSections.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return _buildPopularCard(popularSections[index]);
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // New Sections
        if (newSections.isNotEmpty) ...[
          _buildSectionHeader('🆕 Mới cập nhật', null),
          const SizedBox(height: 12),
          ...newSections.map((s) => _buildNewSectionCard(s)),
          const SizedBox(height: 24),
        ],

        // All Modules
        _buildSectionHeader('📚 Tất cả chủ đề', '${modules.length} chủ đề'),
        const SizedBox(height: 12),
        ...modules.map((m) => _buildModuleCard(m)),
        const SizedBox(height: 32),

        // Help Footer
        _buildHelpFooter(),
        const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildQuickStats(int moduleCount, int sectionCount) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade50, Colors.blue.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.shade100),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              Icons.folder_outlined,
              '$moduleCount',
              'Chủ đề',
              Colors.purple,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.purple.shade200,
          ),
          Expanded(
            child: _buildStatItem(
              Icons.article_outlined,
              '$sectionCount',
              'Bài hướng dẫn',
              Colors.blue,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.purple.shade200,
          ),
          Expanded(
            child: _buildStatItem(
              Icons.verified_outlined,
              '100%',
              AppLocalizations.of(context)!.free,
              Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String? subtitle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
      ],
    );
  }

  Widget _buildPopularCard(GuideSection section) {
    final module = UserGuideRepository.findModule(section.moduleId);
    return GestureDetector(
      onTap: () => _openSectionDetail(section),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              module?.color ?? Colors.purple,
              (module?.color ?? Colors.purple).withOpacity(0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (module?.color ?? Colors.purple).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(module?.icon ?? Icons.article, color: Colors.white, size: 28),
            const SizedBox(height: 12),
            Text(
              section.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 14, color: Colors.white.withOpacity(0.8)),
                const SizedBox(width: 4),
                Text(
                  section.estimatedTime,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white70),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewSectionCard(GuideSection section) {
    final module = UserGuideRepository.findModule(section.moduleId);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: (module?.color ?? Colors.purple).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Center(child: Icon(module?.icon ?? Icons.article, color: module?.color ?? Colors.purple)),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          section.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            AppLocalizations.of(context)!.newLabel,
            style: const TextStyle(
              color: Colors.green,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        onTap: () => _openSectionDetail(section),
      ),
    );
  }

  Widget _buildModuleCard(GuideModule module) {
    final sectionCount = UserGuideRepository.getSectionsByModule(module.id, userRole: widget.userRole).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selectedModuleId = module.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: module.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(module.icon, color: module.color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      module.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: module.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$sectionCount bài',
                            style: TextStyle(
                              color: module.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModuleDetail() {
    final module = UserGuideRepository.findModule(_selectedModuleId!);
    if (module == null) return Center(child: Text(AppLocalizations.of(context)!.notFound));

    final sections = UserGuideRepository.getSectionsByModule(module.id, userRole: widget.userRole);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
        // Module Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [module.color.withOpacity(0.1), module.color.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: module.color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: module.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(module.icon, color: module.color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: module.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      module.description,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${sections.length} bài hướng dẫn',
                      style: TextStyle(
                        color: module.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Sections List
        ...sections.asMap().entries.map((entry) {
          final index = entry.key;
          final section = entry.value;
          return _buildSectionCard(section, index + 1, module.color);
        }),
        const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionCard(GuideSection section, int index, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openSectionDetail(section),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            section.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (section.isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              AppLocalizations.of(context)!.newLabel,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      section.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildInfoChip(Icons.timer_outlined, section.estimatedTime, Colors.blue),
                        const SizedBox(width: 8),
                        _buildInfoChip(Icons.signal_cellular_alt, section.difficulty, _getDifficultyColor(context, section.difficulty)),
                        const SizedBox(width: 8),
                        _buildInfoChip(Icons.list, '${section.steps.length} bước', Colors.purple),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getDifficultyColor(BuildContext context, String difficulty) {
    final loc = AppLocalizations.of(context)!;
    if (difficulty == loc.easy) {
      return Colors.green;
    } else if (difficulty == loc.medium) {
      return Colors.orange;
    } else if (difficulty == loc.advanced) {
      return Colors.red;
    } else {
      return Colors.grey;
    }
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noResultsFound,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.tryDifferentKeywords,
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              AppLocalizations.of(context)!.foundResults(_searchResults.length),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          ..._searchResults.asMap().entries.map((entry) {
            final index = entry.key;
            final section = entry.value;
            final module = UserGuideRepository.findModule(section.moduleId);
            return _buildSectionCard(section, index + 1, module?.color ?? Colors.purple);
          }),
        ],
      ),
    );
  }

  Widget _buildHelpFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.support_agent, color: Colors.blueGrey.shade700, size: 28),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)!.needMoreHelp,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.supportTeamReady,
            style: TextStyle(color: Colors.blueGrey.shade700),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildContactButton(
                icon: Icons.email_outlined,
                label: AppLocalizations.of(context)!.supportEmail,
                onTap: () => NotificationService.showSnackBar(
                  'Email: ${AppLocalizations.of(context)!.supportEmail}',
                  color: Colors.blue,
                ),
              ),
              _buildContactButton(
                icon: Icons.phone_outlined,
                label: AppLocalizations.of(context)!.hotline,
                onTap: () => NotificationService.showSnackBar(
                  AppLocalizations.of(context)!.supportHotline,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.blueGrey.shade700,
        side: BorderSide(color: Colors.blueGrey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _openSectionDetail(GuideSection section) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SectionDetailPage(section: section),
      ),
    );
  }
}

// =============================================================================
// SECTION DETAIL PAGE
// =============================================================================

class _SectionDetailPage extends StatelessWidget {
  final GuideSection section;
  const _SectionDetailPage({required this.section});

  @override
  Widget build(BuildContext context) {
    debugPrint('📖 UserGuide: Opening section ${section.id}');
    debugPrint('📖 UserGuide: Title=${section.title}');
    debugPrint('📖 UserGuide: Steps count=${section.steps.length}');
    debugPrint('📖 UserGuide: Tips count=${section.tips.length}');
    
    final module = UserGuideRepository.findModule(section.moduleId);
    final related = UserGuideRepository.getRelatedSections(section);
    final color = module?.color ?? Colors.purple;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: color,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (module != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(module.icon, size: 16, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  module.title,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          section.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Meta Info
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildMetaChip(Icons.timer_outlined, section.estimatedTime, Colors.blue),
                      _buildMetaChip(Icons.signal_cellular_alt, section.difficulty, _getDifficultyColor(context, section.difficulty)),
                      _buildMetaChip(Icons.list_alt, AppLocalizations.of(context)!.stepsCount(section.steps.length), color),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Description
                  Text(
                    section.description,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87, // FIX: Màu đen rõ ràng
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Steps
                  _buildSectionTitle(AppLocalizations.of(context)!.stepsToPerform, color),
                  const SizedBox(height: 16),
                  ...section.steps.map((step) => _buildStepItem(step, color)),

                  // Tips
                  if (section.tips.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionTitle(AppLocalizations.of(context)!.usefulTips, Colors.amber.shade700),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: section.tips.map((tip) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lightbulb, size: 18, color: Colors.amber.shade700),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  tip,
                                  style: TextStyle(color: Colors.amber.shade900),
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                  ],

                  // Warnings
                  if (section.warnings.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionTitle(AppLocalizations.of(context)!.importantNotes, Colors.red.shade700),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: section.warnings.map((warning) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber, size: 18, color: Colors.red.shade700),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  warning,
                                  style: TextStyle(color: Colors.red.shade900),
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                  ],

                  // Related
                  if (related.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionTitle(AppLocalizations.of(context)!.relatedArticles, Colors.blueGrey),
                    const SizedBox(height: 12),
                    ...related.map((r) => Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Icon(
                          UserGuideRepository.findModule(r.moduleId)?.icon ?? Icons.article,
                          color: UserGuideRepository.findModule(r.moduleId)?.color ?? Colors.purple,
                        ),
                        title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(r.estimatedTime),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => _SectionDetailPage(section: r)),
                          );
                        },
                      ),
                    )),
                  ],

                  const SizedBox(height: 32),

                  // Feedback
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.wasArticleHelpful,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  NotificationService.showSnackBar(
                                    AppLocalizations.of(context)!.thankYouForFeedback,
                                    color: Colors.green,
                                  );
                                },
                                icon: const Icon(Icons.thumb_up_outlined),
                                label: Text(AppLocalizations.of(context)!.yes),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Flexible(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  NotificationService.showSnackBar(
                                    AppLocalizations.of(context)!.weWillImprove,
                                    color: Colors.orange,
                                  );
                                },
                                icon: const Icon(Icons.thumb_down_outlined),
                                label: Text(AppLocalizations.of(context)!.notYet),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Color _getDifficultyColor(BuildContext context, String difficulty) {
    final loc = AppLocalizations.of(context)!;
    if (difficulty == loc.easy) {
      return Colors.green;
    } else if (difficulty == loc.medium) {
      return Colors.orange;
    } else if (difficulty == loc.advanced) {
      return Colors.red;
    } else {
      return Colors.grey;
    }
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    );
  }

  Widget _buildStepItem(GuideStep step, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '${step.order}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87, // FIX: Đảm bảo màu đen
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  step.description,
                  style: const TextStyle(
                    color: Colors.black54, // FIX: Màu xám đậm thay vì grey.shade700
                    height: 1.5,
                  ),
                ),
                if (step.note != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            step.note!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
