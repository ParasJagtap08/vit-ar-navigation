/// CoordinateMapper.cs
/// Production-grade coordinate mapping engine for translating between
/// the building's local coordinate system and AR world space.
///
/// This is the most critical component for AR accuracy. A bad transform
/// means arrows pointing at walls and paths floating in mid-air.
///
/// The system supports:
/// - Single-QR registration (minimum viable — translation only)
/// - Dual-QR registration (rotation + translation, production-grade)
/// - Multi-QR refinement (least-squares optimal, highest accuracy)
/// - Continuous VIO drift compensation via anchor re-observation
///
/// Coordinate Systems:
///   BUILDING SPACE: Right-handed. X=East, Y=Up, Z=North. Origin at SW corner.
///   AR WORLD SPACE: Right-handed. Defined by ARCore/ARKit on session start.
///   Both use meters.

using UnityEngine;
using System.Collections.Generic;
using System.Linq;

/// <summary>
/// Maps between the building's local coordinate system and the AR session's
/// world coordinate system. Maintains a rigid-body transform (rotation +
/// translation, no scaling) derived from QR anchor observations.
/// </summary>
public class CoordinateMapper : MonoBehaviour
{
    // ─────────────────────────────────────────────────────
    // Configuration
    // ─────────────────────────────────────────────────────
    [Header("Configuration")]
    [Tooltip("Minimum observations before transform is considered stable")]
    [SerializeField] private int minObservationsForStable = 2;

    [Tooltip("Maximum registration error (meters) before warning")]
    [SerializeField] private float maxAcceptableError = 0.3f;

    [Tooltip("Exponential smoothing factor for transform updates (0=no smooth, 1=instant)")]
    [SerializeField] private float smoothingFactor = 0.3f;

    // ─────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// The active rigid transform: building coords → AR world coords.
    /// T_ba such that p_ar = T_ba * p_building
    /// </summary>
    private Matrix4x4 _buildingToAR = Matrix4x4.identity;

    /// <summary>
    /// Inverse transform: AR world coords → building coords.
    /// </summary>
    private Matrix4x4 _arToBuilding = Matrix4x4.identity;

    /// <summary>Registration quality state.</summary>
    private RegistrationState _state = RegistrationState.Unregistered;

    /// <summary>All QR observations used to compute the current transform.</summary>
    private List<AnchorObservation> _observations = new List<AnchorObservation>();

    /// <summary>Current registration error (meters RMS).</summary>
    private float _registrationError = float.MaxValue;

    /// <summary>Timestamp of last registration update.</summary>
    private float _lastUpdateTime = 0f;

    // ─────────────────────────────────────────────────────
    // Public Properties
    // ─────────────────────────────────────────────────────

    /// <summary>Current registration state.</summary>
    public RegistrationState State => _state;

    /// <summary>Whether the mapper has a valid transform.</summary>
    public bool IsRegistered => _state != RegistrationState.Unregistered;

    /// <summary>Whether the transform is considered stable (≥2 observations).</summary>
    public bool IsStable => _state == RegistrationState.Stable;

    /// <summary>Current registration error in meters (RMS across observations).</summary>
    public float RegistrationError => _registrationError;

    /// <summary>Number of QR observations used in the current transform.</summary>
    public int ObservationCount => _observations.Count;

    // ─────────────────────────────────────────────────────
    // Core: Registration from QR Scan
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Register a single QR anchor observation.
    ///
    /// This is called when the user scans a QR code. The observation provides
    /// a correspondence between a known building-space position and the
    /// AR-space position where the QR code was detected.
    ///
    /// With 1 observation: translation-only registration (assumes axes aligned).
    /// With 2+ observations: full rotation + translation registration.
    /// </summary>
    /// <param name="buildingPosition">QR anchor position in building coordinates</param>
    /// <param name="arPose">AR world-space pose where the QR code was detected</param>
    /// <param name="qrOrientationYaw">QR code's facing direction in building space (degrees)</param>
    /// <returns>Updated registration quality info</returns>
    public RegistrationResult RegisterAnchor(
        Vector3 buildingPosition,
        Pose arPose,
        float qrOrientationYaw = 0f)
    {
        var observation = new AnchorObservation
        {
            buildingPos = buildingPosition,
            arPos = arPose.position,
            arRot = arPose.rotation,
            qrYawDeg = qrOrientationYaw,
            timestamp = Time.time
        };

        _observations.Add(observation);
        _lastUpdateTime = Time.time;

        // Compute transform based on the number of observations
        if (_observations.Count == 1)
        {
            ComputeSinglePointTransform(observation);
            _state = RegistrationState.Coarse;
        }
        else
        {
            ComputeMultiPointTransform();
            _state = _observations.Count >= minObservationsForStable
                ? RegistrationState.Stable
                : RegistrationState.Refining;
        }

        // Compute the inverse
        _arToBuilding = _buildingToAR.inverse;

        // Calculate registration error
        _registrationError = ComputeRegistrationError();

        return new RegistrationResult
        {
            state = _state,
            errorMeters = _registrationError,
            observationCount = _observations.Count,
            isAcceptable = _registrationError <= maxAcceptableError
        };
    }

    // ─────────────────────────────────────────────────────
    // Core: Coordinate Transforms
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Transform a position from building space to AR world space.
    /// </summary>
    /// <param name="buildingPos">Position in building coordinates</param>
    /// <returns>Position in AR world coordinates</returns>
    public Vector3 BuildingToAR(Vector3 buildingPos)
    {
        if (!IsRegistered)
        {
            Debug.LogWarning("[CoordMapper] No registration. Returning raw position.");
            return buildingPos;
        }
        return _buildingToAR.MultiplyPoint3x4(buildingPos);
    }

    /// <summary>
    /// Transform a position from AR world space to building space.
    /// </summary>
    /// <param name="arPos">Position in AR world coordinates</param>
    /// <returns>Position in building coordinates</returns>
    public Vector3 ARToBuilding(Vector3 arPos)
    {
        if (!IsRegistered)
        {
            Debug.LogWarning("[CoordMapper] No registration. Returning raw position.");
            return arPos;
        }
        return _arToBuilding.MultiplyPoint3x4(arPos);
    }

    /// <summary>
    /// Transform a direction vector from building space to AR world space.
    /// (Translation not applied — direction only.)
    /// </summary>
    public Vector3 BuildingToARDirection(Vector3 buildingDir)
    {
        if (!IsRegistered) return buildingDir;
        return _buildingToAR.MultiplyVector(buildingDir);
    }

    /// <summary>
    /// Transform a full pose from building space to AR world space.
    /// </summary>
    public Pose BuildingToARPose(Vector3 buildingPos, Quaternion buildingRot)
    {
        if (!IsRegistered) return new Pose(buildingPos, buildingRot);

        Vector3 arPos = _buildingToAR.MultiplyPoint3x4(buildingPos);
        // Extract rotation from the transform matrix
        Quaternion transformRot = _buildingToAR.rotation;
        Quaternion arRot = transformRot * buildingRot;

        return new Pose(arPos, arRot);
    }

    /// <summary>
    /// Transform an array of waypoints from building space to AR world space.
    /// Batch operation to avoid repeated matrix decomposition.
    /// </summary>
    public Vector3[] BuildingToARBatch(Vector3[] buildingPositions)
    {
        if (!IsRegistered) return buildingPositions;

        var result = new Vector3[buildingPositions.Length];
        for (int i = 0; i < buildingPositions.Length; i++)
        {
            result[i] = _buildingToAR.MultiplyPoint3x4(buildingPositions[i]);
        }
        return result;
    }

    // ─────────────────────────────────────────────────────
    // Transform Computation: Single Point
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Compute a translation-only transform from a single QR observation.
    ///
    /// This assumes that the building coordinate axes are roughly aligned
    /// with the AR session axes (no rotation). This is the minimum viable
    /// registration but requires the user to start the AR session facing
    /// the same direction as the building's +Z axis.
    ///
    /// For a single-QR scan, we use the QR code's orientation to also
    /// compute the yaw rotation between the two coordinate systems.
    ///
    /// Math:
    ///   T = Translation(AR_pos) × Rotation(yaw_offset) × Translation(-Building_pos)
    ///   Where yaw_offset = QR_ar_yaw - QR_building_yaw
    /// </summary>
    private void ComputeSinglePointTransform(AnchorObservation obs)
    {
        // Extract the yaw rotation of the QR code in AR space
        float arYaw = obs.arRot.eulerAngles.y;
        float buildingYaw = obs.qrYawDeg;

        // The yaw offset tells us how much the building coordinate system
        // is rotated relative to the AR session's coordinate system
        float yawOffset = arYaw - buildingYaw;
        Quaternion rotationOffset = Quaternion.Euler(0, yawOffset, 0);

        // Apply rotation to building position to get the expected AR position
        Vector3 rotatedBuildingPos = rotationOffset * obs.buildingPos;

        // Translation = AR_pos - Rotated_building_pos
        Vector3 translation = obs.arPos - rotatedBuildingPos;

        // Build the transform: first rotate, then translate
        _buildingToAR = Matrix4x4.TRS(translation, rotationOffset, Vector3.one);

        Debug.Log($"[CoordMapper] Single-point registration: " +
                  $"yawOffset={yawOffset:F1}°, translation={translation}");
    }

    // ─────────────────────────────────────────────────────
    // Transform Computation: Multi-Point (Rigid Body)
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Compute a rigid-body transform (rotation + translation) from
    /// multiple QR observations using the method of centroids.
    ///
    /// This finds the rotation R and translation t that minimizes:
    ///   Σ ||AR_i - (R × Building_i + t)||²
    ///
    /// For 2D (yaw-only) rotation in building navigation, we project
    /// onto the XZ plane and solve for the optimal yaw angle.
    ///
    /// Algorithm:
    /// 1. Compute centroid of building points and AR points
    /// 2. Subtract centroids (center the point clouds)
    /// 3. Compute the 2D cross-covariance matrix (XZ plane)
    /// 4. Extract optimal yaw angle via atan2
    /// 5. Compute translation from centroid alignment
    ///
    /// This is a closed-form solution — no iterative optimization needed.
    /// </summary>
    private void ComputeMultiPointTransform()
    {
        int n = _observations.Count;

        // Step 1: Compute centroids
        Vector3 centroidBuilding = Vector3.zero;
        Vector3 centroidAR = Vector3.zero;

        foreach (var obs in _observations)
        {
            centroidBuilding += obs.buildingPos;
            centroidAR += obs.arPos;
        }
        centroidBuilding /= n;
        centroidAR /= n;

        // Step 2: Center the point clouds
        // Step 3: Compute 2D cross-covariance (XZ plane only)
        // We solve for yaw rotation only (pitch/roll assumed near-zero in buildings)
        float sxx = 0, sxz = 0, szx = 0, szz = 0;

        foreach (var obs in _observations)
        {
            Vector3 b = obs.buildingPos - centroidBuilding; // centered building
            Vector3 a = obs.arPos - centroidAR;             // centered AR

            sxx += b.x * a.x;
            sxz += b.x * a.z;
            szx += b.z * a.x;
            szz += b.z * a.z;
        }

        // Step 4: Optimal yaw angle
        // For 2D rotation [cos θ, -sin θ; sin θ, cos θ]:
        //   θ = atan2(szx - sxz, sxx + szz)
        float yawRad = Mathf.Atan2(szx - sxz, sxx + szz);
        float yawDeg = yawRad * Mathf.Rad2Deg;

        Quaternion rotation = Quaternion.Euler(0, yawDeg, 0);

        // Step 5: Translation = centroid_AR - R × centroid_Building
        Vector3 rotatedCentroid = rotation * centroidBuilding;
        Vector3 translation = centroidAR - rotatedCentroid;

        // Apply exponential smoothing if we already have a transform
        if (_state != RegistrationState.Unregistered && _state != RegistrationState.Coarse)
        {
            // Smooth the new transform with the old one
            Vector3 oldTranslation = _buildingToAR.GetColumn(3);
            Quaternion oldRotation = _buildingToAR.rotation;

            translation = Vector3.Lerp(oldTranslation, translation, smoothingFactor);
            rotation = Quaternion.Slerp(oldRotation, rotation, smoothingFactor);
        }

        _buildingToAR = Matrix4x4.TRS(translation, rotation, Vector3.one);

        Debug.Log($"[CoordMapper] Multi-point registration ({n} obs): " +
                  $"yaw={yawDeg:F1}°, translation={translation}, " +
                  $"error={ComputeRegistrationError():F3}m");
    }

    // ─────────────────────────────────────────────────────
    // Error Metrics
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Compute RMS registration error across all observations.
    /// This measures how well the current transform maps known building
    /// positions to their observed AR positions.
    /// </summary>
    /// <returns>RMS error in meters</returns>
    private float ComputeRegistrationError()
    {
        if (_observations.Count == 0) return float.MaxValue;

        float sumSqError = 0;
        foreach (var obs in _observations)
        {
            Vector3 predicted = _buildingToAR.MultiplyPoint3x4(obs.buildingPos);
            float error = Vector3.Distance(predicted, obs.arPos);
            sumSqError += error * error;
        }

        return Mathf.Sqrt(sumSqError / _observations.Count);
    }

    /// <summary>
    /// Get per-observation error breakdown for diagnostics.
    /// </summary>
    public List<(int index, float errorMeters)> GetPerObservationErrors()
    {
        var errors = new List<(int, float)>();
        for (int i = 0; i < _observations.Count; i++)
        {
            var obs = _observations[i];
            Vector3 predicted = _buildingToAR.MultiplyPoint3x4(obs.buildingPos);
            float error = Vector3.Distance(predicted, obs.arPos);
            errors.Add((i, error));
        }
        return errors;
    }

    // ─────────────────────────────────────────────────────
    // VIO Drift Compensation
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Apply a drift correction to the current transform.
    ///
    /// Called when VIO drift is detected (e.g., a re-observed QR code
    /// shows the transform has shifted). Instead of recomputing from
    /// scratch, this applies an incremental correction.
    ///
    /// This is gentler than full re-registration and avoids visual
    /// jumps in the AR path when the transform updates.
    /// </summary>
    /// <param name="measuredDrift">Translation drift detected (AR space)</param>
    /// <param name="correctionStrength">0.0 to 1.0, how much to correct</param>
    public void ApplyDriftCorrection(Vector3 measuredDrift, float correctionStrength = 0.3f)
    {
        if (!IsRegistered) return;

        Vector3 correction = measuredDrift * correctionStrength;
        Vector3 currentTranslation = _buildingToAR.GetColumn(3);
        Quaternion currentRotation = _buildingToAR.rotation;

        Vector3 newTranslation = currentTranslation + (Vector4)new Vector4(
            correction.x, correction.y, correction.z, 0);

        _buildingToAR = Matrix4x4.TRS(newTranslation, currentRotation, Vector3.one);
        _arToBuilding = _buildingToAR.inverse;

        Debug.Log($"[CoordMapper] Drift correction applied: {correction} " +
                  $"(strength={correctionStrength:F2})");
    }

    // ─────────────────────────────────────────────────────
    // Reset & Cleanup
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Reset all registration data. Call when the AR session resets
    /// or when moving to a different building.
    /// </summary>
    public void Reset()
    {
        _buildingToAR = Matrix4x4.identity;
        _arToBuilding = Matrix4x4.identity;
        _state = RegistrationState.Unregistered;
        _observations.Clear();
        _registrationError = float.MaxValue;

        Debug.Log("[CoordMapper] Registration reset.");
    }

    /// <summary>
    /// Remove stale observations older than maxAge seconds.
    /// Useful in long navigation sessions where VIO drift accumulates.
    /// </summary>
    public void PruneStaleObservations(float maxAgeSeconds = 300f)
    {
        float cutoff = Time.time - maxAgeSeconds;
        int removed = _observations.RemoveAll(o => o.timestamp < cutoff);

        if (removed > 0)
        {
            Debug.Log($"[CoordMapper] Pruned {removed} stale observations. " +
                      $"Remaining: {_observations.Count}");

            if (_observations.Count == 0)
            {
                _state = RegistrationState.Unregistered;
            }
            else if (_observations.Count == 1)
            {
                ComputeSinglePointTransform(_observations[0]);
                _state = RegistrationState.Coarse;
            }
            else
            {
                ComputeMultiPointTransform();
            }
            _arToBuilding = _buildingToAR.inverse;
            _registrationError = ComputeRegistrationError();
        }
    }

    // ─────────────────────────────────────────────────────
    // Diagnostics
    // ─────────────────────────────────────────────────────

    /// <summary>
    /// Get a diagnostics snapshot for debugging UI.
    /// </summary>
    public MapperDiagnostics GetDiagnostics()
    {
        Vector3 translation = _buildingToAR.GetColumn(3);
        float yaw = _buildingToAR.rotation.eulerAngles.y;

        return new MapperDiagnostics
        {
            state = _state,
            observationCount = _observations.Count,
            errorRMS = _registrationError,
            yawDegrees = yaw,
            translation = translation,
            timeSinceLastUpdate = Time.time - _lastUpdateTime,
            isAcceptable = _registrationError <= maxAcceptableError
        };
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Supporting Types
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>
/// Quality state of the coordinate registration.
/// </summary>
public enum RegistrationState
{
    /// <summary>No registration. Coordinates are identity-mapped (unreliable).</summary>
    Unregistered,

    /// <summary>Single QR scan. Translation + yaw from one point. May drift.</summary>
    Coarse,

    /// <summary>2+ QR scans. Transform being refined. Accuracy improving.</summary>
    Refining,

    /// <summary>Sufficient observations. Transform is reliable.</summary>
    Stable
}

/// <summary>
/// A single QR anchor observation (correspondence point).
/// </summary>
[System.Serializable]
public struct AnchorObservation
{
    /// <summary>Known position in building coordinates.</summary>
    public Vector3 buildingPos;

    /// <summary>Detected position in AR world coordinates.</summary>
    public Vector3 arPos;

    /// <summary>Detected rotation in AR world coordinates.</summary>
    public Quaternion arRot;

    /// <summary>QR code's facing direction in building space (degrees).</summary>
    public float qrYawDeg;

    /// <summary>Time.time when this observation was recorded.</summary>
    public float timestamp;
}

/// <summary>
/// Result of a registration update.
/// </summary>
public struct RegistrationResult
{
    public RegistrationState state;
    public float errorMeters;
    public int observationCount;
    public bool isAcceptable;
}

/// <summary>
/// Diagnostics snapshot for the coordinate mapper.
/// </summary>
public struct MapperDiagnostics
{
    public RegistrationState state;
    public int observationCount;
    public float errorRMS;
    public float yawDegrees;
    public Vector3 translation;
    public float timeSinceLastUpdate;
    public bool isAcceptable;
}
