/// NavigationARController.cs
/// Main AR controller that bridges Flutter ↔ Unity communication
/// and orchestrates anchor placement, path rendering, and arrow updates.
///
/// This script is the single entry point for all navigation commands
/// sent from Flutter via flutter_unity_widget's postMessage API.

using UnityEngine;
using UnityEngine.XR.ARFoundation;
using UnityEngine.XR.ARSubsystems;
using System;
using System.Collections.Generic;
using System.Linq;

/// <summary>
/// Main controller for the AR navigation session.
/// Receives navigation commands from Flutter, manages the AR session,
/// and coordinates anchor placement, path rendering, and arrow updates.
/// </summary>
public class NavigationARController : MonoBehaviour
{
    // ─────────────────────────────────────────────────────
    // AR Foundation References
    // ─────────────────────────────────────────────────────
    [Header("AR Foundation")]
    [SerializeField] private ARSession arSession;
    [SerializeField] private ARSessionOrigin arSessionOrigin;
    [SerializeField] private ARCameraManager arCameraManager;
    [SerializeField] private ARRaycastManager arRaycastManager;
    [SerializeField] private ARAnchorManager arAnchorManager;

    // ─────────────────────────────────────────────────────
    // Sub-controllers
    // ─────────────────────────────────────────────────────
    [Header("Sub-Controllers")]
    [SerializeField] private AnchorManager anchorManager;
    [SerializeField] private ArrowRenderer arrowRenderer;
    [SerializeField] private PathRenderer pathRenderer;

    // ─────────────────────────────────────────────────────
    // Configuration
    // ─────────────────────────────────────────────────────
    [Header("Configuration")]
    [Tooltip("Maximum distance (meters) to show AR elements")]
    [SerializeField] private float maxRenderDistance = 15f;

    [Tooltip("Distance threshold to advance to next waypoint")]
    [SerializeField] private float waypointReachThreshold = 2.0f;

    [Tooltip("How often to update path visualization (seconds)")]
    [SerializeField] private float updateInterval = 0.1f;

    // ─────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────
    private List<Vector3> currentWaypoints = new List<Vector3>();
    private int currentWaypointIndex = 0;
    private bool isNavigating = false;
    private float lastUpdateTime = 0f;

    /// <summary>
    /// Transform matrix mapping building coordinates → AR world coordinates.
    /// Set when user scans a QR code.
    /// </summary>
    private Matrix4x4 buildingToARTransform = Matrix4x4.identity;
    private bool hasRegistration = false;

    // ─────────────────────────────────────────────────────
    // Events (for Unity-side listeners)
    // ─────────────────────────────────────────────────────
    public event Action<int> OnWaypointReached;
    public event Action OnDestinationReached;
    public event Action<float> OnDistanceUpdated;

    // ─────────────────────────────────────────────────────
    // Unity Lifecycle
    // ─────────────────────────────────────────────────────

    void Awake()
    {
        if (anchorManager == null) anchorManager = GetComponent<AnchorManager>();
        if (arrowRenderer == null) arrowRenderer = GetComponent<ArrowRenderer>();
        if (pathRenderer == null) pathRenderer = GetComponent<PathRenderer>();
    }

    void Update()
    {
        if (!isNavigating || currentWaypoints.Count == 0) return;

        if (Time.time - lastUpdateTime < updateInterval) return;
        lastUpdateTime = Time.time;

        UpdateNavigation();
    }

    // ─────────────────────────────────────────────────────
    // Flutter → Unity Message Handler
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Called by flutter_unity_widget when Flutter sends a message.
    /// Message format: JSON string with "action" and "data" fields.
    /// </summary>
    /// <param name="message">JSON message from Flutter</param>
    public void OnFlutterMessage(string message)
    {
        try
        {
            var msg = JsonUtility.FromJson<FlutterMessage>(message);

            switch (msg.action)
            {
                case "setPath":
                    HandleSetPath(msg.data);
                    break;
                case "updatePath":
                    HandleUpdatePath(msg.data);
                    break;
                case "stopNavigation":
                    HandleStopNavigation();
                    break;
                case "setRegistration":
                    HandleSetRegistration(msg.data);
                    break;
                case "setUserPosition":
                    HandleSetUserPosition(msg.data);
                    break;
                default:
                    Debug.LogWarning($"[NavAR] Unknown action: {msg.action}");
                    break;
            }
        }
        catch (Exception e)
        {
            Debug.LogError($"[NavAR] Error handling message: {e.Message}");
        }
    }

    // ─────────────────────────────────────────────────────
    // Message Handlers
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Sets a new navigation path. Called when user starts navigation
    /// or when path is recalculated.
    /// </summary>
    private void HandleSetPath(string data)
    {
        var pathData = JsonUtility.FromJson<PathData>(data);

        // Convert building coordinates to AR world coordinates
        currentWaypoints.Clear();
        foreach (var wp in pathData.waypoints)
        {
            Vector3 buildingPos = new Vector3(wp.x, wp.y, wp.z);
            Vector3 arPos = TransformBuildingToAR(buildingPos);
            currentWaypoints.Add(arPos);
        }

        currentWaypointIndex = 0;
        isNavigating = true;

        // Initialize path rendering
        pathRenderer.SetPath(currentWaypoints);
        pathRenderer.SetActiveSegment(0);

        // Place initial arrow
        if (currentWaypoints.Count >= 2)
        {
            arrowRenderer.Show();
            arrowRenderer.UpdateArrow(
                Camera.main.transform.position,
                currentWaypoints[1]
            );
        }

        // Send confirmation to Flutter
        SendToFlutter("navigationStarted", $"{{\"waypointCount\": {currentWaypoints.Count}}}");
    }

    /// <summary>
    /// Updates an existing path (rerouting). Preserves current progress
    /// and smoothly transitions to the new path.
    /// </summary>
    private void HandleUpdatePath(string data)
    {
        var pathData = JsonUtility.FromJson<PathData>(data);

        // Fade out old path
        pathRenderer.FadeOut(0.3f, () =>
        {
            // Set new waypoints
            currentWaypoints.Clear();
            foreach (var wp in pathData.waypoints)
            {
                Vector3 buildingPos = new Vector3(wp.x, wp.y, wp.z);
                currentWaypoints.Add(TransformBuildingToAR(buildingPos));
            }

            currentWaypointIndex = 0;
            pathRenderer.SetPath(currentWaypoints);
            pathRenderer.FadeIn(0.3f);
        });
    }

    /// <summary>
    /// Stops current navigation session and cleans up AR elements.
    /// </summary>
    private void HandleStopNavigation()
    {
        isNavigating = false;
        currentWaypoints.Clear();
        currentWaypointIndex = 0;

        arrowRenderer.Hide();
        pathRenderer.ClearPath();
        anchorManager.ClearAllAnchors();

        SendToFlutter("navigationStopped", "{}");
    }

    /// <summary>
    /// Sets the building-to-AR coordinate transform.
    /// Called after a QR code scan provides a registration point.
    /// </summary>
    private void HandleSetRegistration(string data)
    {
        var reg = JsonUtility.FromJson<RegistrationData>(data);

        // Build the transform matrix from the QR scan data
        // QR provides: building position of the anchor + AR pose of the detection
        Vector3 buildingPos = new Vector3(reg.buildingX, reg.buildingY, reg.buildingZ);
        Vector3 arPos = new Vector3(reg.arX, reg.arY, reg.arZ);
        Quaternion arRot = new Quaternion(reg.arQx, reg.arQy, reg.arQz, reg.arQw);

        // Compute registration transform: AR_pos = T × Building_pos
        // T = Translation(AR_pos - Building_pos) (simplified, rotation handled separately)
        Vector3 offset = arPos - buildingPos;
        buildingToARTransform = Matrix4x4.TRS(offset, Quaternion.identity, Vector3.one);
        hasRegistration = true;

        // If navigation is active, recompute waypoint positions
        if (isNavigating)
        {
            // Re-request path from Flutter with updated transform
            SendToFlutter("registrationUpdated", $"{{\"hasRegistration\": true}}");
        }
    }

    /// <summary>
    /// Updates the user's estimated position (from VIO tracking).
    /// Used for off-path detection on the Unity side.
    /// </summary>
    private void HandleSetUserPosition(string data)
    {
        // Position is tracked via ARCamera, this is for explicit override
        var pos = JsonUtility.FromJson<PositionData>(data);
        // Could be used for forced repositioning after floor transition
    }

    // ─────────────────────────────────────────────────────
    // Navigation Update Loop
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Core navigation update — called every updateInterval seconds.
    /// Handles waypoint advancement, arrow updates, and distance calculation.
    /// </summary>
    private void UpdateNavigation()
    {
        if (currentWaypoints.Count == 0 || currentWaypointIndex >= currentWaypoints.Count)
            return;

        Vector3 userPos = Camera.main.transform.position;
        Vector3 nextWaypoint = currentWaypoints[currentWaypointIndex];

        float distToWaypoint = Vector3.Distance(userPos, nextWaypoint);

        // Check if user reached current waypoint
        if (distToWaypoint < waypointReachThreshold)
        {
            currentWaypointIndex++;
            OnWaypointReached?.Invoke(currentWaypointIndex);

            // Check if destination reached
            if (currentWaypointIndex >= currentWaypoints.Count)
            {
                HandleDestinationReached();
                return;
            }

            // Update path visualization
            pathRenderer.SetActiveSegment(currentWaypointIndex);
            nextWaypoint = currentWaypoints[currentWaypointIndex];
        }

        // Update arrow direction
        arrowRenderer.UpdateArrow(userPos, nextWaypoint);

        // Update path rendering (fade passed segments)
        pathRenderer.UpdateUserPosition(userPos);

        // Calculate remaining distance
        float remainingDist = distToWaypoint;
        for (int i = currentWaypointIndex; i < currentWaypoints.Count - 1; i++)
        {
            remainingDist += Vector3.Distance(
                currentWaypoints[i],
                currentWaypoints[i + 1]
            );
        }

        OnDistanceUpdated?.Invoke(remainingDist);

        // Send distance update to Flutter
        SendToFlutter("distanceUpdate", $"{{\"remaining\": {remainingDist:F1}, \"waypointIndex\": {currentWaypointIndex}}}");

        // Check upcoming turn direction for instruction
        if (currentWaypointIndex < currentWaypoints.Count - 1)
        {
            string instruction = GetTurnInstruction(
                currentWaypointIndex > 0 ? currentWaypoints[currentWaypointIndex - 1] : userPos,
                nextWaypoint,
                currentWaypoints[currentWaypointIndex + 1]
            );

            float distToTurn = distToWaypoint;
            SendToFlutter("turnInstruction",
                $"{{\"instruction\": \"{instruction}\", \"distanceToTurn\": {distToTurn:F1}}}");
        }
    }

    /// <summary>
    /// Handle destination reached — show celebration animation and notify Flutter.
    /// </summary>
    private void HandleDestinationReached()
    {
        isNavigating = false;
        arrowRenderer.ShowDestinationReached();
        pathRenderer.ShowCompleted();
        OnDestinationReached?.Invoke();
        SendToFlutter("destinationReached", "{}");
    }

    // ─────────────────────────────────────────────────────
    // Coordinate Transformation
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Transform a position from building coordinates to AR world coordinates.
    /// Requires a valid registration (from QR scan).
    /// </summary>
    private Vector3 TransformBuildingToAR(Vector3 buildingPos)
    {
        if (!hasRegistration)
        {
            // Without registration, use a rough estimate
            // (AR origin ≈ building origin — only works if AR started at entrance)
            return buildingPos;
        }

        return buildingToARTransform.MultiplyPoint3x4(buildingPos);
    }

    /// <summary>
    /// Transform a position from AR world coordinates to building coordinates.
    /// </summary>
    private Vector3 TransformARToBuilding(Vector3 arPos)
    {
        if (!hasRegistration) return arPos;
        return buildingToARTransform.inverse.MultiplyPoint3x4(arPos);
    }

    // ─────────────────────────────────────────────────────
    // Turn Instructions
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Determine the turn instruction at a waypoint based on the
    /// angle between incoming and outgoing path segments.
    /// </summary>
    private string GetTurnInstruction(Vector3 prev, Vector3 current, Vector3 next)
    {
        Vector3 incoming = (current - prev).normalized;
        Vector3 outgoing = (next - current).normalized;

        // Project onto XZ plane (ignore vertical)
        incoming.y = 0;
        outgoing.y = 0;

        float angle = Vector3.SignedAngle(incoming, outgoing, Vector3.up);

        if (Mathf.Abs(angle) < 20f) return "Continue straight";
        if (angle > 20f && angle < 70f) return "Turn slightly right";
        if (angle >= 70f && angle < 110f) return "Turn right";
        if (angle >= 110f) return "Make a sharp right";
        if (angle < -20f && angle > -70f) return "Turn slightly left";
        if (angle <= -70f && angle > -110f) return "Turn left";
        if (angle <= -110f) return "Make a sharp left";

        return "Continue";
    }

    // ─────────────────────────────────────────────────────
    // Flutter Communication
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Send a message from Unity to Flutter.
    /// </summary>
    private void SendToFlutter(string action, string data)
    {
        // flutter_unity_widget receives this via onUnityMessage callback
        UnityMessageManager.Instance.SendMessageToFlutter(
            $"{{\"action\": \"{action}\", \"data\": {data}}}"
        );
    }

    // ─────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────

    public bool IsNavigating => isNavigating;
    public int CurrentWaypointIndex => currentWaypointIndex;
    public int TotalWaypoints => currentWaypoints.Count;
    public bool HasRegistration => hasRegistration;
}

// ─────────────────────────────────────────────────────────
// Message Data Classes
// ─────────────────────────────────────────────────────────

[Serializable]
public class FlutterMessage
{
    public string action;
    public string data;
}

[Serializable]
public class PathData
{
    public WaypointData[] waypoints;
}

[Serializable]
public class WaypointData
{
    public float x, y, z;
    public string nodeId;
    public string nodeType;
}

[Serializable]
public class RegistrationData
{
    public float buildingX, buildingY, buildingZ;
    public float arX, arY, arZ;
    public float arQx, arQy, arQz, arQw;
}

[Serializable]
public class PositionData
{
    public float x, y, z;
    public float confidence;
}
