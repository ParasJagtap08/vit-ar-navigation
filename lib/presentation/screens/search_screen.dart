/// SearchScreen — Destination search with results list.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/navigation/models.dart';
import '../bloc/search_bloc.dart';
import 'navigation_screen.dart';

class SearchScreen extends StatefulWidget {
  final String? buildingId;
  final String? buildingName;

  const SearchScreen({super.key, this.buildingId, this.buildingName});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
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
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.buildingName ?? 'Search Destination',
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A4A)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BCD4).withOpacity(0.1),
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
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF00BCD4), size: 22),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38),
                  onPressed: () {
                    _controller.clear();
                    context.read<SearchBloc>().add(SearchCleared());
                    setState(() {});
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (query) {
          context.read<SearchBloc>().add(SearchQueryChanged(query));
          setState(() {});
        },
      ),
    );
  }

  Widget _buildResults() {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        return switch (state) {
          SearchInitial() => _buildEmptyState(),
          SearchLoading(:final query) => _buildLoadingState(query),
          SearchResults(:final results, :final query) =>
            results.isEmpty
                ? _buildNoResults(query)
                : _buildResultsList(results),
          SearchError(:final message) => _buildErrorState(message),
        };
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.explore, size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'Search for a destination',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try "CS-101", "AI Lab", or "Washroom"',
            style: TextStyle(
              color: Colors.white.withOpacity(0.25),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(String query) {
    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFF00BCD4),
        strokeWidth: 2,
      ),
    );
  }

  Widget _buildNoResults(String query) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 12),
          Text(
            'No results for "$query"',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Text(message, style: const TextStyle(color: Colors.redAccent)),
    );
  }

  Widget _buildResultsList(List<NavNode> results) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final node = results[index];
        return _SearchResultTile(
          node: node,
          onTap: () => _navigateTo(node),
        );
      },
    );
  }

  void _navigateTo(NavNode node) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NavigationScreen(
        destinationNodeId: node.id,
        destinationName: node.displayName,
        buildingId: node.building,
      ),
    ));
  }
}

class _SearchResultTile extends StatelessWidget {
  final NavNode node;
  final VoidCallback onTap;

  const _SearchResultTile({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _getTypeColor(node.type).withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _getTypeIcon(node.type),
            color: _getTypeColor(node.type),
            size: 22,
          ),
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
          '${node.building.toUpperCase()} • Floor ${node.floor} • ${node.type.name.toUpperCase()}',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 12,
          ),
        ),
        trailing: const Icon(
          Icons.navigation_outlined,
          color: Color(0xFF00BCD4),
          size: 22,
        ),
      ),
    );
  }

  IconData _getTypeIcon(NodeType type) {
    return switch (type) {
      NodeType.room => Icons.meeting_room,
      NodeType.lab => Icons.science,
      NodeType.office => Icons.business,
      NodeType.washroom => Icons.wc,
      NodeType.entrance => Icons.door_front_door,
      NodeType.stairs => Icons.stairs,
      NodeType.lift => Icons.elevator,
      _ => Icons.location_on,
    };
  }

  Color _getTypeColor(NodeType type) {
    return switch (type) {
      NodeType.room => const Color(0xFF42A5F5),
      NodeType.lab => const Color(0xFFAB47BC),
      NodeType.office => const Color(0xFF66BB6A),
      NodeType.washroom => const Color(0xFF26C6DA),
      NodeType.entrance => const Color(0xFFFFA726),
      _ => const Color(0xFF78909C),
    };
  }
}
