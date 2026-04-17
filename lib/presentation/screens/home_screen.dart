/// HomeScreen — Building selection, quick actions, recent destinations.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/navigation_bloc.dart';
import '../bloc/localization_bloc.dart';
import '../widgets/building_card.dart';
import '../widgets/confidence_indicator.dart';
import 'search_screen.dart';
import 'navigation_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildAppBar(context),
            _buildLocationStatus(context),
            _buildQuickActions(context),
            _buildBuildingGrid(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      backgroundColor: const Color(0xFF0A0E21),
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          'VIT Campus Navigator',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1A2E), Color(0xFF0A0E21)],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: Colors.white70, size: 28),
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SearchScreen(),
            ));
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildLocationStatus(BuildContext context) {
    return SliverToBoxAdapter(
      child: BlocBuilder<LocalizationBloc, LocalizationState>(
        builder: (context, state) {
          return Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: switch (state) {
                  LocalizationActive(:final position) when position.confidence >= 0.7 =>
                    [const Color(0xFF1B5E20), const Color(0xFF2E7D32)],
                  LocalizationActive(:final position) when position.confidence >= 0.3 =>
                    [const Color(0xFFE65100), const Color(0xFFF57C00)],
                  _ => [const Color(0xFF424242), const Color(0xFF616161)],
                },
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  state is LocalizationActive
                      ? Icons.my_location
                      : Icons.location_searching,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state is LocalizationActive
                            ? 'Position Tracked'
                            : 'Scan QR to Start',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state is LocalizationActive
                            ? 'Building: ${(state).position.building.toUpperCase()}, Floor ${(state).position.floor}'
                            : 'Point your camera at a QR code to begin',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state is LocalizationActive)
                  ConfidenceIndicator(
                    confidence: (state).position.confidence,
                  ),
              ],
            ),
          );
        },
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
            const Text(
              'Quick Actions',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _QuickActionChip(
                  icon: Icons.wc,
                  label: 'Washroom',
                  color: const Color(0xFF00BCD4),
                  onTap: () => _findNearestAmenity(context, 'washroom'),
                ),
                const SizedBox(width: 10),
                _QuickActionChip(
                  icon: Icons.stairs,
                  label: 'Stairs',
                  color: const Color(0xFFFF9800),
                  onTap: () => _findNearestAmenity(context, 'stairs'),
                ),
                const SizedBox(width: 10),
                _QuickActionChip(
                  icon: Icons.elevator,
                  label: 'Lift',
                  color: const Color(0xFF9C27B0),
                  onTap: () => _findNearestAmenity(context, 'lift'),
                ),
                const SizedBox(width: 10),
                _QuickActionChip(
                  icon: Icons.meeting_room,
                  label: 'HOD Office',
                  color: const Color(0xFF4CAF50),
                  onTap: () => _findNearestAmenity(context, 'office'),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildBuildingGrid(BuildContext context) {
    final buildings = [
      {'id': 'cs', 'name': 'Computer Science', 'code': 'CS', 'floors': 4, 'icon': Icons.computer},
      {'id': 'aiml', 'name': 'AI & ML', 'code': 'AIML', 'floors': 4, 'icon': Icons.psychology},
      {'id': 'aids', 'name': 'AI & Data Science', 'code': 'AIDS', 'floors': 4, 'icon': Icons.data_usage},
      {'id': 'ai', 'name': 'Artificial Intelligence', 'code': 'AI', 'floors': 4, 'icon': Icons.smart_toy},
    ];

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Buildings',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: buildings.length,
              itemBuilder: (context, index) {
                final b = buildings[index];
                return BuildingCard(
                  code: b['code'] as String,
                  name: b['name'] as String,
                  floors: b['floors'] as int,
                  icon: b['icon'] as IconData,
                  onTap: () {
                    context.read<LocalizationBloc>().add(
                      BuildingSelected(b['id'] as String),
                    );
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SearchScreen(
                        buildingId: b['id'] as String,
                        buildingName: b['name'] as String,
                      ),
                    ));
                  },
                );
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _findNearestAmenity(BuildContext context, String type) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Finding nearest $type...'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E88E5),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
