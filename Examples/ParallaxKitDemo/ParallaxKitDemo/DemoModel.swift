import ARKit
import AVFoundation
import Combine
import ParallaxKit
import ParallaxARKit
import ParallaxMotion
import ParallaxRealityKit
import RealityKit
import UIKit

enum DemoViewpoint: String, CaseIterable {
    case parallax = "Parallax"
    case thirdPerson = "Third person"
}

@MainActor
final class DemoModel: NSObject, ObservableObject, @preconcurrency ARSessionDelegate {
    @Published var mode: ParallaxMode = .still
    @Published var viewpoint: DemoViewpoint = .parallax
    @Published var screenWidth: Float = 0.07
    @Published var screenHeight: Float = 0.15
    @Published var cameraOffsetX: Float = 0
    @Published var cameraOffsetY: Float = 0.065
    @Published var eye: ParallaxEye = .midpoint
    @Published var settings = DemoSettings()
    @Published private(set) var status = "Fixed viewer"

    private let session = ARSession()
    private let motionSource = CoreMotionParallaxSource()
    private let camera = PerspectiveCamera()
    private var demoScene: DemoScene?
    private var inspector: DemoInspector?
    private var orbitGesture: UIPanGestureRecognizer?
    private var zoomGesture: UIPinchGestureRecognizer?
    // Only fixed built-in defaults are asserted here; edits use the throwing
    // configuration path below and leave the last valid controller intact.
    private var controller = try! ParallaxController()
    private var faceStartedAt: TimeInterval?
    private var updateSubscription: (any Cancellable)?
    private var isActive = false
    private var reducesMotion = false
    private var generation: UInt64 = 0
    private weak var view: ARView?

    override init() {
        super.init()
        #if DEBUG
        // Convenient when repeatedly launching the diagnostic view from Xcode.
        if ProcessInfo.processInfo.arguments.contains("--inspect") { viewpoint = .thirdPerson }
        #endif
    }

    func install(in view: ARView) {
        self.view = view
        view.environment.background = .color(.init(white: 0.025, alpha: 1))
        let scene = DemoScene()
        demoScene = scene
        let inspector = DemoInspector()
        self.inspector = inspector
        scene.root.addChild(inspector.root)
        view.scene.addAnchor(scene.root)
        let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbit.maximumNumberOfTouches = 1
        view.addGestureRecognizer(orbit)
        orbitGesture = orbit
        let zoom = UIPinchGestureRecognizer(target: self, action: #selector(handleZoom(_:)))
        view.addGestureRecognizer(zoom)
        zoomGesture = zoom
        updateSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            self?.render()
        }
        updateViewpoint()
    }

    /// Viewpoint changes never restart sensors or reset the parallax controller.
    func updateViewpoint() {
        guard let demoScene, let inspector else { return }
        camera.removeFromParent()
        inspector.camera.removeFromParent()
        let inspecting = viewpoint == .thirdPerson
        // Only one camera is attached, avoiding RealityKit camera-selection order.
        demoScene.root.addChild(inspecting ? inspector.camera : camera)
        inspector.root.isEnabled = inspecting
        orbitGesture?.isEnabled = inspecting
        zoomGesture?.isEnabled = inspecting
        render()
    }

    func resetInspectionView() {
        inspector?.resetView()
        render()
    }

    @objc private func handleOrbit(_ gesture: UIPanGestureRecognizer) {
        guard viewpoint == .thirdPerson else { return }
        inspector?.orbit(by: gesture.translation(in: view))
        gesture.setTranslation(.zero, in: view)
    }

    @objc private func handleZoom(_ gesture: UIPinchGestureRecognizer) {
        guard viewpoint == .thirdPerson else { return }
        inspector?.magnify(by: Float(gesture.scale))
        gesture.scale = 1
    }

    func activate() async {
        guard !isActive else { return }
        isActive = true
        await updateTrackingMode()
    }

    func deactivate() {
        isActive = false
        stopInputs()
        controller.setMode(.still)
    }

    func dismantle() {
        deactivate()
        updateSubscription?.cancel()
        updateSubscription = nil
        if let orbitGesture { view?.removeGestureRecognizer(orbitGesture) }
        if let zoomGesture { view?.removeGestureRecognizer(zoomGesture) }
        orbitGesture = nil
        zoomGesture = nil
        inspector = nil
        demoScene = nil
        view = nil
    }

    private func stopInputs() {
        generation &+= 1
        session.pause()
        session.delegate = nil
        motionSource.stop()
        faceStartedAt = nil
        controller.reset()
    }

    func setReduceMotion(_ enabled: Bool) async {
        guard reducesMotion != enabled else { return }
        reducesMotion = enabled
        await updateTrackingMode()
    }

    func updateTrackingMode() async {
        stopInputs()
        let requestGeneration = generation
        controller.setMode(isActive && !reducesMotion ? mode : .still)
        guard isActive else { return }
        guard !reducesMotion else { status = "Reduce Motion is on — fixed viewer"; return }
        switch mode {
        case .still:
            status = "Fixed viewer"
        case .motion:
            do {
                try motionSource.start()
                status = "Waiting for motion"
            } catch {
                status = "IMU unavailable — use Still"
            }
        case .face:
            guard ARFaceTrackingConfiguration.isSupported else {
                status = "Face tracking unavailable — use Still or IMU"
                return
            }
            let permission = AVCaptureDevice.authorizationStatus(for: .video)
            let granted: Bool
            if permission == .notDetermined {
                granted = await AVCaptureDevice.requestAccess(for: .video)
            } else { granted = permission == .authorized }
            // Switching away while a permission prompt is open must never
            // restart the old source or replace the new mode's status.
            guard requestGeneration == generation, isActive, mode == .face,
                  !reducesMotion, !Task.isCancelled else { return }
            guard granted else { status = "Camera access denied — use Still, IMU, or Settings"; return }
            session.delegate = self
            session.delegateQueue = .main
            let configuration = ARFaceTrackingConfiguration()
            configuration.isLightEstimationEnabled = false
            faceStartedAt = CACurrentMediaTime()
            session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            status = "Waiting for a face"
        }
    }

    func updateConfiguration() {
        do {
            controller = try settings.makeController(mode: isActive && !reducesMotion ? mode : .still)
        } catch {
            status = "Invalid settings"
        }
    }

    func recenterMotion() {
        controller.recenterMotion()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isActive, mode == .face, !reducesMotion,
              let faceStartedAt, frame.timestamp >= faceStartedAt else { return }
        let provider = ARFaceParallaxProvider(
            eye: eye, cameraFacing: .front,
            cameraOriginInScreenSpace: [cameraOffsetX, cameraOffsetY, 0]
        )
        if let pose = provider.pose(from: frame, orientation: .portrait) {
            controller.submitFacePose(pose)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard isActive, mode == .face else { return }
        controller.invalidate()
        status = "Tracking failed — retry Face or use another mode"
    }

    func sessionWasInterrupted(_ session: ARSession) {
        guard isActive, mode == .face else { return }
        controller.invalidate()
        status = "Tracking interrupted"
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        guard isActive, mode == .face else { return }
        Task { await updateTrackingMode() }
    }

    private func render() {
        let now = CACurrentMediaTime()
        if controller.mode == .motion, let sample = motionSource.latestSample {
            controller.submitMotion(sample, orientation: .portrait)
        }
        let state = controller.sample(at: now)
        if isActive, !reducesMotion {
            switch state.mode {
            case .still: break
            case .face:
                if state.status == .tracking {
                    setStatus("Tracking face")
                } else if status == "Tracking face" {
                    setStatus("Face lost — returning to center")
                }
            case .motion:
                if motionSource.isActive {
                    setStatus(state.status == .tracking
                        ? "Motion tracking" : "Motion unavailable — returning to center")
                }
            }
        }
        guard let screen = try? ParallaxScreen(width: screenWidth, height: screenHeight),
              let projection = try? ParallaxProjection.camera(viewer: state.position, screen: screen) else { return }
        demoScene?.update(screen: screen)
        // Every input uses this identical projection path. The cube, lights,
        // and camera rotation stay fixed; only the virtual eye changes.
        ParallaxRealityCamera.apply(projection, to: camera)
        if viewpoint == .thirdPerson, let inspector, let demoScene, let view {
            inspector.update(
                projection: projection, state: state, screen: screen, depth: demoScene.depth,
                captureOrigin: [cameraOffsetX, cameraOffsetY, 0], viewport: view.bounds.size
            )
            demoScene.setInspectionViewpoint(inspector.camera.position)
        } else {
            demoScene?.setInspectionViewpoint(nil)
        }
    }

    private func setStatus(_ message: String) {
        if status != message { status = message }
    }
}
