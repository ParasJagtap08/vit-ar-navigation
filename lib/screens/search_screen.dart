import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../providers/navigation_provider.dart';
import 'live_map_screen.dart';

class SearchScreen extends StatefulWidget {
  final String? buildingId;
  final String? buildingName;
  final String? buildingCode;
  final bool isSelectingStart;
  final NavNode? pendingDestination;

  const SearchScreen({
    super.key,
    this.buildingId,
    this.buildingName,
    this.buildingCode,
    this.isSelectingStart = false,
    this.pendingDestination,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int? _selectedFloor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      // Pre-populate with building destinations
      if (widget.buildingCode != null) {
        _controller.text = widget.buildingCode!;
        context.read<NavigationProvider>().search(widget.buildingCode!);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E21),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
          onPressed: () {
            context.read<NavigationProvider>().clearSearch();
            Navigator.pop(context);
          },
        ),
        title: Text(
          widget.isSelectingStart 
              ? 'Where are you right now?' 
              : widget.buildingName ?? 'Search Destination',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (widget.buildingId != null) _buildFloorFilter(),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A4A)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BCD4).withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Room, lab, office, or washroom...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon:
              const Icon(Icons.search_rounded, color: Color(0xFF00BCD4)),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white38),
                  onPressed: () {
                    _controller.clear();
                    context.read<NavigationProvider>().clearSearch();
                    setState(() {});
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (query) {
          context.read<NavigationProvider>().search(query);
          setState(() {});
        },
      ),
    );
  }

  Widget _buildFloorFilter() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _floorChip(null, 'All'),
          for (int i = 1; i <= 4; i++) _floorChip(i, 'Floor $i'),
        ],
      ),
    );
  }

  Widget _floorChip(int? floor, String label) {
    final selected = _selectedFloor == floor;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _selectedFloor = floor);
        },
        labelStyle: TextStyle(
          color: selected ? Colors.black : Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        backgroundColor: const Color(0xFF1A1A2E),
        selectedColor: const Color(0xFF00BCD4),
        side: BorderSide(
          color:
              selected ? const Color(0xFF00BCD4) : const Color(0xFF2A2A4A),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildResults() {
    return Consumer<NavigationProvider>(
      builder: (context, nav, _) {
        var results = nav.searchResults;

        // Apply floor filter
        if (_selectedFloor != null) {
          results =
              results.where((n) => n.floor == _selectedFloor).toList();
        }

        if (nav.searchQuery.isEmpty || nav.searchQuery.length < 2) {
          return _buildEmptyState();
        }

        if (results.isEmpty) {
          return _buildNoResults();
        }

        return _buildResultsList(results);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.explore_rounded,
              size: 64, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 16),
          Text(
            'Search for a destination',
            style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Try "CS-101", "Lab", "Washroom", or "HOD"',
            style:
                TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded,
              size: 48, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 12),
          Text(
            'No results found',
            style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(List<NavNode> results) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final node = results[index];
        return _ResultTile(
          node: node,
          onTap: () => _navigateTo(node),
        );
      },
    );
  }

  void _navigateTo(NavNode node) {
    final nav = context.read<NavigationProvider>();

    if (widget.isSelectingStart) {
      nav.setStartNode(node.id);
      if (widget.pendingDestination != null) {
        nav.setDestination(widget.pendingDestination!.id);
      }
      nav.computePath();
      nav.clearSearch();
      
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LiveMapScreen()),
      );
    } else {
      nav.setDestination(node.id);

      if (nav.startNodeId == null) {
        // We need to ask for start location. Make sure we clear the current search 
        // so they don't accidentally pick the same node they just selected.
        nav.clearSearch();
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SearchScreen(
              isSelectingStart: true,
              pendingDestination: node,
            ),
          ),
        );
      } else {
        nav.computePath();
        nav.clearSearch();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LiveMapScreen()),
        );
      }
    }
  }
}

class _ResultTile extends StatelessWidget {
  final NavNode node;
  final VoidCallback onTap;

  const _ResultTile({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _typeColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_typeIcon, color: _typeColor, size: 22),
        ),
        title: Text(
          node.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          '${node.building.toUpperCase()} • Floor ${node.floor} • ${node.typeLabel}',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
        ),
        trailing: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF00BCD4).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.navigation_rounded,
              color: Color(0xFF00BCD4), size: 18),
        ),
      ),
    );
  }

  IconData get _typeIcon {
    switch (node.type) {
      case NodeType.room:
        return Icons.meeting_room_rounded;
      case NodeType.lab:
        return Icons.science_rounded;
      case NodeType.office:
        return Icons.business_rounded;
      case NodeType.washroom:
        return Icons.wc_rounded;
      case NodeType.entrance:
        return Icons.door_front_door_rounded;
      case NodeType.stairs:
        return Icons.stairs_rounded;
      case NodeType.lift:
        return Icons.elevator_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  Color get _typeColor {
    switch (node.type) {
      case NodeType.room:
        return const Color(0xFF42A5F5);
      case NodeType.lab:
        return const Color(0xFFAB47BC);
      case NodeType.office:
        return const Color(0xFF66BB6A);
      case NodeType.washroom:
        return const Color(0xFF26C6DA);
      case NodeType.entrance:
        return const Color(0xFFFFA726);
      default:
        return const Color(0xFF78909C);
    }
  }
}
