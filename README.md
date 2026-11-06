# ParallaxKit

A Swift package for making a screen feel like a window into a small 3D scene.
Choose a fixed viewpoint, face tracking, or device motion; all three use the same
off-axis perspective so objects on the screen plane remain registered to it.

Inspired by Peder Norrby / ALGOMYSTIC's Unity project
[TheParallaxView](https://github.com/algomystic/TheParallaxView).
This native implementation includes no Unity runtime or artwork.

## Requirements and products

Swift 6 · iOS 18+ · macOS 15+ · No external dependencies.

| Product | Use | Platforms |
| --- | --- | --- |
| `ParallaxKit` | Mode controller, projection, filtering, orientation-to-viewer response | iOS, macOS |
| `ParallaxARKit` | Eye position from a host-owned ARKit session | iOS |
| `ParallaxMotion` | Optional Core Motion source, or conversion of host-owned motion data | iOS |
| `ParallaxRealityKit` | Apply the custom camera to a RealityKit entity | iOS, macOS |

## Adding the package

In Xcode, choose **File → Add Package Dependencies** and enter:

```text
https://github.com/AdamYuzhenZhang/ParallaxKit
```

Select the `main` branch while the API is in early development, then link only
the products your app needs. Tagged semantic-version releases will follow as the
API stabilizes. For a Swift package dependency:

```swift
.package(url: "https://github.com/AdamYuzhenZhang/ParallaxKit.git", branch: "main")
```

For local development, use **Add Local** and select the package folder. The
package and demo have no dependency on AmbientLab, ARHandKit, or TextureMonitor.

## Start with one controller

```swift
import Foundation
import ParallaxKit

// Dimensions are illustrative; measure your actual rendering viewport.
let screen = try ParallaxScreen(width: 0.070, height: 0.150)
var controller = try ParallaxController(mode: .still)

// On each render update, using the same monotonic clock as sensor samples:
let state = controller.sample(at: ProcessInfo.processInfo.systemUptime)
let camera = try ParallaxProjection.camera(viewer: state.position, screen: screen)
// Use camera.viewMatrix and camera.projectionMatrix in your renderer.
```

With RealityKit, import `ParallaxRealityKit` and call
`ParallaxRealityCamera.apply(camera, to: cameraEntity)`.
The rendering camera keeps an identity rotation; it is never aimed at the object.

| Mode | Input | Behavior |
| --- | --- | --- |
| `.still` | `setFixedPosition(_:)` (optional) | Fixed viewer; no sensors needed |
| `.face` | `submitFacePose(_:)` | Smoothed eye position; returns to a fallback when input expires |
| `.motion` | `submitMotion(_:orientation:)` | Bounded virtual eye driven by orientation; optional gradual recentering |

Switch with `controller.setMode(...)`. The app starts/stops its input services;
the controller owns no camera, motion manager, UI, timer, or renderer. Its
lower-level projection and filtering types can also be used independently.

See the [integration guide](Documentation/Integration.md) for complete input
wiring, configuration, coordinates, lifecycle, and custom renderers.

## iOS demo

Open [ParallaxKitDemo.xcodeproj](Examples/ParallaxKitDemo/ParallaxKitDemo.xcodeproj)
and select the shared **ParallaxKitDemo** scheme. Still works in Simulator;
Face and IMU require supported hardware. The demo imports only public package
APIs and resolves the package using the relative path `../..`.

The scene contains a 2.8 cm cube with its front surface at Z = 0, four boundary
walls extending 5 cm inward, and a rear grid. A lower-third settings panel keeps
the scene visible while tuning distance, motion strength and recentering, or eye
selection. Calibration is collapsed by default. The rendering viewport remains
full-screen when the panel opens.

Select **Third person** to inspect the same scene from the side, with phone and
eye axes, a cutaway tunnel, and the actual projection frustum. Drag to orbit and
pinch to zoom. This independent observer camera works with all three input modes
without restarting tracking. The inspector is demo-only; the package's reusable
products have no dependency on diagnostic geometry or UI.

Device signing uses an ignored local configuration. Setup, controls, and physical
validation steps are in the [demo guide](Examples/ParallaxKitDemo/README.md).

## Validation and sharing

```sh
swift test -Xswiftc -warnings-as-errors
xcodebuild -project Examples/ParallaxKitDemo/ParallaxKitDemo.xcodeproj \
  -scheme ParallaxKitDemo -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Tests cover projection registration and depth, input validation, mode changes,
interruption recovery, timeout behavior, motion axes, recentering, and cadence.
[CI](.github/workflows/ci.yml) runs the core tests and builds the iOS demo for
device and Simulator. See [publishing notes](Documentation/Publishing.md) for the
standalone repository layout and release checks.

This is a developing package. The effect is monoscopic, and IMU mode models a
virtual eye rather than measuring head position. Physical calibration and sensor
feel require device testing; the demo's dimensions are estimates. The
[demo checklist](Examples/ParallaxKitDemo/README.md) covers those checks.

## Attribution and license

The projection technique is based on
[TheParallaxView](https://github.com/algomystic/TheParallaxView), by Peder Norrby /
ALGOMYSTIC AB. Its original code is MIT-licensed; its separately licensed artwork
is not included. ParallaxKit adapts the technique to native Swift and Metal
reverse depth, with separate input and renderer adapters.

ParallaxKit is [MIT-licensed](LICENSE). Keep
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), including the original code's
MIT notice, when redistributing it.
