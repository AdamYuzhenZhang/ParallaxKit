# Integrating ParallaxKit

Start with `ParallaxController` from the core product. It gives Still, Face, and
Motion the same rendering path while keeping platform services in your app.
The [demo model](../Examples/ParallaxKitDemo/ParallaxKitDemo/DemoModel.swift) is a
working host implementation, including permission handling and backgrounding.

## Coordinates and rendering

- Units are meters. The display is on Z = 0; +X points right, +Y up, and +Z toward
  the viewer. Content behind the display has negative Z.
- `ParallaxScreen` describes the physical rectangle covered by the rendering
  viewport, not its pixel dimensions. An inset viewport needs its own bounds.
  Use `init(left:right:bottom:top:)` for a rectangle offset from the scene origin.
- The camera stays parallel to the screen normal. Translation and the asymmetric
  projection work together; do not add a look-at rotation or apply phone rotation
  directly to the camera.
- Matrices use right-handed coordinates and Metal reverse depth: near = 1,
  far = 0. A custom renderer must match that depth convention and its viewport
  orientation. Other graphics APIs need an appropriate depth conversion.

```swift
import Foundation
import ParallaxKit

let screen = try ParallaxScreen(width: 0.070, height: 0.150)
var controller = try ParallaxController(mode: .still)

// Repeat on the render clock, on the same executor as input submission.
let state = controller.sample(at: ProcessInfo.processInfo.systemUptime)
let camera = try ParallaxProjection.camera(
    viewer: state.position, screen: screen, near: 0.01, far: 10
)
```

`ParallaxState` reports the selected mode, position, and `.fixed`, `.tracking`,
or `.fallback` status. Missing or invalid input never requires creating a second
rendering path. Geometry and configuration initializers throw on invalid values;
input submission returns `false` for rejected samples.

### RealityKit

Link `ParallaxRealityKit` and create a `PerspectiveCamera` under an identity
anchor in a non-AR `ARView`. Apply the result each frame:

```swift
import ParallaxRealityKit

ParallaxRealityCamera.apply(camera, to: cameraEntity)
```

The adapter replaces the perspective camera component with a custom projection
and sets the entity transform to translation only. The camera's parent must use
the same screen coordinates as the scene, with no extra rotation or scale.
Face tracking can use a separate host-owned `ARSession`; Still and Motion need
no AR session. See [DemoModel](../Examples/ParallaxKitDemo/ParallaxKitDemo/DemoModel.swift)
and [DemoScene](../Examples/ParallaxKitDemo/ParallaxKitDemo/DemoScene.swift).

## Still

The default fixed viewer is `[0, 0, 0.5]`. Change it programmatically if useful:

```swift
controller.setMode(.still)
try controller.setFixedPosition([0.02, 0, 0.5])
```

Changing this position affects only Still. Face's fallback and Motion's virtual
viewing distance are configured separately. No hardware is needed.

## Face

Link `ParallaxARKit`. Your app checks `ARFaceTrackingConfiguration.isSupported`,
provides `NSCameraUsageDescription`, requests camera permission, and owns the
session and its delegate. On each matched frame:

```swift
import ParallaxARKit

// Set once when entering Face, before starting the session.
controller.setMode(.face)
let faceProvider = ARFaceParallaxProvider(
    eye: .midpoint,
    cameraFacing: .front,
    cameraOriginInScreenSpace: [0, 0.065, 0] // Illustrative; measure your device.
)

// In the ARSession frame callback, serialized with rendering:
if let pose = faceProvider.pose(from: frame, orientation: .portrait) {
    controller.submitFacePose(pose)
}
```

Pass the current **interface** orientation, and recompute screen dimensions and
camera offset when it changes. The offset is the capture camera's physical
position relative to the display origin in screen axes. Front-camera horizontal
position follows viewer movement without an additional mirror. Eye selection
supports `.left`, `.right`, and `.midpoint`; a single image remains monoscopic.
The provider reads camera and eye transforms from the same frame.

For an existing rear-camera world-tracking session, `.back` supports
`userFaceTrackingEnabled` after the app checks `supportsUserFaceTracking`.
The demo validates the simpler front-camera path; combined-camera behavior needs
its own hardware validation.

## Motion (IMU)

Link `ParallaxMotion` if using the supplied Core Motion adapter. The optional
source is main-actor isolated. The controller itself has no actor requirement;
keep its mutation on the same executor as rendering and input delivery.

```swift
import ParallaxMotion

// Own the source for the lifetime of the host scene, on the main actor.
let source = CoreMotionParallaxSource()
controller.setMode(.motion)
try source.start() // Throws if unavailable; the controller remains centered.

// On each render update, before controller.sample(at:):
if let sample = source.latestSample {
    controller.submitMotion(sample, orientation: .portrait)
}

// When leaving Motion or backgrounding:
source.stop()
controller.reset()
```

Include a meaningful `NSMotionUsageDescription` in the host's Info.plist. No
camera permission or ARKit session is needed. If your app already owns a motion
manager, submit `ParallaxMotionSample(deviceMotion: deviceMotion)` instead of
starting a second manager. For custom or replayed inputs, use
`ParallaxMotionSample(referenceToDevice:timestamp:)`; its quaternion must rotate
reference coordinates into portrait device coordinates (+X right, +Y top, +Z out).
The Core Motion adapter performs this conversion for you.

The first sample establishes neutral at any holding angle. Later orientation
changes produce a bounded virtual eye; the camera's rotation stays fixed. Pure
roll around the neutral display normal produces no displacement. Automatic
recentering continuously adapts the neutral orientation so a held tilt gradually
returns to center. `controller.recenterMotion()` centers immediately and uses the
next fresh sample as neutral. A changed interface orientation or a long sample
gap also establishes a new reference.

IMU cannot measure eye distance or follow a viewer moving around a stationary
phone. The configured viewing distance is virtual and stays constant.

## Configuration

The demo exposes only the most useful controls. Apps can tune the full public
configuration without importing any demo source:

```swift
let center = SIMD3<Float>(0, 0, 0.5)
var controller = try ParallaxController(
    mode: .motion,
    fixedPosition: center,
    tracking: .init(
        fallbackPosition: center,
        smoothingTime: 0.07,
        lossTimeout: 0.4,
        returnTime: 0.25
    ),
    motion: .init(
        viewerDistance: 0.5,
        sensitivity: [0.6, 0.6],
        maximumTilt: [0.21, 0.17],
        maximumOffset: [0.12, 0.10],
        recenterTime: 1.2,
        smoothingTime: 0.08,
        maximumSampleGap: 0.5
    )
)
```

These are the defaults. All timing values are in seconds; tilt is in radians
and offset in meters. Sensitivity is horizontal/vertical gain: negative reverses
an axis and zero disables it. `recenterTime: nil` holds the neutral until a reset;
a time of 1.2 gives approximately 95% return after 3.6 seconds for a small held
tilt, plus output smoothing. Smoothing uses time constants rather than frame counts.

`tracking` controls Face smoothing and both modes' loss timeout and return speed.
Motion applies its own smoothing once and falls back to `motion.neutralPosition`.
To change configuration, construct and assign a new controller using its current
mode. This clears history and recenters Motion. Validate editable values before
replacing the previous controller, as [DemoSettings](../Examples/ParallaxKitDemo/ParallaxKitDemo/DemoSettings.swift)
and `DemoModel.updateConfiguration()` do. Screen calibration lives outside the
controller; update the screen passed to the projection and the face provider's
offset, resetting tracking if the coordinate reference changes.

## Lifecycle and timing

| Event | Controller action | Host action |
| --- | --- | --- |
| Change mode | `setMode(_:)` clears input history when the mode changes | Stop old input, start new input |
| Known interruption | `invalidate()` returns smoothly to fallback | Report the interruption; resume input when available |
| Restart stream, clock, or coordinate reference | `reset()` clears timestamps and filter history | Reject callbacks queued by the previous stream |
| Explicit motion recenter | `recenterMotion()` | Keep the motion source running |
| Background / disappear | `reset()`; optionally select `.still` | Stop motion updates and pause the AR session |
| Reduce Motion | Select `.still` or your app's reduced-motion behavior | Stop unused input services |

Repeated `setMode` calls with the same mode preserve history. Inputs for inactive
modes are ignored. `invalidate()` and `recenterMotion()` retain the last accepted
input timestamp, preventing a cached sample from seeding a new reference;
`reset()` deliberately permits a restarted clock. The supplied motion source
also withholds samples from before its most recent start.

Use a single monotonic time base for inputs and `sample(at:)`. ARFrame timestamps,
Core Motion timestamps, `CACurrentMediaTime()`, and system uptime use the
boot-relative clock; do not use wall-clock `Date`. Replays need a shared replay
clock for inputs and sampling. Nonfinite, duplicate, and out-of-order inputs are
rejected. Sample every render frame even when no new input arrives so stale data
expires and the fallback transition continues.

The host must also guard asynchronous permission completion and delayed callbacks
with an activation generation or start timestamp. Inactive-mode rejection alone
cannot identify a callback from an older session after returning to that mode.
The demo demonstrates both permission-generation and frame-start checks.

## Smaller building blocks

Use `ParallaxProjection` directly for an existing viewer-position system.
`ParallaxTracker` can filter custom poses independently, and
`ParallaxMotionResponse` converts orientations into poses without a controller.
When combining the latter two yourself, set the tracker's smoothing time to zero
because the motion response already smooths output. These types have no hardware,
UI, or renderer dependencies and can be exercised with recorded input.
