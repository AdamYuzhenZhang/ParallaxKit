import ParallaxKit
import ParallaxARKit
import RealityKit
import SwiftUI

struct DemoView: View {
    @StateObject private var model = DemoModel()
    @State private var showsControls = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                DemoSurface(model: model).ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("ParallaxKit").font(.headline)
                            Text(model.status).font(.caption)
                        }
                        Spacer()
                        Button("Controls", systemImage: "slider.horizontal.3") { showsControls = true }
                            .labelStyle(.iconOnly)
                    }
                    DemoModePicker(mode: $model.mode)
                    Picker("Scene viewpoint", selection: $model.viewpoint) {
                        ForEach(DemoViewpoint.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("sceneViewpoint")
                }
                .padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding()
            }
            .overlay(alignment: .bottom) {
                if showsControls {
                    DemoControls(model: model, onClose: { showsControls = false })
                        // Overlay instead of resizing the render surface: physical
                        // screen calibration must stay valid while tuning settings.
                        .frame(height: geometry.size.height * 0.34)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 12)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if model.viewpoint == .thirdPerson {
                    inspectionLegend
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showsControls)
        }
        .preferredColorScheme(.dark)
        .task {
            await model.setReduceMotion(reduceMotion)
            await model.activate()
        }
        .onDisappear { model.deactivate() }
        .onChange(of: model.mode) { Task { await model.updateTrackingMode() } }
        .onChange(of: model.viewpoint) { model.updateViewpoint() }
        .onChange(of: reduceMotion) { _, value in Task { await model.setReduceMotion(value) } }
        .onChange(of: model.settings) { model.updateConfiguration() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.activate() } }
            else { model.deactivate() }
        }
    }

    private var inspectionLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Drag to orbit · Pinch to zoom").font(.subheadline)
                Spacer()
                Button("Reset view") { model.resetInspectionView() }
                    .accessibilityIdentifier("resetInspectionView")
            }
            HStack(spacing: 14) {
                Text("X").foregroundStyle(.red)
                Text("Y").foregroundStyle(.green)
                Text("Z").foregroundStyle(.blue)
                Text("Frustum").foregroundStyle(.cyan)
                Text("Eye").foregroundStyle(.yellow)
            }
            .font(.caption.bold())
            Text("Phone coordinates. Frustum shown to the rear grid, 5 cm inside the screen. White line: camera forward.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct DemoModePicker: View {
    @Binding var mode: ParallaxMode
    var body: some View {
        Picker("Viewer input", selection: $mode) {
            ForEach(ParallaxMode.allCases, id: \.self) { Text($0.demoTitle).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("viewerInput")
    }
}

private extension ParallaxMode {
    var demoTitle: String {
        switch self {
        case .still: "Still"
        case .face: "Face"
        case .motion: "IMU"
        }
    }
}

private struct DemoControls: View {
    @ObservedObject var model: DemoModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if model.mode != .face {
                    Section {
                        control("Viewing distance · m", value: $model.settings.viewingDistance, range: 0.25...0.8)
                    }
                }
                if model.mode == .motion {
                    Section("Motion") {
                        control("Strength", value: $model.settings.motionStrength, range: 0...1.5)
                        Toggle("Return to center", isOn: $model.settings.automaticallyRecenters)
                        if model.settings.automaticallyRecenters {
                            control("Return time · s", value: $model.settings.recenterTime, range: 0.2...4)
                        }
                        Button("Recenter now") { model.recenterMotion() }
                    }
                }
                if model.mode == .face {
                    Section {
                        Picker("Eye", selection: $model.eye) {
                            ForEach(ParallaxEye.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        Button("Restart face tracking") { Task { await model.updateTrackingMode() } }
                    }
                }
                Section {
                    DisclosureGroup("Screen calibration") {
                        control("Width · m", value: $model.screenWidth, range: 0.05...0.22, precision: 3)
                        control("Height · m", value: $model.screenHeight, range: 0.1...0.32, precision: 3)
                        if model.mode == .face {
                            control("Camera X · m", value: $model.cameraOffsetX, range: -0.1...0.1, precision: 3)
                            control("Camera Y · m", value: $model.cameraOffsetY, range: 0...0.16, precision: 3)
                        }
                        Text("Measure the screen and front-camera offset from its center. Defaults are estimates.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done", action: onClose) }
        }
    }

    private func control(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, precision: Int = 2) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(precision))).monospacedDigit() }
            Slider(value: value, in: range)
        }
    }
}

private struct DemoSurface: UIViewRepresentable {
    let model: DemoModel
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        model.install(in: view)
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {}
    func makeCoordinator() -> DemoModel { model }
    static func dismantleUIView(_ view: ARView, coordinator: DemoModel) { coordinator.dismantle() }
}
