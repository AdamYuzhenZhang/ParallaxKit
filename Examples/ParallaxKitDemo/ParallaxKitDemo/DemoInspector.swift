import ParallaxKit
import RealityKit
import UIKit
import simd

/// A second rendering camera and diagnostic geometry, owned entirely by the demo.
/// Consumes the same computed camera as the parallax view; never reads sensors,
/// changes a tracking reference, or substitutes a second projection calculation.
@MainActor
final class DemoInspector {
    let root = Entity()
    let camera = PerspectiveCamera()
    private let box = MeshResource.generateBox(size: 1)
    private var rays: [InspectionLine] = []
    private var nearEdges: [InspectionLine] = []
    private var rearEdges: [InspectionLine] = []
    private var tunnelEdges: [InspectionLine] = []
    private let phoneAxes: Entity
    private let eyeAxes: Entity
    private let forward: InspectionLine
    private let phoneLabel: ModelEntity
    private let screenLabel: ModelEntity
    private let eyeLabel: ModelEntity
    private var eyeTitle = ""

    private var yaw: Float = 55 * .pi / 180
    private var elevation: Float = 35 * .pi / 180
    private var zoom: Float = 0.85
    private var target = SIMD3<Float>(0, 0, 0.22)
    private var radius: Float = 0.4
    private var needsFraming = true

    init() {
        phoneAxes = Self.axes(length: 0.025, marker: .systemCyan)
        eyeAxes = Self.axes(length: 0.035, marker: .systemYellow)
        forward = InspectionLine(mesh: box, color: .white, width: 0.0007)
        phoneLabel = Self.label("Phone camera")
        screenLabel = Self.label("Screen · z = 0")
        eyeLabel = Self.label("Eye")
        for entity in [phoneAxes, eyeAxes, forward.entity, phoneLabel, screenLabel, eyeLabel] {
            root.addChild(entity)
        }
        for _ in 0..<4 {
            rays.append(line(color: .systemCyan, width: 0.0008))
            nearEdges.append(line(color: .systemCyan, width: 0.0006))
            rearEdges.append(line(color: .systemCyan, width: 0.0008))
        }
        for index in 0..<12 {
            tunnelEdges.append(line(color: index < 4 ? .white : .gray, width: 0.0008))
        }
        camera.camera = PerspectiveCameraComponent(
            near: 0.001, far: 20, fieldOfViewInDegrees: 45, fieldOfViewOrientation: .vertical
        )
    }

    func resetView() {
        yaw = 55 * .pi / 180
        elevation = 35 * .pi / 180
        zoom = 0.85
        needsFraming = true
    }

    func orbit(by translation: CGPoint) {
        yaw -= Float(translation.x) * 0.006
        elevation = min(max(elevation + Float(translation.y) * 0.006, -.pi / 2.5), .pi / 2.5)
    }

    func magnify(by scale: Float) {
        guard scale.isFinite, scale > 0 else { return }
        zoom = min(max(zoom / scale, 0.45), 3)
    }

    func update(
        projection: ParallaxCamera, state: ParallaxState,
        screen: ParallaxScreen, depth: Float,
        captureOrigin: SIMD3<Float>, viewport: CGSize
    ) {
        let eye = projection.position
        // Frame once, rather than chasing the tracked eye every frame. Its
        // movement remains visible against a stationary observer and phone.
        if needsFraming {
            target = [screen.center.x, screen.center.y, (eye.z - depth) / 2]
            radius = max(0.22, simd_length(SIMD3(
                max(screen.size.x / 2, abs(eye.x)) + 0.08,
                max(screen.size.y / 2, abs(eye.y)) + 0.06,
                (eye.z + depth) / 2 + 0.04
            )))
            needsFraming = false
        }
        let aspect = Float(max(viewport.width, 1) / max(viewport.height, 1))
        let verticalHalfFOV: Float = 22.5 * .pi / 180
        let horizontalHalfFOV = atan(tan(verticalHalfFOV) * aspect)
        // Leave room above/below the scene for the mode picker and legend.
        let limitingAngle = min(horizontalHalfFOV * 0.88, verticalHalfFOV * 0.65)
        let distance = radius / sin(limitingAngle) * zoom
        let offset = SIMD3<Float>(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation))
        camera.look(at: target, from: target + offset * distance, relativeTo: nil)

        phoneAxes.position = captureOrigin
        // These axes are the actual rendering camera transform (not head gaze).
        eyeAxes.transform.matrix = simd_inverse(projection.viewMatrix)
        forward.update(from: eye, to: eye + [0, 0, -min(0.1, eye.z)])

        let corners: [SIMD3<Float>] = [
            [screen.left, screen.bottom, 0], [screen.right, screen.bottom, 0],
            [screen.right, screen.top, 0], [screen.left, screen.top, 0],
        ]
        for index in 0..<4 {
            let next = (index + 1) % 4
            tunnelEdges[index].update(from: corners[index], to: corners[next])
            tunnelEdges[index + 4].update(from: corners[index] - [0, 0, depth], to: corners[next] - [0, 0, depth])
            tunnelEdges[index + 8].update(from: corners[index], to: corners[index] - [0, 0, depth])
        }

        // Unproject the ACTUAL reverse-Z near-plane corners. Extend those rays
        // only to the scene's rear plane, not the projection's 10 m far clip.
        // This keeps the useful frustum section visible at the phone's scale.
        let inverse = simd_inverse(projection.projectionMatrix * projection.viewMatrix)
        let clipCorners: [SIMD2<Float>] = [[-1, -1], [1, -1], [1, 1], [-1, 1]]
        let near = clipCorners.map { corner -> SIMD3<Float> in
            let p = inverse * SIMD4<Float>(corner.x, corner.y, 1, 1)
            return SIMD3(p.x, p.y, p.z) / p.w
        }
        let rear = near.map { point -> SIMD3<Float> in
            let ray = point - eye
            return eye + ray * ((-depth - eye.z) / ray.z)
        }
        for index in 0..<4 {
            let next = (index + 1) % 4
            rays[index].update(from: eye, to: rear[index])
            nearEdges[index].update(from: near[index], to: near[next])
            rearEdges[index].update(from: rear[index], to: rear[next])
        }

        let title: String
        switch (state.mode, state.status) {
        case (.still, _): title = "Fixed eye"
        case (_, .fallback): title = "Fallback eye"
        case (.face, _): title = "Tracked eye"
        case (.motion, _): title = "Virtual eye"
        }
        if title != eyeTitle {
            eyeTitle = title
            eyeLabel.model?.mesh = Self.textMesh(title)
        }
        billboard(eyeLabel, at: eye, offset: [0.012, 0.045, 0.04])
        billboard(phoneLabel, at: captureOrigin, offset: [0.015, 0.03, 0.04])
        billboard(screenLabel, at: [screen.left, screen.bottom, 0], offset: [0, -0.04, 0.07])
    }

    private func billboard(_ label: Entity, at point: SIMD3<Float>, offset: SIMD3<Float>) {
        label.orientation = camera.orientation
        label.position = point + camera.orientation.act(offset)
    }

    private func line(color: UIColor, width: Float) -> InspectionLine {
        let line = InspectionLine(mesh: box, color: color, width: width)
        root.addChild(line.entity)
        return line
    }

    private static func axes(length: Float, marker: UIColor) -> Entity {
        let root = Entity()
        root.addChild(ModelEntity(mesh: .generateSphere(radius: 0.003), materials: [UnlitMaterial(color: marker)]))
        let mesh = MeshResource.generateBox(size: 1)
        for (direction, color) in [
            (SIMD3<Float>(1, 0, 0), UIColor.systemRed),
            (SIMD3<Float>(0, 1, 0), UIColor.systemGreen),
            (SIMD3<Float>(0, 0, 1), UIColor.systemBlue),
        ] {
            let line = InspectionLine(mesh: mesh, color: color, width: 0.0012)
            line.update(from: .zero, to: direction * length)
            root.addChild(line.entity)
            let tip = ModelEntity(mesh: .generateSphere(radius: 0.0018), materials: [UnlitMaterial(color: color)])
            tip.position = direction * length
            root.addChild(tip)
        }
        return root
    }

    private static func textMesh(_ text: String) -> MeshResource {
        .generateText(text, extrusionDepth: 0, font: .systemFont(ofSize: 1, weight: .medium))
    }

    private static func label(_ text: String) -> ModelEntity {
        let entity = ModelEntity(mesh: textMesh(text), materials: [UnlitMaterial(color: .white)])
        entity.scale = .init(repeating: 0.016)
        return entity
    }
}

/// Reuses a unit mesh; render updates change transforms only.
@MainActor
private final class InspectionLine {
    let entity: ModelEntity
    private let width: Float

    init(mesh: MeshResource, color: UIColor, width: Float) {
        self.width = width
        entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
    }

    func update(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        let delta = end - start
        let length = simd_length(delta)
        entity.isEnabled = length > 0.000001
        guard entity.isEnabled else { return }
        entity.position = (start + end) / 2
        entity.scale = [width, length, width]
        entity.orientation = simd_quatf(from: [0, 1, 0], to: delta / length)
    }
}
