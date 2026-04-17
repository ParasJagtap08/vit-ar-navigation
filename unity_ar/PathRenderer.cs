/// PathRenderer.cs
/// Renders the navigation path as a glowing line in AR world space.
///
/// The path is rendered using Unity's LineRenderer with a custom shader
/// that creates a glowing, pulsating effect. Segments behind the user
/// fade out, giving a clear visual indication of progress.

using UnityEngine;
using System;
using System.Collections;
using System.Collections.Generic;

/// <summary>
/// Renders the navigation path as a 3D line in AR world space.
/// 
/// Features:
/// - Catmull-Rom spline interpolation for smooth curves
/// - Gradient coloring (bright ahead, faded behind)
/// - Animated "flow" effect along the path
/// - Occlusion awareness (path dips at doorways)
/// - Progressive fade-in/fade-out for path transitions
/// </summary>
public class PathRenderer : MonoBehaviour
{
    // ─────────────────────────────────────────────────────
    // Configuration
    // ─────────────────────────────────────────────────────
    [Header("Path Appearance")]
    [Tooltip("Width of the path line")]
    [SerializeField] private float lineWidth = 0.05f;

    [Tooltip("Height offset above the floor")]
    [SerializeField] private float floorOffset = 0.02f;

    [Tooltip("Number of interpolation points per segment")]
    [SerializeField] private int splineResolution = 8;

    [Header("Colors")]
    [SerializeField] private Color pathColor = new Color(0f, 0.85f, 1f, 0.8f);        // Cyan
    [SerializeField] private Color pathColorBehind = new Color(0f, 0.4f, 0.5f, 0.3f); // Faded cyan
    [SerializeField] private Color pathColorDestination = new Color(0.2f, 1f, 0.4f, 0.9f); // Green end

    [Header("Animation")]
    [Tooltip("Speed of the flow animation along the path")]
    [SerializeField] private float flowSpeed = 2.0f;

    [Tooltip("Length of the flow pulse")]
    [SerializeField] private float flowLength = 3.0f;

    // ─────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────
    private LineRenderer lineRenderer;
    private List<Vector3> rawWaypoints = new List<Vector3>();
    private List<Vector3> interpolatedPoints = new List<Vector3>();
    private int activeSegmentStartIndex = 0;
    private float totalPathLength = 0f;
    private Material pathMaterial;

    // ─────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────

    void Awake()
    {
        CreateLineRenderer();
    }

    void Update()
    {
        if (lineRenderer != null && lineRenderer.positionCount > 0)
        {
            UpdateFlowAnimation();
        }
    }

    // ─────────────────────────────────────────────────────
    // Initialization
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Create and configure the LineRenderer component.
    /// </summary>
    private void CreateLineRenderer()
    {
        lineRenderer = gameObject.GetComponent<LineRenderer>();
        if (lineRenderer == null)
        {
            lineRenderer = gameObject.AddComponent<LineRenderer>();
        }

        // Create a custom material for the path
        pathMaterial = new Material(Shader.Find("Universal Render Pipeline/Unlit"));
        pathMaterial.color = pathColor;
        pathMaterial.renderQueue = 3100; // Render on top of most things

        lineRenderer.material = pathMaterial;
        lineRenderer.startWidth = lineWidth;
        lineRenderer.endWidth = lineWidth;
        lineRenderer.useWorldSpace = true;
        lineRenderer.numCornerVertices = 4;
        lineRenderer.numCapVertices = 4;
        lineRenderer.alignment = LineAlignment.TransformZ;

        // Set up gradient
        UpdateLineGradient();

        // Initially hidden
        lineRenderer.positionCount = 0;
    }

    // ─────────────────────────────────────────────────────
    // Path Management
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Set a new path to render.
    /// Interpolates waypoints using Catmull-Rom splines for smooth curves.
    /// </summary>
    /// <param name="waypoints">World-space waypoint positions</param>
    public void SetPath(List<Vector3> waypoints)
    {
        rawWaypoints = new List<Vector3>(waypoints);

        if (waypoints.Count < 2)
        {
            ClearPath();
            return;
        }

        // Apply floor offset
        for (int i = 0; i < rawWaypoints.Count; i++)
        {
            rawWaypoints[i] = new Vector3(
                rawWaypoints[i].x,
                rawWaypoints[i].y + floorOffset,
                rawWaypoints[i].z
            );
        }

        // Interpolate with Catmull-Rom splines
        interpolatedPoints = InterpolatePath(rawWaypoints);

        // Calculate total length
        totalPathLength = 0f;
        for (int i = 1; i < interpolatedPoints.Count; i++)
        {
            totalPathLength += Vector3.Distance(interpolatedPoints[i - 1], interpolatedPoints[i]);
        }

        // Set LineRenderer positions
        lineRenderer.positionCount = interpolatedPoints.Count;
        lineRenderer.SetPositions(interpolatedPoints.ToArray());

        UpdateLineGradient();
    }

    /// <summary>
    /// Clear the path visualization.
    /// </summary>
    public void ClearPath()
    {
        lineRenderer.positionCount = 0;
        rawWaypoints.Clear();
        interpolatedPoints.Clear();
    }

    /// <summary>
    /// Set the active segment (fades segments behind this index).
    /// </summary>
    /// <param name="segmentIndex">Waypoint index the user is currently at</param>
    public void SetActiveSegment(int segmentIndex)
    {
        activeSegmentStartIndex = segmentIndex * splineResolution;
        UpdateLineGradient();
    }

    /// <summary>
    /// Update path rendering based on user's current position.
    /// Fades segments that are behind the user.
    /// </summary>
    /// <param name="userPosition">Current user position</param>
    public void UpdateUserPosition(Vector3 userPosition)
    {
        if (interpolatedPoints.Count == 0) return;

        // Find nearest point on path
        float minDist = float.MaxValue;
        int nearestIndex = 0;

        for (int i = 0; i < interpolatedPoints.Count; i++)
        {
            float dist = Vector3.Distance(userPosition, interpolatedPoints[i]);
            if (dist < minDist)
            {
                minDist = dist;
                nearestIndex = i;
            }
        }

        activeSegmentStartIndex = nearestIndex;
        UpdateLineGradient();
    }

    // ─────────────────────────────────────────────────────
    // Spline Interpolation
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Interpolate waypoints using Catmull-Rom splines.
    /// Produces smooth curves through all waypoints.
    /// </summary>
    private List<Vector3> InterpolatePath(List<Vector3> points)
    {
        var result = new List<Vector3>();

        if (points.Count < 2) return new List<Vector3>(points);
        if (points.Count == 2)
        {
            // Simple linear interpolation for 2 points
            for (int j = 0; j <= splineResolution; j++)
            {
                float t = j / (float)splineResolution;
                result.Add(Vector3.Lerp(points[0], points[1], t));
            }
            return result;
        }

        for (int i = 0; i < points.Count - 1; i++)
        {
            // Get 4 control points for Catmull-Rom
            Vector3 p0 = i > 0 ? points[i - 1] : points[i];
            Vector3 p1 = points[i];
            Vector3 p2 = points[i + 1];
            Vector3 p3 = i + 2 < points.Count ? points[i + 2] : points[i + 1];

            for (int j = 0; j < splineResolution; j++)
            {
                float t = j / (float)splineResolution;
                result.Add(CatmullRom(p0, p1, p2, p3, t));
            }
        }

        // Add the last point
        result.Add(points[points.Count - 1]);

        return result;
    }

    /// <summary>
    /// Catmull-Rom spline interpolation.
    /// </summary>
    private Vector3 CatmullRom(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, float t)
    {
        float t2 = t * t;
        float t3 = t2 * t;

        return 0.5f * (
            (2f * p1) +
            (-p0 + p2) * t +
            (2f * p0 - 5f * p1 + 4f * p2 - p3) * t2 +
            (-p0 + 3f * p1 - 3f * p2 + p3) * t3
        );
    }

    // ─────────────────────────────────────────────────────
    // Visual Updates
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Update the line gradient to fade behind the user.
    /// </summary>
    private void UpdateLineGradient()
    {
        if (interpolatedPoints.Count == 0) return;

        var gradient = new Gradient();
        float activeStart = interpolatedPoints.Count > 0
            ? (float)activeSegmentStartIndex / interpolatedPoints.Count
            : 0f;

        // Clamp
        activeStart = Mathf.Clamp01(activeStart);

        var colorKeys = new GradientColorKey[]
        {
            new GradientColorKey(pathColorBehind, 0f),             // Start (already passed)
            new GradientColorKey(pathColor, Mathf.Max(0.01f, activeStart)),    // Current position
            new GradientColorKey(pathColor, Mathf.Min(0.99f, 0.8f)),           // Most of remaining path
            new GradientColorKey(pathColorDestination, 1f)         // Destination
        };

        var alphaKeys = new GradientAlphaKey[]
        {
            new GradientAlphaKey(0.1f, 0f),                              // Faded behind
            new GradientAlphaKey(0.9f, Mathf.Max(0.01f, activeStart)),   // Current
            new GradientAlphaKey(0.7f, 0.9f),                            // Near end
            new GradientAlphaKey(1.0f, 1f)                               // Destination
        };

        gradient.SetKeys(colorKeys, alphaKeys);
        lineRenderer.colorGradient = gradient;
    }

    /// <summary>
    /// Animate a "flow" effect along the path (pulsing brightness
    /// that travels from user toward destination).
    /// </summary>
    private void UpdateFlowAnimation()
    {
        if (pathMaterial == null) return;

        // Use material texture offset to create flow effect
        float offset = Time.time * flowSpeed;
        pathMaterial.mainTextureOffset = new Vector2(offset, 0);
    }

    // ─────────────────────────────────────────────────────
    // Transitions
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Fade out the path over a duration, then invoke a callback.
    /// </summary>
    public void FadeOut(float duration, Action onComplete = null)
    {
        StartCoroutine(FadeCoroutine(1f, 0f, duration, onComplete));
    }

    /// <summary>
    /// Fade in the path over a duration.
    /// </summary>
    public void FadeIn(float duration)
    {
        StartCoroutine(FadeCoroutine(0f, 1f, duration, null));
    }

    private IEnumerator FadeCoroutine(float fromAlpha, float toAlpha, float duration, Action onComplete)
    {
        float elapsed = 0f;

        while (elapsed < duration)
        {
            elapsed += Time.deltaTime;
            float t = elapsed / duration;
            float alpha = Mathf.Lerp(fromAlpha, toAlpha, t);

            Color color = pathMaterial.color;
            color.a = alpha;
            pathMaterial.color = color;

            yield return null;
        }

        onComplete?.Invoke();
    }

    /// <summary>
    /// Show completion effect (path turns green and pulses).
    /// </summary>
    public void ShowCompleted()
    {
        var gradient = new Gradient();
        gradient.SetKeys(
            new GradientColorKey[] {
                new GradientColorKey(pathColorDestination, 0f),
                new GradientColorKey(pathColorDestination, 1f)
            },
            new GradientAlphaKey[] {
                new GradientAlphaKey(1f, 0f),
                new GradientAlphaKey(1f, 1f)
            }
        );
        lineRenderer.colorGradient = gradient;
    }

    // ─────────────────────────────────────────────────────
    // Cleanup
    // ─────────────────────────────────────────────────────

    void OnDestroy()
    {
        if (pathMaterial != null)
        {
            Destroy(pathMaterial);
        }
    }
}
