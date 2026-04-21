import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/campus_data.dart';
import '../core/models.dart';
import '../providers/navigation_provider.dart';
import '../widgets/building_card.dart';
import 'search_screen.dart';
import 'ar_navigation_screen.dart';
import 'live_map_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildAppBar(context),
            _buildStatsBanner(context),
            _buildNavigationCard(context),
            _buildQuickActions(context),
            _buildSectionTitle('Campus Buildings'),
            _buildBuildingGrid(context),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 130,
      floating: true,
      pinned: true,
      backgroundColor: const Color(0xFF0A0E21),
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'VIT Campus',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Navigator',
              style: TextStyle(
                fontWeight: FontWeight.w300,
                fontSize: 14,
                color: const Color(0xFF00BCD4).withOpacity(0.9),
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF131B30), Color(0xFF0A0E21)],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A4A)),
            ),
            child: const Icon(Icons.search_rounded,
                color: Color(0xFF00BCD4), size: 20),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildStatsBanner(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0D2137), Color(0xFF0A1628)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF1A3A5C)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00BCD4).withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _statItem(Icons.account_balance, '${campusBuildings.length}',
                'Buildings'),
            _divider(),
            _statItem(Icons.layers, '16', 'Floors'),
            _divider(),
            _statItem(Icons.meeting_room, '${nav.graph.nodeCount}', 'Nodes'),
            _divider(),
            _statItem(Icons.route, '${nav.graph.edgeCount ~/ 2}', 'Edges'),
          ],
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF00BCD4), size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 40,
      color: const Color(0xFF1A3A5C),
    );
  }

  /// Prominent hero card to launch the GPS map navigation.
  Widget _buildNavigationCard(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              final nav = context.read<NavigationProvider>();
              if (nav.activePath != null) {
                // Already have a path — go directly to map
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LiveMapScreen()),
                );
              } else {
                // Need to select start + destination first
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              }
            },
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00695C), Color(0xFF004D40)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF00BCD4).withOpacity(0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00BCD4).withOpacity(0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00BCD4).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: Color(0xFF00E5FF),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Start Navigation',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'GPS Map • Live Tracking • AR View',
                          style: TextStyle(
                            color: const Color(0xFF00E5FF).withOpacity(0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Color(0xFF00E5FF),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'QUICK FIND',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _quickChip(
                    context, Icons.wc_rounded, 'Washroom',
                    const Color(0xFF26C6DA), NodeType.washroom),
                const SizedBox(width: 8),
                _quickChip(
                    context, Icons.stairs_rounded, 'Stairs',
                    const Color(0xFFFFA726), NodeType.stairs),
                const SizedBox(width: 8),
                _quickChip(
                    context, Icons.elevator_rounded, 'Lift',
                    const Color(0xFF7E57C2), NodeType.lift),
                const SizedBox(width: 8),
                _quickChip(
                    context, Icons.science_rounded, 'Labs',
                    const Color(0xFFAB47BC), NodeType.lab),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _quickChip(BuildContext context, IconData icon, String label,
      Color color, NodeType type) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onQuickFind(context, type, label),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
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
          ),
        ),
      ),
    );
  }

  // Removed hardcoded StartNode setting. Let the user choose!
  void _onQuickFind(BuildContext context, NodeType type, String label) {
    final nav = context.read<NavigationProvider>();
    if (nav.selectedBuilding == null) {
      nav.selectBuilding('cs');
    }
    
    if (nav.startNodeId == null) {
      // Need a start location to find the nearest amenity
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select your Current Location first! Tap search.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFEF5350),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SearchScreen(isSelectingStart: true)),
      );
      return;
    }
    
    final found = nav.findNearestAmenity(type);
    if (found) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LiveMapScreen()),
      );
    }
  }

  Widget _buildSectionTitle(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildBuildingGrid(BuildContext context) {
    final icons = [
      Icons.computer_rounded,
      Icons.psychology_rounded,
      Icons.data_usage_rounded,
      Icons.smart_toy_rounded,
    ];

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: campusBuildings.length,
          itemBuilder: (context, index) {
            final b = campusBuildings[index];
            return BuildingCard(
              code: b.code,
              name: b.name,
              department: b.department,
              floors: b.floors,
              rooms: b.totalRooms,
              labs: b.totalLabs,
              icon: icons[index],
              onTap: () {
                context.read<NavigationProvider>().selectBuilding(b.id);
                // DON'T set start node. Let them pick.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SearchScreen(
                      buildingId: b.id,
                      buildingName: b.name,
                      buildingCode: b.code,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
