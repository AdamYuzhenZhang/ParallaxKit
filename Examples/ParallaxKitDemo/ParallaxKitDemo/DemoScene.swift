import ParallaxKit
import RealityKit
import UIKit
import simd

/// Demo geometry only. The tunnel's opening follows the same physical screen
/// bounds used by the projection, including when calibration changes live.
@MainActor
final class DemoScene {
    let root = AnchorEntity(world: .zero)
    private let tunnel = Entity()
    private let box = MeshResource.generateBox(size: 1)
    private var screen: ParallaxScreen?
    let depth: Float = 0.05
    private var walls: [(entity: ModelEntity, outward: SIMD3<Float>)] = []

    init() {
        let cubeWidth: Float = 0.028
        let cube = ModelEntity(
            mesh: .generateBox(size: cubeWidth, cornerRadius: 0.002),
            materials: [SimpleMaterial(color: .systemOrange, roughness: 0.35, isMetallic: false)]
        )
        // Put the front surface on the glass, with the cube extending behind it.
        cube.position = [0, 0, -cubeWidth / 2]
        root.addChild(cube)
        root.addChild(tunnel)

        let light = PointLight()
        light.light.intensity = 200
        light.light.attenuationRadius = 2
        light.position = [-0.1, 0.12, 0.15]
        root.addChild(light)
        let fill = PointLight()
        fill.light.intensity = 50
        fill.light.attenuationRadius = 1
        fill.position = [0, 0, 0.08]
        root.addChild(fill)
    }

    func update(screen: ParallaxScreen) {
        guard self.screen != screen else { return }
        self.screen = screen
        tunnel.children.removeAll()
        walls.removeAll()

        let width = screen.size.x
        let height = screen.size.y
        let center = screen.center
        let thickness: Float = 0.003
        let wall = SimpleMaterial(color: UIColor(white: 0.18, alpha: 1), roughness: 0.9, isMetallic: false)

        // Inner edges meet the phone boundary at Z = 0. All wall thickness is
        // outside the opening; the walls extend back to the grid at Z = -depth.
        for sign: Float in [-1, 1] {
            let x = center.x + sign * (width + thickness) / 2
            let entity = addBox(size: [thickness, height + 2 * thickness, depth],
                                position: [x, center.y, -depth / 2], material: wall)
            walls.append((entity, [sign, 0, 0]))
        }
        for sign: Float in [-1, 1] {
            let y = center.y + sign * (height + thickness) / 2
            let entity = addBox(size: [width, thickness, depth],
                                position: [center.x, y, -depth / 2], material: wall)
            walls.append((entity, [0, sign, 0]))
        }

        // Close the tunnel with a dark backing. Grid lines sit slightly in front
        // of it to avoid depth fighting and remain inside the four walls.
        let backing = addBox(size: [width, height, thickness],
                             position: [center.x, center.y, -depth - thickness / 2],
                             material: UnlitMaterial(color: UIColor(white: 0.025, alpha: 1)))
        walls.append((backing, [0, 0, -1]))
        let grid = UnlitMaterial(color: UIColor(white: 0.25, alpha: 1))
        let spacing: Float = 0.015
        let columns = Int(width / (2 * spacing))
        let rows = Int(height / (2 * spacing))
        for index in -columns...columns {
            addBox(size: [0.00035, height, 0.0001],
                   position: [center.x + Float(index) * spacing, center.y, -depth + 0.0002],
                   material: grid)
        }
        for index in -rows...rows {
            addBox(size: [width, 0.00035, 0.0001],
                   position: [center.x, center.y + Float(index) * spacing, -depth + 0.0002],
                   material: grid)
        }
    }

    /// Cut away only the observer-facing walls. The inspector draws their edges;
    /// nil restores every solid wall when returning to the real parallax view.
    func setInspectionViewpoint(_ position: SIMD3<Float>?) {
        for wall in walls {
            wall.entity.isEnabled = position.map {
                simd_dot($0 - wall.entity.position, wall.outward) <= 0
            } ?? true
        }
    }

    @discardableResult
    private func addBox(size: SIMD3<Float>, position: SIMD3<Float>, material: any Material) -> ModelEntity {
        let entity = ModelEntity(mesh: box, materials: [material])
        entity.scale = size
        entity.position = position
        tunnel.addChild(entity)
        return entity
    }
}
