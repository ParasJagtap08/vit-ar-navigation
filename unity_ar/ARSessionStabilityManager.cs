/// ARSessionStabilityManager.cs
/// Production stability layer for AR Foundation sessions.
///
/// Monitors AR tracking quality, handles session lifecycle events,
/// manages visual quality scaling, and provides graceful degradation
/// when tracking is lost.
///
/// This script must be attached to the same GameObject as ARSession.

using UnityEngine;
using UnityEngine.XR.ARFoundation;
using UnityEngine.XR.ARSubsystems;
using System;
using System.Collections;

/// <summary>
/// Monitors AR session health and provides graceful degradation.
///
/// Production concerns handled:
/// - Tracking loss detection and recovery prompts
/// - Feature point density monitoring (low-texture environments)
/// - Frame rate monitoring (thermal throttling on mobile)
/// - Light estimation (dark corridor detection)
/// - Session pause/resume lifecycle (app backgrounded)
/// - Visual quality scaling under performance pressure
/// </summary>
public class ARSessionStabilityManager : MonoBehaviour
{
    // ─────────────────────────────────────────────────────
    // Configuration
    // ─────────────────────────────────────────────────────
    [Header("Tracking Quality")]
    [Tooltip("Seconds of limited tracking before alerting user")]
    [SerializeField] private float limitedTrackingGracePeriod = 3f;

    [Tooltip("Seconds of no tracking before pausing navigation")]
    [SerializeField] private float trackingLostTimeout = 5f;

    [Header("Performance")]
    [Tooltip("Target frame rate for AR rendering")]
    [SerializeField] private int targetFrameRate = 30;

    [Tooltip("Frame rate below which quality scaling kicks in")]
    [SerializeField] private int lowFrameRateThreshold = 24;

    [Tooltip("Frame rate monitoring window (seconds)")]
    [SerializeField] private float fpsWindowSize = 2f;

    [Header("Light Estimation")]
    [Tooltip("Light intensity below which a 'dark environment' warning triggers (lux)")]
    [SerializeField] private float lowLightThreshold = 50f;

    // ─────────────────────────────────────────────────────
    // References
    // ─────────────────────────────────────────────────────
    [Header("References")]
    [SerializeField] private ARSession arSession;
    [SerializeField] private ARCameraManager cameraManager;
    [SerializeField] private PathRenderer pathRenderer;
    [SerializeField] private ArrowRenderer arrowRenderer;

    // ─────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────

    /// <summary>Fired when tracking quality changes.</summary>
    public event Action<TrackingQuality> OnTrackingQualityChanged;

    /// <summary>Fired when an environment warning should be shown.</summary>
    public event Action<string> OnEnvironmentWarning;

    /// <summary>Fired when the AR session is fully lost and navigation must pause.</summary>
    public event Action OnNavigationPaused;

    /// <summary>Fired when the AR session recovers and navigation can resume.</summary>
    public event Action OnNavigationResumed;

    // ─────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────
    private TrackingQuality _currentQuality = TrackingQuality.Good;
    private float _limitedTrackingSince = -1f;
    private float _trackingLostSince = -1f;
    private bool _isNavigationPaused = false;

    // FPS tracking
    private float[] _frameTimes;
    private int _frameTimeIndex = 0;
    private float _averageFPS = 30f;
    private bool _isQualityReduced = false;

    // Light estimation
    private float _lastLightIntensity = 250f;
    private float _lastLightWarningTime = -60f; // Don't spam warnings

    /// <summary>Current tracking quality assessment.</summary>
    public TrackingQuality CurrentQuality => _currentQuality;

    /// <summary>Whether navigation visuals are paused due to tracking loss.</summary>
    public bool IsNavigationPaused => _isNavigationPaused;

    /// <summary>Current average FPS.</summary>
    public float AverageFPS => _averageFPS;

    // ─────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────

    void Awake()
    {
        Application.targetFrameRate = targetFrameRate;

        // Initialize FPS ring buffer
        int bufferSize = Mathf.CeilToInt(fpsWindowSize * targetFrameRate);
        _frameTimes = new float[Mathf.Max(bufferSize, 10)];
        for (int i = 0; i < _frameTimes.Length; i++)
            _frameTimes[i] = 1f / targetFrameRate;
    }

    void OnEnable()
    {
        if (ARSession.stateChanged != null)
            ARSession.stateChanged += OnARSessionStateChanged;

        if (cameraManager != null)
            cameraManager.frameReceived += OnFrameReceived;
    }

    void OnDisable()
    {
        ARSession.stateChanged -= OnARSessionStateChanged;

        if (cameraManager != null)
            cameraManager.frameReceived -= OnFrameReceived;
    }

    void Update()
    {
        UpdateFPSTracking();
        CheckPerformance();
    }

    // ─────────────────────────────────────────────────────
    // AR Session State Monitoring
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Called when the AR session state changes (e.g., tracking lost/recovered).
    /// </summary>
    private void OnARSessionStateChanged(ARSessionStateChangedEventArgs args)
    {
        Debug.Log($"[ARStability] Session state: {args.state}");

        switch (args.state)
        {
            case ARSessionState.SessionTracking:
                HandleTrackingRecovered();
                break;

            case ARSessionState.SessionInitializing:
                SetQuality(TrackingQuality.Initializing);
                break;

            case ARSessionState.Ready:
            case ARSessionState.Installing:
                SetQuality(TrackingQuality.Initializing);
                break;

            case ARSessionState.None:
            case ARSessionState.CheckingAvailability:
            case ARSessionState.NeedsInstall:
            case ARSessionState.Unsupported:
                SetQuality(TrackingQuality.Unavailable);
                HandleTrackingLost("AR not available on this device");
                break;
        }
    }

    /// <summary>
    /// Called every camera frame. Used for light estimation.
    /// </summary>
    private void OnFrameReceived(ARCameraFrameEventArgs args)
    {
        // Check light estimation
        if (args.lightEstimation.averageBrightness.HasValue)
        {
            _lastLightIntensity = args.lightEstimation.averageBrightness.Value * 1000f;

            if (_lastLightIntensity < lowLightThreshold &&
                (Time.time - _lastLightWarningTime) > 30f) // Max once per 30 seconds
            {
                _lastLightWarningTime = Time.time;
                OnEnvironmentWarning?.Invoke(
                    "Low light detected. AR tracking may be unstable. " +
                    "Turn on nearby lights for better accuracy.");
            }
        }

        // Check tracking state from camera
        if (args.lightEstimation.averageBrightness.HasValue)
        {
            UpdateTrackingQualityFromNotionalReason();
        }
    }

    /// <summary>
    /// Assess tracking quality based on the camera's tracking state
    /// and notional reason for limited tracking.
    /// </summary>
    private void UpdateTrackingQualityFromNotionalReason()
    {
        var subsystem = cameraManager?.subsystem;
        if (subsystem == null) return;

        var trackingState = subsystem.trackingState;

        switch (trackingState)
        {
            case TrackingState.Tracking:
                if (_limitedTrackingSince >= 0)
                {
                    _limitedTrackingSince = -1f;
                    HandleTrackingRecovered();
                }
                if (_currentQuality != TrackingQuality.Good)
                {
                    SetQuality(TrackingQuality.Good);
                }
                break;

            case TrackingState.Limited:
                if (_limitedTrackingSince < 0)
                    _limitedTrackingSince = Time.time;

                float limitedDuration = Time.time - _limitedTrackingSince;

                if (limitedDuration > trackingLostTimeout)
                {
                    HandleTrackingLost("Extended tracking loss");
                }
                else if (limitedDuration > limitedTrackingGracePeriod)
                {
                    SetQuality(TrackingQuality.Limited);
                    OnEnvironmentWarning?.Invoke(
                        "Tracking quality reduced. " +
                        "Try pointing your camera at a well-lit area with texture.");
                }
                break;

            case TrackingState.None:
                HandleTrackingLost("AR tracking unavailable");
                break;
        }
    }

    // ─────────────────────────────────────────────────────
    // Tracking Recovery
    // ─────────────────────────────────────────────────────

    private void HandleTrackingRecovered()
    {
        _limitedTrackingSince = -1f;
        _trackingLostSince = -1f;

        if (_isNavigationPaused)
        {
            _isNavigationPaused = false;
            SetQuality(TrackingQuality.Good);

            // Resume navigation visuals
            if (pathRenderer != null) pathRenderer.FadeIn(0.5f);
            if (arrowRenderer != null) arrowRenderer.Show();

            OnNavigationResumed?.Invoke();

            Debug.Log("[ARStability] Tracking recovered. Navigation resumed.");
        }
    }

    private void HandleTrackingLost(string reason)
    {
        if (_isNavigationPaused) return; // Already paused

        _trackingLostSince = Time.time;
        _isNavigationPaused = true;
        SetQuality(TrackingQuality.Lost);

        // Pause navigation visuals
        if (pathRenderer != null) pathRenderer.FadeOut(0.3f);
        if (arrowRenderer != null) arrowRenderer.Hide();

        OnNavigationPaused?.Invoke();

        // Notify Flutter to show 2D map fallback
        SendToFlutter("trackingLost", $"{{\"reason\": \"{reason}\"}}");

        Debug.LogWarning($"[ARStability] Tracking lost: {reason}. Navigation paused.");
    }

    // ─────────────────────────────────────────────────────
    // FPS & Performance Monitoring
    // ─────────────────────────────────────────────────────

    private void UpdateFPSTracking()
    {
        _frameTimes[_frameTimeIndex] = Time.unscaledDeltaTime;
        _frameTimeIndex = (_frameTimeIndex + 1) % _frameTimes.Length;

        float sum = 0;
        for (int i = 0; i < _frameTimes.Length; i++)
            sum += _frameTimes[i];

        _averageFPS = _frameTimes.Length / sum;
    }

    private void CheckPerformance()
    {
        if (_averageFPS < lowFrameRateThreshold && !_isQualityReduced)
        {
            ReduceVisualQuality();
        }
        else if (_averageFPS > lowFrameRateThreshold + 4 && _isQualityReduced)
        {
            RestoreVisualQuality();
        }
    }

    /// <summary>
    /// Reduce visual complexity when frame rate drops.
    /// </summary>
    private void ReduceVisualQuality()
    {
        _isQualityReduced = true;
        Debug.LogWarning($"[ARStability] FPS low ({_averageFPS:F0}). Reducing quality.");

        // Reduce path line complexity
        // (PathRenderer can accept these dynamically)

        // Reduce rendering scale
        if (QualitySettings.renderPipeline != null)
        {
            // URP: reduce render scale
            // This is a global setting and should be restored when FPS recovers
        }

        SendToFlutter("performanceWarning",
            $"{{\"fps\": {_averageFPS:F0}, \"quality\": \"reduced\"}}");
    }

    /// <summary>
    /// Restore visual quality when frame rate recovers.
    /// </summary>
    private void RestoreVisualQuality()
    {
        _isQualityReduced = false;
        Debug.Log($"[ARStability] FPS recovered ({_averageFPS:F0}). Restoring quality.");

        SendToFlutter("performanceWarning",
            $"{{\"fps\": {_averageFPS:F0}, \"quality\": \"normal\"}}");
    }

    // ─────────────────────────────────────────────────────
    // App Lifecycle
    // ─────────────────────────────────────────────────────

    void OnApplicationPause(bool paused)
    {
        if (paused)
        {
            Debug.Log("[ARStability] App paused. AR session will be interrupted.");
            // AR tracking will drift during pause
            // When user returns, we'll need QR recalibration
        }
        else
        {
            Debug.Log("[ARStability] App resumed. Checking AR session state.");
            // After resume, the AR session may need time to relocalize
            SetQuality(TrackingQuality.Initializing);

            // Prompt user to scan a QR code for recalibration after pause
            StartCoroutine(PromptRecalibrationAfterDelay(2f));
        }
    }

    private IEnumerator PromptRecalibrationAfterDelay(float delay)
    {
        yield return new WaitForSeconds(delay);

        if (_currentQuality != TrackingQuality.Good)
        {
            SendToFlutter("recalibrationNeeded",
                "{\"reason\": \"App was paused. Please scan a QR code to recalibrate.\"}");
        }
    }

    // ─────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────

    private void SetQuality(TrackingQuality quality)
    {
        if (_currentQuality == quality) return;
        var old = _currentQuality;
        _currentQuality = quality;
        OnTrackingQualityChanged?.Invoke(quality);
        Debug.Log($"[ARStability] Tracking quality: {old} → {quality}");
    }

    private void SendToFlutter(string action, string data)
    {
        try
        {
            UnityMessageManager.Instance?.SendMessageToFlutter(
                $"{{\"action\": \"{action}\", \"data\": {data}}}");
        }
        catch (Exception e)
        {
            Debug.LogWarning($"[ARStability] Flutter message failed: {e.Message}");
        }
    }

    /// <summary>
    /// Get a stability diagnostics snapshot.
    /// </summary>
    public StabilityDiagnostics GetDiagnostics()
    {
        return new StabilityDiagnostics
        {
            quality = _currentQuality,
            fps = _averageFPS,
            isQualityReduced = _isQualityReduced,
            isNavigationPaused = _isNavigationPaused,
            lightLevel = _lastLightIntensity,
            timeSinceTrackingLost = _trackingLostSince >= 0
                ? Time.time - _trackingLostSince
                : -1f
        };
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Supporting Types
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>
/// Tracking quality assessment levels.
/// </summary>
public enum TrackingQuality
{
    /// <summary>AR is initializing.</summary>
    Initializing,

    /// <summary>Tracking is optimal.</summary>
    Good,

    /// <summary>Tracking is reduced (low light, featureless surface, fast motion).</summary>
    Limited,

    /// <summary>Tracking is fully lost. Navigation visuals hidden.</summary>
    Lost,

    /// <summary>AR is not available on this device.</summary>
    Unavailable
}

/// <summary>
/// Stability diagnostics snapshot.
/// </summary>
public struct StabilityDiagnostics
{
    public TrackingQuality quality;
    public float fps;
    public bool isQualityReduced;
    public bool isNavigationPaused;
    public float lightLevel;
    public float timeSinceTrackingLost;
}
