# Snapshot camera service on Android 8.1/API 27

## Android camera implementation and lifecycle

### Takeaway

Implement one bounded, single-shot native service behind a Dart-facing abstraction. Prefer Camera2 (available from API 21) for the normal path, but probe capabilities and retain a serialized Camera API1 adapter for robot/OEM cameras whose Camera2 metadata or session configuration is unusable. A snapshot should be acquired only while the app is foreground/visible on API 27; do not imply that an arbitrary background MCP request can start camera access.

### Cited Findings

- Android documents Camera2 as the low-level replacement for the deprecated `android.hardware.Camera` API, with both Camera2 and CameraX supporting API 21+. Camera2 provides more control but requires device-specific configuration; Google recommends CameraX for most ordinary apps. [Android Camera2 overview](https://developer.android.com/media/camera/camera2)
- Camera API1 is deprecated since API 21. Its documented sequence is open camera, configure parameters, attach a preview surface, start preview, take the picture asynchronously, then stop/release; preview must be started before `takePicture()`, and camera resources should be released in `onPause()` and reopened in `onResume()`. [Android `Camera` reference](https://developer.android.com/reference/android/hardware/Camera)
- Camera API1 is not thread-safe and is intended for one event thread. Callbacks run on the event thread used by `open()`, and Android warns not to assume camera specifications because devices differ in megapixels and autofocus capabilities. [Android `Camera` reference](https://developer.android.com/reference/android/hardware/Camera)
- Android runtime permissions require declaring `android.permission.CAMERA`, checking permission every time the protected operation is performed, requesting it in context after the user invokes the feature, handling the asynchronous result, and degrading gracefully after denial. [Request runtime permissions](https://developer.android.com/training/permissions/requesting)
- The permission documentation specifically recommends explaining camera/microphone access and making sensitive access apparent rather than collecting data surreptitiously. [Request runtime permissions](https://developer.android.com/training/permissions/requesting)
- API 27 is Android 8.1 and predates Android 10 multi-resume and Android 14 foreground-service type enforcement. Nevertheless, the safe policy is foreground-only capture: require an attached/resumed Activity (or an explicitly designed foreground service), reject requests when the app is backgrounded, and cancel/release on pause. Camera API1 explicitly documents this lifecycle requirement. [Android `Camera` reference](https://developer.android.com/reference/android/hardware/Camera)
- For newer target/device combinations, Android documents that camera foreground services require camera permission and that camera access is subject to while-in-use restrictions; a camera FGS cannot generally be created from background. This reinforces “foreground or explicit user-visible service,” not autonomous hidden capture, as the portable policy. [Foreground service types: camera](https://developer.android.com/develop/background-work/services/fgs/service-types)
- Camera2 sessions can contain a preview surface and an `ImageReader` surface; a still request uses `TEMPLATE_STILL_CAPTURE` and must target a surface configured when the session was created. [Camera2 capture sessions and requests](https://developer.android.com/training/camera2/capture-sessions-requests)
- `ImageReader` queues images until acquired; failing to close acquired `Image` objects can exhaust the queue and stall the producer. `acquireLatestImage()` drops older frames and is suitable for real-time/snapshot use, while `maxImages` should be kept minimal. [Android `ImageReader` reference](https://developer.android.com/reference/android/media/ImageReader)
- Camera2 orientation depends on sensor orientation, lens facing, and device/display rotation. Android gives the formula `rotation = (sensorOrientation - deviceRotation * sign + 360) % 360`, where `sign` is `1` for front-facing and `-1` for back-facing cameras. [Camera2 preview orientation](https://developer.android.com/training/camera2/camera-preview)
- Camera API1's `setDisplayOrientation()` affects preview/displayed picture but does not change JPEG byte ordering; callers must handle the captured JPEG's orientation separately. [Android `Camera#setDisplayOrientation`](https://developer.android.com/reference/android/hardware/Camera#setDisplayOrientation(int))
- Android's app-specific cache directory is private, needs no storage permission, may be deleted by the OS, and should still be explicitly cleaned by the app. `File.createTempFile(..., context.cacheDir)` is the documented pattern. [App-specific storage: cache files](https://developer.android.com/training/data-storage/app-specific#internal-create-cache)
- MCP tool results support text, image content, and resource links; image content is represented as base64 in the protocol example, while resource links can return a URI. Tool servers must validate inputs, rate-limit invocations, sanitize outputs, and clients should use timeouts and validate results. [MCP Tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)

### Inferences

- Use an interface such as `SnapshotCamera.capture(request): SnapshotResult`, with implementations `Camera2SnapshotCamera` and `Camera1SnapshotCamera`. A capability probe should first enumerate camera IDs, inspect Camera2 characteristics/output sizes, and attempt a short open/session configuration. On `ERROR_CAMERA_DEVICE`, malformed metadata, unsupported JPEG size, session configuration failure, or OEM-specific crash, close every Camera2 resource and try Camera1 once; do not loop indefinitely.
- For API 27, avoid CameraX solely as an assumed fix for unusual robot hardware: CameraX is a useful default when its backend works, but the app needs a native escape hatch because Camera2 itself is explicitly device-configuration-sensitive. Keep the fallback isolated behind the same contract so Flutter and MCP do not know which backend ran.
- Prefer a headless Camera2 still pipeline using `ImageReader` with `ImageFormat.JPEG`, a bounded supported size, and `maxImages = 2`. On image callback, acquire exactly one image, copy its plane bytes to a temp file, close the `Image` in `finally`, then close reader/session/device. Never pass a live preview stream to Dart for this tool.
- Request a single JPEG at a conservative default (for example, the largest supported size under a documented pixel/byte ceiling, rather than unbounded “maximum”). If the device rejects it, retry at most once with the next smaller supported size. Record actual width, height, byte count, rotation, backend, and elapsed time in the result.
- Normalize orientation before handing the artifact to downstream vision: set Camera2 `JPEG_ORIENTATION` when supported and/or apply a verified EXIF/pixel transform after capture; for Camera1, compute display/JPEG orientation from camera info and device rotation and explicitly normalize. Treat a missing or contradictory orientation as `ORIENTATION_UNKNOWN`, not as zero.
- A file is created in `cacheDir` with a random name and mode private. Return only a short-lived opaque reference (for example `vision://snapshot/<nonce>` mapped to an in-process registry) to trusted local consumers; delete it after upload/vision processing, on timeout/cancellation, and on service shutdown. At startup, delete stale files matching the service prefix older than a short TTL. Do not expose arbitrary filesystem paths to the model or remote peer.
- Serialize captures with a mutex/single-flight guard. Reject concurrent requests rather than queueing unbounded work. Use a hard deadline (suggested design value: 5 seconds end-to-end, with a shorter camera-open/capture sub-deadline), cancellation, and a maximum output byte/pixel limit.

### Gaps

- No public Visbot-specific camera HAL contract was found in the sources consulted. Camera selection, sensor orientation, supported sizes, autofocus behavior, and whether Camera2 is actually usable must be discovered on hardware and recorded in a device quirk table.
- Android's current foreground-service page describes later API levels; it does not establish a special API-27 camera background exemption. The design should therefore test the actual robot image/target SDK and preserve foreground-only behavior unless the platform owner explicitly validates a visible foreground service path.

## Flutter boundary and testability

### Takeaway

Keep camera ownership, permissions, threading, JPEG normalization, and temporary-file lifecycle native. Flutter should call one asynchronous method with a JSON-like map and receive a small metadata map; it should never receive camera byte arrays or depend on a preview widget for MCP capture.

### Cited Findings

- Flutter platform channels pass asynchronous messages between Dart and host code. `MethodChannel` is the low-level method-call mechanism; standard codecs support strings, numbers, byte buffers, lists, and maps. [Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)
- Flutter says channel method invocation must occur on the platform main thread, while handlers may be moved to a background thread when appropriate. [Flutter platform channels: threading](https://docs.flutter.dev/platform-integration/platform-channels#channels-and-platform-threading)
- Flutter's official camera plugin supports still snapshots saved to a file, but lifecycle changes are no longer handled by the plugin: the app must dispose resources on inactive and reinitialize on resumed. Permission failures are surfaced as explicit camera access errors. [Flutter camera package](https://pub.dev/packages/camera)
- The Flutter camera package currently supports Android SDK 24+, so it can cover API 27, but its endorsed Android implementation is CameraX and the package documents limitations and a Camera2 implementation choice. [Flutter camera package](https://pub.dev/packages/camera)

### Inferences

- Recommended channel: `MethodChannel("self.vision/camera")`, methods `getCapabilities`, `captureSnapshot`, `deleteSnapshot`, and `cleanupStaleSnapshots`. `captureSnapshot` arguments should be bounded and validated: `{cameraId?: String, facing?: "back"|"front"|"external", maxWidth?: int, maxHeight?: int, quality?: int, timeoutMs?: int, purpose?: String}`. Clamp dimensions/quality/timeouts natively; reject unknown keys if strict validation is desired.
- Result contract (no base64):

  ```json
  {
    "ok": true,
    "reference": "vision://snapshot/opaque-id",
    "mimeType": "image/jpeg",
    "width": 1280,
    "height": 720,
    "rotation": 0,
    "bytes": 183421,
    "backend": "camera2",
    "capturedAtEpochMs": 0,
    "expiresAtEpochMs": 0
  }
  ```

  `reference` is resolvable only by the local vision/upload adapter. If the caller needs a user-visible image, a separate trusted adapter may publish a resource link; the MethodChannel itself should not marshal JPEG bytes.
- Channel errors should use stable codes (`camera_permission_denied`, `camera_backgrounded`, `camera_unavailable`, `camera_busy`, `camera_timeout`, `camera_configuration`, `camera_capture`, `image_invalid`, `storage_full`, `cancelled`, `unsupported`) and a human-readable message plus safe details (`backend`, `cameraId`, `retryable`). Never include permission tokens, API keys, or full local paths in errors/logs.
- Native classes should be dependency-injected: `PermissionChecker`, `LifecycleState`, `CameraBackendFactory`, `Clock`, `TempFileStore`, and `VisionReferenceStore`. Unit-test the request validator, size chooser, orientation formula, state machine, error mapping, TTL cleanup, and single-flight behavior without Android camera hardware.
- Use Android instrumentation tests with a fake camera provider where possible, plus physical API-27 robot tests for permission grant/deny, pause/resume, camera contention, malformed OEM metadata, each rotation, low storage, and process death. Test both Camera2 and API1 adapters against the same contract; a golden JPEG/EXIF fixture can verify rotation normalization.
- The Dart wrapper should map `PlatformException.code` to typed domain errors and expose `Future<SnapshotResult> captureSnapshot(...)`. It should observe `AppLifecycleState`; it may proactively reject while inactive, but native code must re-check lifecycle and permission because Dart state can race with an Activity transition.

### Gaps

- The current repository's exact Android activity/plugin registration and existing upload/reference conventions require source inspection before choosing Java versus Kotlin and the final channel name. The contract above deliberately avoids coupling to either.

## `self.vision.capture` MCP contract and failure matrix

### Takeaway

Expose `self.vision.capture` as a one-shot, bounded observation tool, not a camera-control or autonomous surveillance primitive. It should return concise text plus an opaque image/resource reference, never raw base64 in the normal app path, and it must fail closed when consent, foreground state, bounds, or cleanup cannot be guaranteed.

### Cited Findings

- MCP tools are model-controlled, but the specification says there should generally be a human in the loop able to deny invocations and that clients should show tool inputs/indicators for sensitive operations. [MCP Tools: user interaction model](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- MCP requires servers to validate tool inputs, implement access controls, rate-limit calls, and sanitize outputs; clients should implement timeouts and validate results. [MCP Tools: security considerations](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- MCP permits text, image content, and resource links in tool results. The specification's image example uses base64, but a resource link is also a protocol-supported result type. [MCP Tools: tool result content](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)

### Inferences

- Proposed tool schema:

  ```json
  {
    "name": "self.vision.capture",
    "description": "Capture one bounded still image from the robot camera for the current user-requested observation. Does not monitor, loop, move the robot, or capture in the background.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "prompt": {"type": "string", "maxLength": 300},
        "camera": {"type": "string", "enum": ["default", "front", "back", "external"]},
        "maxWidth": {"type": "integer", "minimum": 320, "maximum": 1920},
        "maxHeight": {"type": "integer", "minimum": 240, "maximum": 1080},
        "timeoutMs": {"type": "integer", "minimum": 500, "maximum": 5000}
      },
      "required": ["prompt"],
      "additionalProperties": false
    }
  }
  ```

- Enforce one invocation per request, one JPEG, no retry loop visible to MCP, no continuous stream, no motion/actuator side effects, a strict timeout, and a rate limit/cooldown (suggested design value: one capture per 10 seconds unless a user explicitly repeats). Require a visible/user-authorized session and a camera permission; if the app is inactive/backgrounded, return `camera_backgrounded` rather than silently launching a service.
- Normal success result should be text such as `Captured one JPEG (1280x720, rotation 0°, camera2, 183 KB), reference expires in 60 seconds.` plus a local/trusted `resource_link` such as `vision://snapshot/<opaque-id>`. If the downstream MCP transport cannot safely carry a resource link, return text only with a stable reference and let the trusted vision/upload layer fetch it; do not expand to base64 merely for convenience.
- Failure matrix:

  | Condition | Native/channel code | MCP result | Retry | Cleanup/side effect |
  |---|---|---|---|---|
  | Camera permission denied/permanently denied | `camera_permission_denied` | `isError: true`, explain permission required | No automatic retry; user may grant in settings | No camera open; no file |
  | App not resumed/visible | `camera_backgrounded` | Error; state capture requires foreground | Only after foreground/user action | Release any pending camera; delete temp |
  | Request exceeds dimensions/timeout/unknown args | `invalid_arguments` | Error; show allowed bounds | No | No camera open |
  | Another capture in progress | `camera_busy` | Error; “try again later” | Caller may retry once after cooldown | Existing request owns its file |
  | No camera or selected camera unavailable | `camera_unavailable` | Error with capability summary | No blind retry; allow another camera only if user requested | Close partial backend |
  | Camera2 metadata/session fails | `camera_configuration` | Error only after bounded Camera1 fallback | Fallback once; no loop | Close Camera2 device/session/reader |
  | Camera1 open/takePicture fails | `camera_capture` | Error; backend diagnostics omitted from user text | At most one controlled retry | `release()` camera; delete temp |
  | Capture deadline expires | `camera_timeout` | Error; no image reference | No automatic retry | Cancel request, close backend, delete temp |
  | JPEG missing/invalid/oversize | `image_invalid` | Error; image not published | Maybe one smaller-size retry inside native bound | Delete invalid file |
  | Orientation unsupported/ambiguous | `orientation_unknown` | Error or explicit “rotation unknown” only if consumer accepts it | No autonomous guessing | Delete or quarantine only until TTL |
  | Cache write/full/permission failure | `storage_full` | Error; no reference | Caller may retry after cleanup | Delete partial file; retain no path |
  | Vision/upload layer unavailable | `reference_unavailable` | Text-only capture metadata or error according to policy | No camera re-capture by default | Delete after TTL; no base64 fallback |
  | Cancellation/process death | `cancelled` | Error/no result | User may invoke again | `finally` cleanup plus startup stale sweep |

- Log an audit event with request ID, timestamp, selected backend, camera ID, result code, dimensions, byte count, and duration; do not log image bytes, full paths, prompt contents if sensitive, or secrets. The MCP result should not disclose implementation stack traces or arbitrary filesystem paths.

### Gaps

- MCP does not itself prescribe a robot-camera consent UX, a local `vision://` URI scheme, or a retention period. The 60-second reference TTL, 10-second cooldown, and 5-second timeout above are proposed safety defaults for the design and must be confirmed with product/privacy owners and the actual MCP transport.
- The MCP specification permits base64 image content, so “no base64” is an application policy for bounded transport/privacy and memory use, not a protocol limitation. A future trusted gateway may choose another representation, but it must preserve the tool's one-shot and access-control guarantees.
