# Visbot camera hardware/software options (research snapshot, 2026)

## 1. What is publicly documented about the robot camera hardware?

### Takeaway

Public material confirms that UBTECH commercial robots in the Cruzr family have integrated RGB/depth perception hardware and an Android/ROS software environment, but I found no reliable public specification tying those camera details to the exact Visbot unit in this repository. Therefore an integrated camera is plausible, not proven; the exact sensor node, lens, stream formats, Android camera ID, HAL capability, and whether the application is allowed to open it remain device-access questions.

### Cited Findings

- UBTECH's Cruzr presentation lists a 13 MP HD camera with 1080p video, one depth-perception camera, Android & ROS, and a separate LiDAR/sonar/IR/IMU sensor stack. This is evidence for a related UBTECH platform, not proof of Visbot's hardware. — [UBTECH Cruzr presentation PDF](https://www.generationrobots.com/media/cruzr-robot-presentation.pdf)
- The same published Cruzr material says the platform exposes an open SDK for custom applications, including facial recognition, but it does not document a generic public camera-frame API or Camera2 camera ID. — [UBTECH Cruzr presentation PDF](https://www.generationrobots.com/media/cruzr-robot-presentation.pdf)
- A Cruzr SDK integration guide shows Android integration and a legacy `android.hardware.Camera` `onPreviewFrame(byte[] data, Camera camera)` callback feeding NV21 frames to ArcSoft face detection. This is concrete evidence that at least one UBTECH Android robot SDK/application path has used Camera API1-style preview frames; it does not establish that Visbot exposes the same API or that its camera is free for a second client. — [Cruzr SDK Integration Guide](https://usermanual.wiki/Document/Cruzr20SDK20Integration20Guide.577788025.pdf)
- UBTECH's official co-creation platform describes Android/Java application development and an SDK/toolkit, but the public page does not publish Visbot camera interfaces or hardware identifiers. — [UBTECH Co-Creation Platform](https://open.ubtrobot.com/)
- UBTECH's 2023 annual-results announcement discusses self-developed binocular depth-camera kits and visual perception, but this is company-level technology disclosure rather than a Visbot specification. — [UBTECH 2023 annual results](https://owebsite-cdn.ubtrobot.com/resources/file/2024/04/12/535558081712197.pdf)
- Android's camera architecture distinguishes internal camera HALs from external-camera support; camera API behavior is determined by the device's HAL implementation and advertised characteristics, not by the Android version alone. — [AOSP camera versioning](https://source.android.com/docs/core/camera/versioning)

### Inferences

- The safest hardware hypothesis is “one or more vendor-integrated cameras, potentially including RGB-D/navigation cameras,” because related UBTECH products advertise them and the SDK has consumed preview frames. Treat “Visbot front RGB camera available to arbitrary apps” as an unverified hypothesis.
- A depth/navigation camera may be owned by ROS, a vendor service, or a privileged system process. Even if Android enumerates an RGB camera, it may be the interaction camera rather than the navigation/depth sensor.
- The old SDK guide's API1/NV21 example raises compatibility value for a Camera API1 fallback, while not proving that API1 is the only or best path on Visbot.

### Gaps

- No public Visbot-specific camera datasheet, teardown, camera sensor model, USB VID/PID, `/dev/video*` mapping, Android `CameraManager` output, `dumpsys media.camera`, `getCameraIdList()`, HAL level, or permission policy was found.
- Without the robot, shell access, or an OEM Visbot SDK/firmware package, it is impossible to conclude whether the camera is integrated, USB/UVC, vendor-private, already occupied, or accessible to this app.
- The Cruzr evidence must not be silently generalized to Visbot: model, firmware, board, Android build, and camera ownership may differ.

## 2. Which software stack fits Android 8.1/API 27 and armeabi-v7a?

### Takeaway

For an integrated camera, native Camera2 with an API1 fallback is the most diagnosable and controllable first implementation. Flutter's official camera plugin is viable for a normal app-facing camera if the current dependency set is pinned to an API-27-compatible release and the device behaves like a standard Camera2 device. USB/UVC is a contingency for an external camera, not a default assumption: AOSP's system external-camera provider is a device-build feature, and its Java `EXTERNAL` hardware level starts at API 28; on API 27, direct USB host/UVC work would require vendor support or an in-app UVC implementation/native library.

### Cited Findings

- Android Camera2 is the low-level replacement for deprecated `android.hardware.Camera`; both Camera2 and CameraX support Android 5.0/API 21+, while Camera2 requires the application to handle device-specific configurations. — [Android Camera2 documentation](https://developer.android.com/media/camera/camera2)
- A Camera2 device advertising `LEGACY` provides minimum Camera2 support and is approximately equivalent to the older Camera API; the documented hardware-level query is `CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL`. — [CameraDevice API reference](https://developer.android.com/reference/android/hardware/camera2/CameraDevice)
- AOSP's external USB-camera implementation requires `android.hardware.usb.host`, kernel UVC/media support (`CONFIG_USB_VIDEO_CLASS` and `CONFIG_MEDIA_USB_SUPPORT`), an external camera provider/HAL configuration, and SELinux/device-build integration. — [AOSP external USB cameras](https://source.android.com/docs/core/camera/external-usb-cameras)
- AOSP explicitly says the Java Camera2 `EXTERNAL` hardware level is included starting in API level 28. Consequently, Android 8.1/API 27 cannot be assumed to expose a UVC webcam through the normal Java Camera2 camera list, even if the kernel and USB host hardware support UVC. — [AOSP external USB cameras](https://source.android.com/docs/core/camera/external-usb-cameras)
- Android USB host mode has existed since API 12, but hardware support is optional. Applications use `UsbManager`/`UsbDevice`/`UsbDeviceConnection`, declare the USB-host feature, request user permission, and communicate with endpoints off the UI thread. — [Android USB host guide](https://developer.android.com/develop/connectivity/usb/host)
- The official Flutter `camera` package provides preview, still capture, video recording, and image-buffer streaming. Its 2026 package page lists Android SDK 24+ support; the endorsed Android implementation is CameraX, while `camera_android` is the Camera2 implementation. — [Flutter camera package](https://pub.dev/packages/camera)
- Flutter's Android camera implementation has historically required API 21 for Camera2 and does not itself make a nonstandard UVC camera appear; the plugin enumerates cameras exposed by Android's camera stack. — [Flutter camera Android source](https://github.com/flutter-team-archive/plugins/blob/main/packages/camera/camera_android/android/src/main/java/io/flutter/plugins/camera/CameraPlugin.java?plain=1)
- This repository currently sets `minSdk = 24` and restricts the APK to `armeabi-v7a`; that is compatible in principle with the current Flutter camera package's stated Android floor, but this is a repository fact and not evidence that Visbot's camera HAL works. — [Repository Android build configuration](https://github.com/tu-kimei/xiaozhi-android-client/blob/feat/visbot-next-phase/android/app/build.gradle.kts)

### Inferences

- **Native Camera2 (recommended first probe):** enumerate camera IDs, inspect `INFO_SUPPORTED_HARDWARE_LEVEL`, `REQUEST_AVAILABLE_CAPABILITIES`, stream configurations, lens facing, and YUV/JPEG sizes; open only a low resolution YUV stream initially. Add API1 fallback if Camera2 reports `LEGACY`, fails to configure a supported stream, or the vendor app only exposes API1 behavior. Native code avoids Dart image-copy overhead and makes vendor quirks/logging easier to diagnose.
- **Flutter `camera` plugin (good UI-layer option):** suitable after native probing confirms a normal app-facing camera. It is attractive for preview and image-stream wiring already used by a Flutter app, but frame delivery into Dart can add CPU/memory pressure on an old ARMv7 board. Pin a plugin version compatible with the project's Flutter/Dart/Gradle toolchain rather than blindly taking the 2026 latest release; test both the CameraX implementation and the Camera2 implementation if the plugin allows selection.
- **USB/UVC through Camera2:** possible only if Visbot's system image includes the AOSP external-camera provider (or a vendor equivalent). API 27 makes this route especially uncertain because the documented public `EXTERNAL` level begins at API 28.
- **Direct USB/UVC:** technically possible through API-12 USB host primitives if the robot has host hardware and the kernel exposes a usable UVC path, but the application must implement or bundle UVC streaming/decoding, handle permission/attachment, power, isochronous transfers, and ARMv7 native binaries. This is materially more work than integrated Camera2 and may be blocked by SELinux, missing kernel support, or lack of a USB port/OTG power budget.
- The three approaches are not interchangeable: Flutter camera is a wrapper over cameras Android exposes; native Camera2 is the direct public camera API; direct UVC bypasses the camera service and is a USB protocol/native-media project.

### Gaps

- The public Flutter package page does not guarantee that every current release can still be built with this project's exact Flutter 3.7-era SDK constraints, nor that all transitive AndroidX dependencies run correctly on this vendor Android 8.1 image.
- AOSP documentation describes how an OEM enables external UVC cameras; it does not prove that Visbot enabled that provider. API 27 may still support a vendor backport, but that would require device inspection.
- No reliable public evidence was found for a Visbot-specific UVC port, OTG mode, kernel config, SELinux policy, camera permission grant, or 32-bit ARMv7 UVC library.

## 3. What can be concluded now, and what must be tested on Visbot?

### Takeaway

The design should be capability-driven rather than model-driven: ship a probe/diagnostic layer first, prefer an integrated Android camera if enumerated, and retain an explicit “unsupported/owned by vendor” result. No source reviewed can establish camera availability or frame ownership on this particular robot without device access.

### Cited Findings

- Android's camera API exposes camera characteristics and hardware levels for runtime inspection; a `LEGACY` result means only minimum Camera2 behavior should be expected. — [CameraDevice API reference](https://developer.android.com/reference/android/hardware/camera2/CameraDevice)
- Android USB host support is hardware-dependent even though the API exists at API 12+, and applications must request access to a connected device before communication. — [Android USB host guide](https://developer.android.com/develop/connectivity/usb/host)
- AOSP's generic external USB camera path is intended for lightweight use cases and is not designed as a replacement for internal cameras or performance-intensive high-resolution/high-speed/AR workloads. — [AOSP external USB cameras](https://source.android.com/docs/core/camera/external-usb-cameras)
- Flutter's camera package requires applications to handle lifecycle and camera-access errors; its documented feature set includes image-buffer streaming but not arbitrary UVC protocol access. — [Flutter camera package](https://pub.dev/packages/camera)

### Inferences

- **Required first-device test (native diagnostic APK or temporary screen):** record Android release/API, ABI, `CameraManager.getCameraIdList()`, per-ID lens facing, hardware level, capabilities, supported YUV/JPEG sizes and FPS ranges, open/configure success, and exact exception/logcat output. Also test whether the vendor's existing app is using the same camera and whether opening it causes a conflict.
- **USB test only if integrated probing fails or external hardware is intentional:** inspect `UsbManager.deviceList`, USB host feature, attached interfaces/classes, permission flow, `/dev/video*` visibility (where permitted), and whether a UVC camera appears in Camera2. Record VID/PID, descriptors, negotiated formats, frame rate, power draw/disconnect behavior, and ARMv7 native-library availability.
- **Architecture recommendation:** define a `CameraSource` abstraction with (1) `AndroidCamera2Source`, (2) `AndroidCamera1Source` fallback, and (3) optional `UvcSource`; expose capability/error diagnostics to Flutter. Keep vision processing at the smallest useful resolution and rate, and avoid sending full-rate frames over Dart/platform channels until measured.
- **Decision gate:** choose Flutter camera only after the probe succeeds and frame latency/CPU are acceptable; choose native Camera2/API1 if the robot is quirky or vision is latency-sensitive; choose UVC only after confirming external hardware/provider/USB-host prerequisites. If all fail, request UBTECH's Visbot SDK or a vendor service/API rather than trying to infer private device nodes.

### Gaps

- Device access is needed to answer all Visbot-specific questions: integrated versus external camera, camera IDs, API1/API2 level, stream formats, concurrent ownership, permission/app-op policy, actual image orientation, thermal/CPU budget, and whether depth frames are available to third-party apps.
- Public related-robot documentation cannot establish Visbot's exact board, Android build fingerprint, kernel, camera HAL version, sensor calibration, or vendor restrictions.
- The absence of a public Visbot camera API in the sources searched is not evidence that no API exists; it may be distributed only under UBTECH partner/customer documentation.
