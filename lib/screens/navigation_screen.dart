import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/models.dart';
import '../core/campus_data.dart';
import '../providers/navigation_provider.dart';
import '../widgets/map_painter.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with TickerProviderStateMixin {
  late AnimationController _pathAnimController;
  late AnimationController _pulseController;
  final TransformationController _transformCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _pathAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pathAnimController.dispose();
    _pulseController.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Consumer<NavigationProvider>(
        builder: (context, nav, _) {
          final hasPath = nav.activePath != null;

          return Stack(
            children: [
              // ─── Map View ───
              Positioned.fill(child: _buildMap(nav)),

              // ─── Top Bar ───
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(context, nav),
              ),

              // ─── Floor Selector ───
              Positioned(
                right: 12,
                top: MediaQuery.of(context).padding.top + 70,
                child: _buildFloorSelector(nav),
              ),

              // ─── Path Info Panel ───
              if (hasPath)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildPathPanel(nav),
                ),

              // ─── No Path Message ───
              if (!hasPath && nav.destNodeId != null)
                Positioned(
                  bottom: 100,
                  left: 40,
                  right: 40,
                  child: _buildNoPathMessage(),
                ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // MAP
  // ═══════════════════════════════════════════════════════════

  Widget _buildMap(NavigationProvider nav) {
    final floorNodes = nav.floorNodes;
    final floorEdges = <NavEdge>[];
    final nodeMap = <String, NavNode>{};

    for (final node in floorNodes) {
      nodeMap[node.id] = node;
    }

    // Get edges for this floor
    for (final node in floorNodes) {
      for (final entry in nav.graph.getNeighbors(node.id).entries) {
        final edge = entry.value;
        // Only include edges where both nodes are on this floor
        if (nodeMap.containsKey(edge.fromNode) &&
            nodeMap.containsKey(edge.toNode)) {
          floorEdges.add(edge);
        }
      }
    }

    // Filter active path to current floor
    NavPath? floorPath;
    if (nav.activePath != null) {
      final pathNodes = nav.activePath!.nodes
          .where((n) => n.floor == nav.selectedFloor)
          .toList();
      if (pathNodes.length >= 2) {
        final pathEdges = <NavEdge>[];
        for (int i = 0; i < nav.activePath!.nodes.length - 1; i++) {
          if (nav.activePath!.nodes[i].floor == nav.selectedFloor &&
              nav.activePath!.nodes[i + 1].floor == nav.selectedFloor) {
            pathEdges.add(nav.activePath!.edges[i]);
          }
        }
        floorPath = NavPath(nodes: pathNodes, edges: pathEdges);
      }
    }

    return InteractiveViewer(
      transformationController: _transformCtrl,
      minScale: 0.5,
      maxScale: 4.0,
      boundaryMargin: const EdgeInsets.all(100),
      child: GestureDetector(
        onTapUp: (details) => _onMapTap(details, nav, nodeMap),
        child: AnimatedBuilder(
          animation: _pathAnimController,
          builder: (context, _) => CustomPaint(
            size: const Size(450, 280),
            painter: MapPainter(
              nodes: floorNodes,
              edges: floorEdges,
              activePath: floorPath,
              currentSegmentIndex: nav.currentSegmentIndex,
              selectedNodeId: null,
              startNodeId: nav.startNodeId,
              destNodeId: nav.destNodeId,
              blockedEdges: nav.blockedEdges,
              animationValue: _pathAnimController.value,
              nodeMap: nodeMap,
            ),
          ),
        ),
      ),
    );
  }

  void _onMapTap(
      TapUpDetails details, NavigationProvider nav, Map<String, NavNode> nodeMap) {
    // Find nearest node to tap
    final tapPos = details.localPosition;
    double minDist = double.infinity;
    NavNode? nearest;

    for (final node in nodeMap.values) {
      final screenPos = Offset(
        node.position.x * 7.0 + 20.0,
        (30.0 - node.position.z) * 7.0 + 30.0,
      );
      final d = (tapPos - screenPos).distance;
      if (d < minDist && d < 20) {
        minDist = d;
        nearest = node;
      }
    }

    if (nearest != null) {
      _showNodeActions(nearest);
    }
  }

  void _showNodeActions(NavNode node) {
    final nav = context.read<NavigationProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              node.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${node.building.toUpperCase()} • Floor ${node.floor} • ${node.typeLabel}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    icon: Icons.my_location_rounded,
                    label: 'Set as Start',
                    color: const Color(0xFF4CAF50),
                    onTap: () {
                      nav.setStartNode(node.id);
                      if (nav.destNodeId != null) nav.computePath();
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionButton(
                    icon: Icons.flag_rounded,
                    label: 'Set as Dest',
                    color: const Color(0xFFFF5252),
                    onTap: () {
                      nav.setDestination(node.id);
                      if (nav.startNodeId != null) nav.computePath();
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TOP BAR
  // ═══════════════════════════════════════════════════════════

  Widget _buildTopBar(BuildContext context, NavigationProvider nav) {
    final building = campusBuildings.firstWhere(
      (b) => b.id == nav.selectedBuilding,
      orElse: () => campusBuildings.first,
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
          8, MediaQuery.of(context).padding.top + 4, 8, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0A0E21),
            const Color(0xFF0A0E21).withOpacity(0.9),
            const Color(0xFF0A0E21).withOpacity(0),
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white70, size: 20),
            onPressed: () {
              nav.stopNavigation();
              Navigator.pop(context);
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${building.code} Building',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Floor ${nav.selectedFloor}',
                  style: TextStyle(
                    color: const Color(0xFF00BCD4).withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (nav.isNavigating)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF00BCD4).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF00BCD4).withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.route_rounded,
                      color: Color(0xFF00BCD4), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    nav.algorithmUsed ?? '',
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              nav.wheelchairMode
                  ? Icons.accessible_rounded
                  : Icons.accessible_forward_rounded,
              color: nav.wheelchairMode
                  ? const Color(0xFF00BCD4)
                  : Colors.white38,
              size: 22,
            ),
            onPressed: () => nav.toggleWheelchairMode(),
            tooltip: 'Wheelchair accessible route',
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // FLOOR SELECTOR
  // ═══════════════════════════════════════════════════════════

  Widget _buildFloorSelector(NavigationProvider nav) {
    final pathFloors = nav.activePath?.floorsTraversed ?? {};

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A4A)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(4, (i) {
          final floor = 4 - i;
          final isSelected = floor == nav.selectedFloor;
          final isOnPath = pathFloors.contains(floor);

          return GestureDetector(
            onTap: () => nav.selectFloor(floor),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00BCD4).withOpacity(0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$floor',
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF00E5FF)
                        : isOnPath
                            ? const Color(0xFF00BCD4)
                            : Colors.white38,
                    fontWeight:
                        isSelected ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // PATH INFO PANEL
  // ═══════════════════════════════════════════════════════════

  Widget _buildPathPanel(NavigationProvider nav) {
    final path = nav.activePath!;
    final remaining = path.remainingDistance(nav.currentSegmentIndex);
    final progress = 1.0 - (remaining / path.totalDistance).clamp(0.0, 1.0);

    // Current instruction
    String instruction = 'Navigate to ${path.destination.displayName}';
    if (nav.currentSegmentIndex < path.nodes.length - 1) {
      final next = path.nodes[nav.currentSegmentIndex + 1];
      if (next.type == NodeType.stairs) {
        instruction = '🚶 Head to staircase';
      } else if (next.type == NodeType.lift) {
        instruction = '🛗 Head to elevator';
      } else if (next.type == NodeType.washroom) {
        instruction = '🚻 Washroom ahead';
      } else if (next.isDestination) {
        instruction = '📍 ${next.displayName} ahead';
      } else {
        instruction = '→ Continue to ${next.displayName}';
      }
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00121830),
            Color(0xFF121830),
            Color(0xFF0D1225),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),

              // Instruction
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BCD4).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF00BCD4).withOpacity(0.2)),
                ),
                child: Text(
                  instruction,
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: const Color(0xFF1A2640),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF00BCD4)),
                ),
              ),
              const SizedBox(height: 10),

              // Stats row
              Row(
                children: [
                  _infoChip(Icons.straighten_rounded,
                      '${remaining.toStringAsFixed(0)}m left'),
                  const SizedBox(width: 12),
                  _infoChip(Icons.timer_outlined, path.formattedETA),
                  const SizedBox(width: 12),
                  _infoChip(Icons.layers_rounded,
                      '${path.floorsTraversed.length} floor${path.isCrossFloor ? 's' : ''}'),
                  const Spacer(),
                  Text(
                    '${nav.computeTimeMs}ms',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.3), fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Action buttons
              Row(
                children: [
                  // Simulate walk
                  Expanded(
                    child: _panelButton(
                      icon: Icons.directions_walk_rounded,
                      label: 'Step Forward',
                      color: const Color(0xFF00BCD4),
                      onTap: () => nav.advanceSegment(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Reroute
                  Expanded(
                    child: _panelButton(
                      icon: Icons.alt_route_rounded,
                      label: 'Reroute',
                      color: const Color(0xFFFFA726),
                      onTap: () => nav.reroute(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Stop
                  Expanded(
                    child: _panelButton(
                      icon: Icons.stop_rounded,
                      label: 'Stop',
                      color: const Color(0xFFEF5350),
                      onTap: () {
                        nav.stopNavigation();
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.6), fontSize: 12)),
      ],
    );
  }

  Widget _panelButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoPathMessage() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEF5350).withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFEF5350), size: 36),
          const SizedBox(height: 8),
          const Text(
            'No path found',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Some corridors may be blocked. Try disabling wheelchair mode.',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
