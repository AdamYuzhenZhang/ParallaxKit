# ParallaxKit demo

A small iOS app that consumes the package's public API. It compares Still, Face,
and IMU using an identical projection and scene. It runs on iOS 18+ in portrait.
Face data is processed in memory; the demo does not store or transmit camera
frames or face observations.

## Open and run

Open `ParallaxKitDemo.xcodeproj` and select the shared **ParallaxKitDemo** scheme.
The package resolves from `../..`, so this demo works in a standalone clone.
No generation step or external dependency installation is needed.

Still works in Simulator. For device signing, copy
`Configuration/Signing.local.xcconfig.example` to
`Configuration/Signing.local.xcconfig`, then enter your team ID and unique bundle
identifier. This local file is ignored by Git and overrides the shared defaults
in `Demo.xcconfig`. Face requires ARKit face-tracking support; IMU requires device
motion. Each mode reports unavailable input and leaves a centered scene.

## Scene and controls

The orange cube is 0.028 m wide, centered at Z = -0.014: its front surface is at
Z = 0 and its body extends into the screen. Four walls open at the physical screen
boundary and extend 0.05 m inward to a rear grid. The cube never rotates or follows
the viewer. Walls and grid resize with screen calibration.

Choose **Still**, **Face**, or **IMU** at the top. The settings button opens a
scrollable lower-third panel without resizing the rendering viewport.

| Mode | Main settings |
| --- | --- |
| Still | Viewing distance |
| Face | Left, right, or midpoint eye; restart tracking |
| IMU | Viewing distance, strength, return to center, return time, recenter now |

**Screen calibration** is collapsed by default. Enter measured screen width and
height in meters; Face also exposes the front-camera X/Y offset from screen
center. Defaults are estimates, not a hardware profile. Advanced per-axis gain,
smoothing, travel limits, and timeouts remain available in the package API.
Changing motion settings establishes a new center.

## Third-person inspection

Choose **Third person** below the input selector to look at the same scene from
the side. This is a viewing option, independent of Still / Face / IMU. Switching
views keeps the controller, sensor session, and motion neutral running unchanged.
Drag the scene to orbit, pinch to zoom, and use **Reset view** to frame it again.

- The white rectangle is the calibrated screen at Z = 0. Gray edges outline the
  5 cm tunnel. Walls facing the observer are cut away so the original cube and
  rear grid remain visible; all solid walls return in Parallax view.
- **Phone camera** marks the calibrated capture-camera origin. Its RGB axes use
  the package's screen coordinates: X right, Y up, Z out of the display. The phone
  stays fixed in this coordinate frame; this is not an AR world-position display.
- **Fixed / Tracked / Virtual eye** marks the actual viewpoint used for rendering
  in Still / Face / IMU. Face displays the filtered selected eye, not raw head
  pose or gaze orientation. Missing input is labeled **Fallback eye**.
- The eye's RGB axes come from the rendering camera's inverse view matrix.
  Its white forward line stays perpendicular to the screen while the asymmetric
  cyan frustum moves with the eye.
- Frustum lines are unprojected from the actual projection matrix. They include
  the near-plane outline and extend through the display corners to the rear-grid
  plane. This is a useful section of the frustum, not the full 10 m far clip.

The separate world camera and frustum display follow the diagnostic approach in
TheParallaxView's [CameraManager](https://github.com/algomystic/TheParallaxView/blob/master/Assets/Scripts/CameraManager.cs)
and [OffAxisProjection](https://github.com/algomystic/TheParallaxView/blob/master/Assets/Scripts/OffAxisProjection.cs).
The implementation is native RealityKit and uses the same public ParallaxKit
output as the normal view. No extra tracking or projection path is introduced.

For repeated development launches, add `--inspect` to the scheme's Run arguments
to start directly in Third person (Debug builds only).

## Validation checklist

1. In Still, confirm that head or phone movement does not change the rendering.
   Adjust distance and check that the cube's front surface and tunnel opening
   remain registered to the screen plane.
2. Open settings and scroll. The panel must remain in the lower third and the
   scene must retain its full-screen size. Change screen calibration and confirm
   that the walls and rear grid follow the new bounds.
3. On hardware, measure the illuminated display rectangle, excluding the bezel,
   and the front-camera offset from its center. Enter those values before judging
   physical registration.
4. In Face, grant camera permission, then move your head right/left, up/down, and
   closer/farther. The virtual viewpoint should follow your head: moving right
   reveals more of the cube's right side. The front surface and tunnel opening
   stay fixed. Check all three eye choices; for one-eye validation, keep the
   selected eye open. Camera X calibration is a physical offset, not an axis flip.
5. Cover the camera or move out of view. The viewpoint should return smoothly to
   center after a short timeout. Reacquisition must preserve movement direction.
   Deny permission or interrupt tracking and verify that other modes still work.
6. Enter IMU at a comfortable holding angle. It starts centered. Turn and tip the
   display slowly; depth layers should move relative to each other while the
   tunnel opening stays fixed. A display turning toward your right places the
   virtual eye to the left in screen coordinates.
7. Hold the new angle. The default return time is 1.2 seconds (approximately
   3.6 seconds for 95% return, plus smoothing). Tilt again from the new grip and
   confirm that the effect responds again. Repeat upright, reclining, and nearly
   flat. Pure twisting around the display normal from neutral should not shift
   the viewpoint.
8. Adjust strength and return time. Disable **Return to center** and confirm a
   held tilt remains displaced. **Recenter now** establishes a new neutral.
9. Switch Still → Face → IMU → Still repeatedly, including while camera
   permission is pending. Only Face uses the camera; IMU works with camera
   permission denied. Background and resume at a new phone orientation: IMU
   should establish a fresh center without replaying the old tilt.
10. Enable the system's Reduce Motion setting. The demo should stop tracking
    inputs and keep a fixed viewpoint. Repeat validation on the oldest supported
    OS and record device, OS, calibration, and any corrections.
11. Enter Third person in each input mode. The eye and frustum must continue
    following the active source, including automatic IMU return and face-loss
    fallback. Changing the viewing option must not restart tracking or recenter.
12. Orbit around the phone and pinch to zoom. The nearest walls should cut away;
    RGB eye axes must remain parallel to the phone axes even when the frustum
    becomes asymmetric. Check that the rays pass through all four screen corners.
13. Return to Parallax and verify that the solid tunnel is restored, no diagnostic
    axes or lines remain, and the projection still fills the calibrated viewport.
    Reset view, screen calibration, and viewing-distance changes should also
    work while inspecting; use Reset view to reframe a changed scene size.

Simulator and automated tests validate UI/build behavior and mathematics;
sensor direction, optical calibration, and latency need physical hardware.

## Reusing the implementation

- [DemoModel.swift](ParallaxKitDemo/DemoModel.swift) owns services, permissions,
  lifecycle, and the render loop. All modes feed `ParallaxController`.
- [DemoSettings.swift](ParallaxKitDemo/DemoSettings.swift) maps the small settings
  surface to public package configuration.
- [DemoScene.swift](ParallaxKitDemo/DemoScene.swift) owns only the validation scene.
- [DemoInspector.swift](ParallaxKitDemo/DemoInspector.swift) owns the observer
  camera, orbit/zoom, axes, labels, and frustum. It consumes `ParallaxCamera` and
  `ParallaxState`; it never owns sensors or changes tracking configuration.
- [Integration guide](../../Documentation/Integration.md) explains package usage
  without copying demo UI or scene code.

The scene contains no Rocky's Scanner content or copied Unity artwork. Portrait
is intentional for this validation app. The package accepts interface orientation;
apps supporting landscape must supply matching physical calibration and test it.
