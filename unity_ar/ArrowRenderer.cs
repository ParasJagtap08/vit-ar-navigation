/// ArrowRenderer.cs
/// Renders a 3D directional arrow in world space that always points
/// toward the next waypoint. The arrow is the primary visual guide
/// for the user during AR navigation.
///
/// The arrow is NOT a UI overlay — it exists in 3D world space and
/// is anchored relative to the camera with a stable offset.

using UnityEngine;

/// <summary>
/// Renders and animates a 3D directional arrow that guides the user
/// toward the next navigation waypoint.
/// 
/// Placement strategy:
/// - Positioned 1.5m in front of the camera
/// - Slightly below eye level (0.3m below camera)
/// - Smoothly rotates toward the next waypoint
/// - Pulses when near a turn
/// - Shows distance text on the arrow body
/// </summary>
public class ArrowRenderer : MonoBehaviour
{
    // ─────────────────────────────────────────────────────
    // Configuration
    // ─────────────────────────────────────────────────────
    [Header("Arrow Prefab")]
    [Tooltip("The 3D arrow prefab to instantiate")]
    [SerializeField] private GameObject arrowPrefab;

    [Header("Placement")]
    [Tooltip("Distance in front of camera to place arrow")]
    [SerializeField] private float forwardOffset = 1.5f;

    [Tooltip("Vertical offset below camera")]
    [SerializeField] private float verticalOffset = -0.3f;

    [Tooltip("Arrow scale")]
    [SerializeField] private float arrowScale = 0.15f;

    [Header("Animation")]
    [Tooltip("Rotation smoothing speed (higher = faster)")]
    [SerializeField] private float rotationSmoothing = 8.0f;

    [Tooltip("Position smoothing speed")]
    [SerializeField] private float positionSmoothing = 10.0f;

    [Tooltip("Pulse speed when near a turn")]
    [SerializeField] private float pulseSpeed = 3.0f;

    [Tooltip("Pulse scale multiplier")]
    [SerializeField] private float pulseAmplitude = 0.2f;

    [Header("Colors")]
    [SerializeField] private Color normalColor = new Color(0f, 0.85f, 1f, 0.9f);    // Cyan
    [SerializeField] private Color nearTurnColor = new Color(1f, 0.6f, 0f, 0.95f);  // Orange
    [SerializeField] private Color arrivedColor = new Color(0.2f, 1f, 0.4f, 0.95f);  // Green

    // ─────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────
    private GameObject arrowInstance;
    private Renderer arrowMeshRenderer;
    private MaterialPropertyBlock propertyBlock;

    private Vector3 targetDirection;
    private Vector3 currentDirection;
    private Vector3 smoothedPosition;
    private bool isVisible = false;
    private bool isNearTurn = false;
    private float distanceToTarget = 0f;

    private Camera arCamera;

    // ─────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────

    void Awake()
    {
        arCamera = Camera.main;
        propertyBlock = new MaterialPropertyBlock();
    }

    void Start()
    {
        CreateArrowInstance();
    }

    void LateUpdate()
    {
        if (!isVisible || arrowInstance == null) return;
        UpdateArrowTransform();
        UpdateArrowAppearance();
    }

    // ─────────────────────────────────────────────────────
    // Arrow Creation
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Create the arrow instance from prefab.
    /// If no prefab is assigned, creates a simple procedural arrow.
    /// </summary>
    private void CreateArrowInstance()
    {
        if (arrowPrefab != null)
        {
            arrowInstance = Instantiate(arrowPrefab, transform);
        }
        else
        {
            // Create a simple procedural arrow (cone + cylinder)
            arrowInstance = CreateProceduralArrow();
        }

        arrowInstance.transform.localScale = Vector3.one * arrowScale;
        arrowMeshRenderer = arrowInstance.GetComponentInChildren<Renderer>();
        arrowInstance.SetActive(false);
    }

    /// <summary>
    /// Creates a simple arrow from Unity primitives.
    /// Used as fallback when no custom prefab is provided.
    /// </summary>
    private GameObject CreateProceduralArrow()
    {
        var arrowRoot = new GameObject("ProceduralArrow");
        arrowRoot.transform.SetParent(transform);

        // Arrow shaft (cylinder)
        var shaft = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        shaft.transform.SetParent(arrowRoot.transform);
        shaft.transform.localPosition = new Vector3(0, 0, -0.3f);
        shaft.transform.localRotation = Quaternion.Euler(90, 0, 0);
        shaft.transform.localScale = new Vector3(0.15f, 0.4f, 0.15f);
        Destroy(shaft.GetComponent<Collider>());

        // Arrow head (cone approximation using stretched sphere)
        var head = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        head.transform.SetParent(arrowRoot.transform);
        head.transform.localPosition = new Vector3(0, 0, 0.3f);
        head.transform.localScale = new Vector3(0.4f, 0.4f, 0.6f);
        Destroy(head.GetComponent<Collider>());

        // Apply material
        var mat = new Material(Shader.Find("Universal Render Pipeline/Lit"));
        mat.color = normalColor;
        mat.SetFloat("_Surface", 1); // Transparent
        mat.SetFloat("_Blend", 0);
        mat.renderQueue = 3000;

        shaft.GetComponent<Renderer>().material = mat;
        head.GetComponent<Renderer>().material = mat;

        return arrowRoot;
    }

    // ─────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Update the arrow to point from the user's position toward the next waypoint.
    /// Should be called every frame during navigation.
    /// </summary>
    /// <param name="userPosition">Current user position (AR world space)</param>
    /// <param name="nextWaypoint">Next waypoint position (AR world space)</param>
    public void UpdateArrow(Vector3 userPosition, Vector3 nextWaypoint)
    {
        // Calculate direction to next waypoint
        Vector3 direction = nextWaypoint - userPosition;
        direction.y = 0; // Project onto horizontal plane for cleaner arrow rotation
        targetDirection = direction.normalized;
        distanceToTarget = direction.magnitude;

        // Determine if we're near a turn (arrow should pulse)
        isNearTurn = distanceToTarget < 5.0f;
    }

    /// <summary>
    /// Show the arrow.
    /// </summary>
    public void Show()
    {
        isVisible = true;
        if (arrowInstance != null)
        {
            arrowInstance.SetActive(true);
        }
    }

    /// <summary>
    /// Hide the arrow.
    /// </summary>
    public void Hide()
    {
        isVisible = false;
        if (arrowInstance != null)
        {
            arrowInstance.SetActive(false);
        }
    }

    /// <summary>
    /// Show destination reached animation (arrow turns green and pulses).
    /// </summary>
    public void ShowDestinationReached()
    {
        if (arrowMeshRenderer != null)
        {
            propertyBlock.SetColor("_BaseColor", arrivedColor);
            arrowMeshRenderer.SetPropertyBlock(propertyBlock);
        }

        // Scale up and fade out over 2 seconds
        StartCoroutine(DestinationReachedAnimation());
    }

    // ─────────────────────────────────────────────────────
    // Transform Updates
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Smoothly update arrow position and rotation.
    /// The arrow stays in front of the camera but points toward the waypoint.
    /// </summary>
    private void UpdateArrowTransform()
    {
        if (arCamera == null) return;

        // Target position: offset from camera
        Vector3 targetPos = arCamera.transform.position
            + arCamera.transform.forward * forwardOffset
            + Vector3.up * verticalOffset;

        // Smooth position
        smoothedPosition = Vector3.Lerp(
            smoothedPosition,
            targetPos,
            Time.deltaTime * positionSmoothing
        );
        arrowInstance.transform.position = smoothedPosition;

        // Smooth rotation toward target direction
        if (targetDirection.sqrMagnitude > 0.001f)
        {
            Quaternion targetRotation = Quaternion.LookRotation(targetDirection, Vector3.up);
            arrowInstance.transform.rotation = Quaternion.Slerp(
                arrowInstance.transform.rotation,
                targetRotation,
                Time.deltaTime * rotationSmoothing
            );
        }
    }

    /// <summary>
    /// Update arrow appearance (color, pulse, etc.) based on state.
    /// </summary>
    private void UpdateArrowAppearance()
    {
        if (arrowMeshRenderer == null) return;

        // Pulse animation when near a turn
        if (isNearTurn)
        {
            float pulse = 1.0f + Mathf.Sin(Time.time * pulseSpeed) * pulseAmplitude;
            arrowInstance.transform.localScale = Vector3.one * arrowScale * pulse;

            Color lerpColor = Color.Lerp(normalColor, nearTurnColor,
                Mathf.PingPong(Time.time * 2f, 1f));
            propertyBlock.SetColor("_BaseColor", lerpColor);
            arrowMeshRenderer.SetPropertyBlock(propertyBlock);
        }
        else
        {
            arrowInstance.transform.localScale = Vector3.one * arrowScale;
            propertyBlock.SetColor("_BaseColor", normalColor);
            arrowMeshRenderer.SetPropertyBlock(propertyBlock);
        }
    }

    // ─────────────────────────────────────────────────────
    // Animations
    // ─────────────────────────────────────────────────────

    private System.Collections.IEnumerator DestinationReachedAnimation()
    {
        float duration = 2.0f;
        float elapsed = 0f;
        Vector3 startScale = arrowInstance.transform.localScale;
        Vector3 endScale = startScale * 1.5f;

        while (elapsed < duration)
        {
            elapsed += Time.deltaTime;
            float t = elapsed / duration;

            // Scale up
            arrowInstance.transform.localScale = Vector3.Lerp(startScale, endScale, t);

            // Fade out
            Color fadedColor = arrivedColor;
            fadedColor.a = Mathf.Lerp(1f, 0f, t);
            propertyBlock.SetColor("_BaseColor", fadedColor);
            arrowMeshRenderer.SetPropertyBlock(propertyBlock);

            yield return null;
        }

        Hide();
    }

    // ─────────────────────────────────────────────────────
    // Cleanup
    // ─────────────────────────────────────────────────────

    void OnDestroy()
    {
        if (arrowInstance != null)
        {
            Destroy(arrowInstance);
        }
    }
}
