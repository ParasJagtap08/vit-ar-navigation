/// AnchorManager.cs
/// Manages AR spatial anchors for stable placement of navigation elements.
///
/// Anchors are placed at decision points (turns, intersections) along the
/// navigation path. They provide stable reference points that persist even
/// as the AR session's tracking quality fluctuates.

using UnityEngine;
using UnityEngine.XR.ARFoundation;
using UnityEngine.XR.ARSubsystems;
using System.Collections.Generic;
using System.Linq;

/// <summary>
/// Manages placement, lifecycle, and optimization of AR anchors
/// along the navigation path.
/// </summary>
public class AnchorManager : MonoBehaviour
{
    // ─────────────────────────────────────────────────────
    // Configuration
    // ─────────────────────────────────────────────────────
    [Header("Configuration")]
    [Tooltip("Minimum distance between anchors (meters)")]
    [SerializeField] private float minAnchorSpacing = 3.0f;

    [Tooltip("Maximum distance between anchors (meters)")]
    [SerializeField] private float maxAnchorSpacing = 5.0f;

    [Tooltip("Maximum number of active anchors (performance limit)")]
    [SerializeField] private int maxAnchors = 20;

    [Tooltip("Distance beyond which anchors are hidden")]
    [SerializeField] private float anchorVisibilityRange = 15.0f;

    [Tooltip("Distance behind user to keep anchors (for looking back)")]
    [SerializeField] private float rearVisibilityRange = 5.0f;

    // ─────────────────────────────────────────────────────
    // References
    // ─────────────────────────────────────────────────────
    [Header("References")]
    [SerializeField] private ARAnchorManager arAnchorManager;

    // ─────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────
    private List<NavigationAnchor> activeAnchors = new List<NavigationAnchor>();
    private Camera arCamera;

    /// <summary>
    /// An anchor placed along the navigation path with associated metadata.
    /// </summary>
    private class NavigationAnchor
    {
        public ARAnchor arAnchor;
        public GameObject visualObject;
        public Vector3 worldPosition;
        public int pathIndex; // Index in waypoint list
        public bool isDecisionPoint; // Turn, intersection, floor change
        public float distanceFromStart;
        public bool isVisible;
    }

    void Awake()
    {
        arCamera = Camera.main;
    }

    // ─────────────────────────────────────────────────────
    // Anchor Placement
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Place anchors along a navigation path.
    /// 
    /// Strategy:
    /// 1. Always place at decision points (turns, intersections)
    /// 2. Place intermediate anchors every 3-5m on long straight segments
    /// 3. Limit total anchors for performance
    /// 4. Hide anchors beyond visibility range
    /// </summary>
    /// <param name="waypoints">World-space waypoint positions</param>
    /// <param name="decisionPointIndices">Indices of decision points in the waypoint list</param>
    public void PlaceAnchorsAlongPath(
        List<Vector3> waypoints, 
        HashSet<int> decisionPointIndices = null)
    {
        ClearAllAnchors();

        if (waypoints.Count < 2) return;

        float cumulativeDistance = 0f;
        float lastAnchorDistance = 0f;

        for (int i = 0; i < waypoints.Count; i++)
        {
            if (i > 0)
            {
                cumulativeDistance += Vector3.Distance(waypoints[i - 1], waypoints[i]);
            }

            bool isDecision = decisionPointIndices?.Contains(i) ?? false;
            float distSinceLastAnchor = cumulativeDistance - lastAnchorDistance;

            // Place anchor if:
            // 1. It's a decision point, OR
            // 2. Enough distance since last anchor
            bool shouldPlace = isDecision ||
                               distSinceLastAnchor >= maxAnchorSpacing ||
                               i == 0 || // Always at start
                               i == waypoints.Count - 1; // Always at end

            // Don't place if too close to previous (unless decision point)
            if (!isDecision && distSinceLastAnchor < minAnchorSpacing && i > 0)
            {
                shouldPlace = false;
            }

            if (shouldPlace && activeAnchors.Count < maxAnchors)
            {
                PlaceAnchor(waypoints[i], i, isDecision, cumulativeDistance);
                lastAnchorDistance = cumulativeDistance;
            }
        }
    }

    /// <summary>
    /// Place a single anchor at a world position.
    /// </summary>
    private void PlaceAnchor(Vector3 position, int pathIndex, bool isDecision, float distance)
    {
        // Create AR anchor for tracking stability
        Pose anchorPose = new Pose(position, Quaternion.identity);
        ARAnchor anchor = null;

        // Try to create an AR-tracked anchor (requires plane detection)
        if (arAnchorManager != null)
        {
            // For AR Foundation 4.x+, we create anchors from pose
            var anchorGO = new GameObject($"NavAnchor_{pathIndex}");
            anchorGO.transform.position = position;
            anchor = anchorGO.AddComponent<ARAnchor>();
        }

        var navAnchor = new NavigationAnchor
        {
            arAnchor = anchor,
            visualObject = anchor?.gameObject,
            worldPosition = position,
            pathIndex = pathIndex,
            isDecisionPoint = isDecision,
            distanceFromStart = distance,
            isVisible = true
        };

        activeAnchors.Add(navAnchor);
    }

    // ─────────────────────────────────────────────────────
    // Visibility Management
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Update anchor visibility based on user's current position.
    /// Only anchors within the visibility range are rendered.
    /// </summary>
    /// <param name="userPosition">Current user position in AR world space</param>
    /// <param name="userForward">User's forward direction</param>
    public void UpdateVisibility(Vector3 userPosition, Vector3 userForward)
    {
        foreach (var anchor in activeAnchors)
        {
            if (anchor.visualObject == null) continue;

            float distance = Vector3.Distance(userPosition, anchor.worldPosition);
            Vector3 toAnchor = (anchor.worldPosition - userPosition).normalized;
            float dot = Vector3.Dot(userForward, toAnchor);

            // Visible if:
            // 1. In front of user and within range, OR
            // 2. Behind user but within rear visibility range
            bool shouldBeVisible =
                (dot > 0 && distance <= anchorVisibilityRange) ||
                (dot <= 0 && distance <= rearVisibilityRange);

            if (shouldBeVisible != anchor.isVisible)
            {
                anchor.isVisible = shouldBeVisible;
                anchor.visualObject.SetActive(shouldBeVisible);
            }
        }
    }

    /// <summary>
    /// Get the nearest anchor to a position.
    /// </summary>
    public (Vector3 position, int pathIndex)? GetNearestAnchor(Vector3 position)
    {
        if (activeAnchors.Count == 0) return null;

        NavigationAnchor nearest = activeAnchors
            .OrderBy(a => Vector3.Distance(position, a.worldPosition))
            .First();

        return (nearest.worldPosition, nearest.pathIndex);
    }

    // ─────────────────────────────────────────────────────
    // Cleanup
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Remove all active anchors and their visual objects.
    /// </summary>
    public void ClearAllAnchors()
    {
        foreach (var anchor in activeAnchors)
        {
            if (anchor.visualObject != null)
            {
                Destroy(anchor.visualObject);
            }
        }
        activeAnchors.Clear();
    }

    /// <summary>
    /// Remove anchors that the user has already passed.
    /// Keeps a few behind for context.
    /// </summary>
    /// <param name="currentPathIndex">Current waypoint index the user is near</param>
    public void CleanupPassedAnchors(int currentPathIndex)
    {
        int keepBehindCount = 2; // Keep 2 anchors behind user

        var anchorsToRemove = activeAnchors
            .Where(a => a.pathIndex < currentPathIndex - keepBehindCount)
            .ToList();

        foreach (var anchor in anchorsToRemove)
        {
            if (anchor.visualObject != null)
            {
                Destroy(anchor.visualObject);
            }
            activeAnchors.Remove(anchor);
        }
    }

    void OnDestroy()
    {
        ClearAllAnchors();
    }

    // ─────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────
    public int AnchorCount => activeAnchors.Count;
    public List<Vector3> AnchorPositions => activeAnchors.Select(a => a.worldPosition).ToList();
}
