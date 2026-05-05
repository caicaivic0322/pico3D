import AppKit
import Foundation
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct TrellisMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)

        WindowGroup("3D 模型预览", id: "modelPreview") {
            ModelPreviewWindow()
                .environmentObject(model)
        }
        .defaultSize(width: 820, height: 620)
    }
}

struct ModelSceneView: NSViewRepresentable {
    let modelURL: URL

    final class Coordinator {
        var loadedURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = false
        view.scene = Self.scene(for: modelURL)
        context.coordinator.loadedURL = modelURL
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        guard context.coordinator.loadedURL != modelURL else { return }
        view.scene = Self.scene(for: modelURL)
        context.coordinator.loadedURL = modelURL
    }

    private static func scene(for url: URL) -> SCNScene {
        let sourceScene = loadScene(url: url) ?? placeholderScene()
        let scene = SCNScene()
        let content = SCNNode()
        let isGeometryPreview = url.pathExtension.lowercased() == "obj"

        for child in sourceScene.rootNode.childNodes {
            child.removeFromParentNode()
            content.addChildNode(child)
        }

        if content.childNodes.isEmpty {
            content.addChildNode(SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.03)))
        }

        prepareForPreview(content, useMatteMaterial: isGeometryPreview)
        normalize(content)
        scene.rootNode.addChildNode(content)
        addCameraAndLights(to: scene)
        return scene
    }

    private static func loadScene(url: URL) -> SCNScene? {
        let options: [SCNSceneSource.LoadingOption: Any] = [
            .createNormalsIfAbsent: true,
            .checkConsistency: true
        ]
        return try? SCNScene(url: url, options: options)
    }

    private static func prepareForPreview(_ node: SCNNode, useMatteMaterial: Bool) {
        node.enumerateChildNodes { child, _ in
            guard let geometry = child.geometry else { return }

            let materials = geometry.materials.isEmpty
                ? [SCNMaterial()]
                : geometry.materials.map { $0.copy() as? SCNMaterial ?? $0 }

            for material in materials {
                material.isDoubleSided = true
                if useMatteMaterial {
                    material.diffuse.contents = NSColor(calibratedRed: 0.72, green: 0.74, blue: 0.76, alpha: 1)
                    material.specular.contents = NSColor.black
                    material.emission.contents = NSColor.black
                    material.lightingModel = .lambert
                } else {
                    material.diffuse.contents = material.diffuse.contents ?? NSColor(calibratedWhite: 0.78, alpha: 1)
                    material.roughness.contents = 0.92
                    material.metalness.contents = 0.0
                    material.lightingModel = .physicallyBased
                }
            }
            geometry.materials = materials
        }
    }

    private static func placeholderScene() -> SCNScene {
        let scene = SCNScene()
        let node = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.03))
        scene.rootNode.addChildNode(node)
        return scene
    }

    private static func normalize(_ node: SCNNode) {
        let box = node.boundingBox
        let minV = box.min
        let maxV = box.max
        guard minV.x.isFinite, minV.y.isFinite, minV.z.isFinite,
              maxV.x.isFinite, maxV.y.isFinite, maxV.z.isFinite else {
            return
        }

        let center = SCNVector3(
            (minV.x + maxV.x) * 0.5,
            (minV.y + maxV.y) * 0.5,
            (minV.z + maxV.z) * 0.5
        )
        let extentX = maxV.x - minV.x
        let extentY = maxV.y - minV.y
        let extentZ = maxV.z - minV.z
        let maxExtent = Swift.max(Swift.max(extentX, extentY), extentZ)
        let scale = maxExtent > 0 ? 2.4 / maxExtent : 1.0

        node.position = SCNVector3(-center.x * scale, -center.y * scale, -center.z * scale)
        node.scale = SCNVector3(scale, scale, scale)
    }

    private static func addCameraAndLights(to scene: SCNScene) {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 100
        camera.position = SCNVector3(0, 0, 4.2)
        scene.rootNode.addChildNode(camera)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 430
        keyLight.eulerAngles = SCNVector3(-0.75, 0.55, 0.0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .ambient
        fillLight.light?.intensity = 150
        fillLight.light?.color = NSColor(white: 0.72, alpha: 1)
        scene.rootNode.addChildNode(fillLight)
    }
}

struct ModelPreviewWindow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.05)
                .ignoresSafeArea()

            if let url = model.modelPreviewURL {
                ModelSceneView(modelURL: url)
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        Text(url.lastPathComponent)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.black.opacity(0.42))
                            )
                            .padding(14)
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cube")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("还没有可预览的 OBJ")
                        .font(.system(size: 16, weight: .semibold))
                    Text("先生成 OBJ 模型，预览会自动加载。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var showCustomParameters = false
    @State private var showSidebar = true
    @State private var showInspector = true
    @State private var showLogDrawer = true
    @State private var previewSceneReloadID = UUID()

    private let pipelineOptions = ["512", "1024", "1024_cascade"]
    private let textureOptions = ["512", "1024", "2048"]
    private let bakeFaceOptions = ["50000", "100000", "200000"]
    private let seedSuggestions = ["7", "42", "123", "256", "512"]

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 1080

            ZStack {
                backgroundLayer

                VStack(spacing: 10) {
                    commandBar(isCompact: isCompact)

                    if isCompact {
                        compactWorkspace
                    } else {
                        expandedWorkspace
                    }

                    if showLogDrawer {
                        logDrawer
                    }

                    footerBar
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 980, minHeight: 700)
        .task {
            model.installBundledBackendIfNeeded()
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.058, blue: 0.064),
                    Color(red: 0.034, green: 0.036, blue: 0.041),
                    Color(red: 0.018, green: 0.020, blue: 0.024)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.055),
                    Color.clear,
                    Color.black.opacity(0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private func commandBar(isCompact: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: model.chooseInputImage) {
                Label("选择图片", systemImage: "photo")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .disabled(model.isBusy)

            Button(action: model.runGeometryStage) {
                Label("生成 OBJ", systemImage: "cube")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(model.isBusy)

            Button(action: model.runTextureStage) {
                Label("贴图 GLB", systemImage: "paintbrush")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .disabled(!model.hasBakeState || model.isBusy)

            Button(action: model.stopCurrentTask) {
                Label("停止", systemImage: "stop.fill")
            }
            .buttonStyle(ToolbarButtonStyle(isDestructive: true))
            .disabled(!model.isBusy)

            Spacer(minLength: 10)

            StatusBadge(text: model.statusText, isBusy: model.isBusy, isReady: model.hasPythonEnvironment)

            if !isCompact {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Label("侧栏", systemImage: "sidebar.left")
                }
                .buttonStyle(ToolbarButtonStyle())

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showInspector.toggle()
                    }
                } label: {
                    Label("检查器", systemImage: "sidebar.right")
                }
                .buttonStyle(ToolbarButtonStyle())
            }

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showLogDrawer.toggle()
                }
            } label: {
                Label(showLogDrawer ? "隐藏日志" : "显示日志", systemImage: "terminal")
            }
            .buttonStyle(ToolbarButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var expandedWorkspace: some View {
        HStack(alignment: .top, spacing: 10) {
            if showSidebar {
                ScrollView {
                    sidebar
                }
                .scrollIndicators(.hidden)
                .frame(width: 220)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            centerColumn
                .frame(maxWidth: .infinity, alignment: .top)

            if showInspector {
                inspectorColumn
                    .frame(width: 420)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var compactWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerPanel
                workflowPanel
                inputPanel
                parameterPanel
                previewPanel
                outputFilesPanel
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 2)
        }
    }

    private var logDrawer: some View {
        logPanel
            .frame(height: 230)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.blue.opacity(0.14))
                                .frame(width: 30, height: 30)
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.blue)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("TRELLIS.2")
                                    .font(.system(size: 16, weight: .bold))
                                Text("v0.1.0")
                                    .font(.system(size: 8, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.white.opacity(0.06)))
                                    .foregroundStyle(.secondary)
                            }
                            Text("for Apple Silicon")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(action: model.runGeometryStage) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                            Text("生成 OBJ 模型")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(model.seed)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                    }
                    .buttonStyle(SidebarPrimaryButtonStyle())
                    .disabled(model.isBusy)
                }
            }

            firstRunPanel

            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近生成")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        ForEach(recentJobs) { job in
                            recentJobRow(job)
                        }

                        Button("打开输出目录", action: model.openOutputDirectory)
                            .buttonStyle(SidebarSecondaryButtonStyle())
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("系统状态")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))

                        VStack(spacing: 8) {
                            ForEach(systemRows) { row in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(row.tint.opacity(0.16))
                                        .frame(width: 18, height: 18)
                                        .overlay(
                                            Image(systemName: row.icon)
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(row.tint)
                                        )

                                    Text(row.title)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Text(row.value)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.88))
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.028))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )

                    VStack(spacing: 4) {
                        sideActionButton(title: "生成贴图 GLB", icon: "paintbrush", action: model.runTextureStage)
                            .disabled(!model.hasBakeState || model.isBusy)
                        sideActionButton(title: "下载 Metal Toolchain", icon: "hammer", action: model.downloadMetalToolchain)
                            .disabled(model.isBusy)
                        sideActionButton(title: "设置", icon: "gearshape", action: model.chooseRepoFolder)
                            .disabled(model.isBusy)
                        sideActionButton(title: "关于 TRELLIS.2", icon: "info.circle", action: openAboutTrellis)
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.05))

                    HStack(spacing: 10) {
                        Circle()
                            .fill(model.hasPythonEnvironment ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)

                        Text(model.isBusy ? "就绪中" : "就绪")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))

                        Spacer()

                        Text("MPS (Apple Silicon)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var centerColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerPanel
                workflowPanel

                HStack(alignment: .top, spacing: 12) {
                    inputPanel
                        .frame(maxWidth: .infinity)
                    parameterPanel
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 2)
        }
    }

    private var inspectorColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewPanel
            outputFilesPanel
        }
    }

    private var headerPanel: some View {
        AppCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(displayTitle)
                            .font(.system(size: 16, weight: .semibold))
                        statusChip
                    }

                    Text(headerMetaLine)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11.5))
                }

                Spacer()

                HStack(spacing: 8) {
                    outputFilesMenu

                    Menu {
                        Button("查看 Repo", action: openRepoFolder)
                        Button("环境安装", action: model.runSetup)
                        Button("Hugging Face 登录", action: model.launchHuggingFaceLogin)
                    } label: {
                        Label("工具", systemImage: "wrench.and.screwdriver")
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(ToolbarButtonStyle())
                    .disabled(model.isBusy)

                    Button(action: { model.logs = "" }) {
                        Label("删除", systemImage: "trash")
                    }
                    .buttonStyle(ToolbarButtonStyle(isDestructive: true))
                    .disabled(model.logs.isEmpty)
                }
            }
        }
    }

    private var outputFilesMenu: some View {
        Menu {
            Section("生成") {
                Button("生成 OBJ", action: model.runGeometryStage)
                    .disabled(model.isBusy)
                Button("继续生成贴图 GLB", action: model.runTextureStage)
                    .disabled(!model.hasBakeState || model.isBusy)
            }

            Section("导出目录") {
                Button("打开目录", action: model.openOutputDirectory)
                    .disabled(model.outputDirectoryPath.isEmpty)
                Button("更改目录", action: model.chooseOutputDirectory)
                    .disabled(model.isBusy)
                Text(outputDirectoryDisplayName)
            }

            Section("文件") {
                ForEach(outputArtifacts) { artifact in
                    Button {
                        revealArtifact(artifact)
                    } label: {
                        Label("\(artifact.name) · \(artifact.meta)", systemImage: artifact.icon)
                    }
                }
            }
        } label: {
            Label("输出文件", systemImage: "folder")
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(ToolbarButtonStyle())
    }

    private var workflowPanel: some View {
        AppCard(title: "生成流程", subtitle: nil) {
            WorkflowStepper(items: workflowItems)
        }
    }

    private var firstRunPanel: some View {
        AppCard(title: "首次使用", subtitle: "按顺序完成安装、授权和检查") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    firstRunStepRow(
                        title: model.hasManagedBackend ? "应用内 Backend 已安装" : "安装应用内 Backend",
                        detail: model.hasManagedBackend ? "已准备 setup.sh 和 generate.py" : "把应用内后端复制到本机托管目录。",
                        icon: model.hasManagedBackend ? "checkmark" : "tray.and.arrow.down",
                        tint: model.hasManagedBackend ? .green : .blue
                    )
                    firstRunStepRow(
                        title: model.hasPythonEnvironment ? "Python 环境已安装" : "运行环境安装",
                        detail: model.hasPythonEnvironment ? "`.venv/bin/python` 已就绪" : "安装 Python 依赖、Hugging Face CLI 和运行环境。",
                        icon: model.hasPythonEnvironment ? "checkmark" : "terminal",
                        tint: model.hasPythonEnvironment ? .green : .orange
                    )
                    firstRunStepRow(
                        title: "申请 Hugging Face 模型访问",
                        detail: model.hasOpenedModelAccess ? "授权页面已打开，可继续确认访问权限。" : "先申请模型访问，再继续登录。",
                        icon: model.hasOpenedModelAccess ? "checkmark" : "person.crop.circle.badge.checkmark",
                        tint: model.hasOpenedModelAccess ? .green : .secondary
                    )
                    firstRunStepRow(
                        title: "登录 Hugging Face",
                        detail: model.hasStartedHuggingFaceLogin ? "Terminal 已打开登录命令。" : "在 Terminal 中运行 huggingface-cli login。",
                        icon: model.hasStartedHuggingFaceLogin ? "checkmark" : "person.badge.key",
                        tint: model.hasStartedHuggingFaceLogin ? .green : .secondary
                    )
                    firstRunStepRow(
                        title: model.hasCompletedBackendCheck ? "后端检查已通过" : "运行后端检查",
                        detail: model.hasCompletedBackendCheck ? "Backend 和运行时检查已经完成。" : "确认 generate.py 可以找到依赖和后端。",
                        icon: model.hasCompletedBackendCheck ? "checkmark" : "checklist",
                        tint: model.hasCompletedBackendCheck ? .green : .secondary
                    )
                }

                VStack(spacing: 4) {
                    sideActionButton(title: "安装 Backend", icon: "tray.and.arrow.down", action: model.installBundledBackendIfNeeded)
                        .disabled(model.isBusy)
                    sideActionButton(title: "环境安装", icon: "shippingbox", action: model.runSetup)
                        .disabled(model.isBusy || !model.hasRepoBackend)
                    sideActionButton(title: "模型授权", icon: "person.crop.circle.badge.checkmark", action: model.openModelAccessPages)
                    sideActionButton(title: "登录 Hugging Face", icon: "person.badge.key", action: model.launchHuggingFaceLogin)
                        .disabled(model.isBusy || !model.hasPythonEnvironment)
                    sideActionButton(title: "检查后端", icon: "cpu", action: model.checkBackends)
                        .disabled(model.isBusy || !model.hasPythonEnvironment)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(firstRunStatusTint)
                        .frame(width: 8, height: 8)

                    Text(model.setupStatusText)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(firstRunStatusTint.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(firstRunStatusTint.opacity(0.18), lineWidth: 1)
                )
            }
        }
    }

    private var inputPanel: some View {
        AppCard(title: "输入", subtitle: nil) {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: model.chooseInputImage) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))

                        if let image = inputPreviewImage {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(14)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("选择输入图片")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("建议使用单主体、背景干净、轮廓清晰的图片")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 188)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(inputImageURL?.lastPathComponent ?? "未选择图片")
                            .font(.system(size: 11.5, weight: .medium))
                    }

                    Text(inputMetaLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var parameterPanel: some View {
        AppCard(title: "控制面板", subtitle: "第一阶段先导出 OBJ，第二阶段按需烘焙 PBR GLB") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    presetTile(title: "快速", detail: "512 / 50K", icon: "bolt.fill", tint: .green, action: model.applyFastPreset)
                    presetTile(title: "标准", detail: "512 / 100K", icon: "slider.horizontal.3", tint: .blue, action: model.applyBalancedPreset)
                    presetTile(title: "高质量", detail: "1024 / 200K", icon: "sparkles", tint: .orange, action: model.applyHighQualityPreset)
                }
                .disabled(model.isBusy)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showCustomParameters.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("自定义参数")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("Pipeline \(model.pipelineType) · Texture \(model.textureSize)px · Seed \(model.seed)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showCustomParameters ? 180 : 0))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                if showCustomParameters {
                    VStack(alignment: .leading, spacing: 12) {
                        controlSection(title: "模型阶段", icon: "square.stack.3d.up") {
                            segmentedControl(
                                title: "Pipeline",
                                caption: pipelineCaption,
                                options: pipelineOptions,
                                selection: $model.pipelineType
                            )
                        }

                        controlSection(title: "贴图烘焙", icon: "paintpalette") {
                            segmentedControl(
                                title: "纹理",
                                caption: "Web 预览建议 512，精细导出可用 1024",
                                options: textureOptions,
                                selection: $model.textureSize,
                                display: { "\($0)px" }
                            )

                            segmentedControl(
                                title: "Bake 面数",
                                caption: "数值越高越慢，网页同步生成建议 50K-100K",
                                options: bakeFaceOptions,
                                selection: $model.bakeTargetFaces,
                                display: compactFaceLabel
                            )
                        }

                        controlSection(title: "输出", icon: "arrow.down.doc") {
                            editableField(title: "文件名", placeholder: "output_3d", text: $model.outputName)
                            editableField(title: "导出面数", placeholder: "原始", text: $model.simplifyTargetFaces)
                        }

                        controlSection(title: "Seed", icon: "number") {
                            HStack(spacing: 6) {
                                ForEach(seedSuggestions, id: \.self) { value in
                                    Button(value) {
                                        model.setSeed(value)
                                    }
                                    .buttonStyle(SeedChipButtonStyle(isSelected: model.seed == value))
                                }

                                TextField("Seed", text: $model.seed)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .frame(width: 68)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.white.opacity(0.055))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            }

                            HStack(spacing: 8) {
                                Button("下一个 Seed", action: model.retryWithNextSuggestedSeed)
                                    .buttonStyle(SecondaryActionButtonStyle())
                                Button("自动尝试", action: model.startAutoSeedSearch)
                                    .buttonStyle(SecondaryActionButtonStyle())
                            }
                            .disabled(model.isBusy)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .disabled(model.isBusy)
        }
    }

    private var outputFilesPanel: some View {
        AppCard(title: "输出文件", subtitle: "OBJ 预览完成后，可继续生成带 PBR 贴图的 GLB") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    iconBadge("folder", tint: .blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("导出文件夹")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(outputDirectoryDisplayName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button {
                        model.chooseOutputDirectory()
                    } label: {
                        Label("更改目录", systemImage: "folder.badge.gearshape")
                    }
                    .labelStyle(.titleAndIcon)
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(model.isBusy)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

                ForEach(outputArtifacts) { artifact in
                    outputArtifactRow(artifact)
                }

                HStack(spacing: 10) {
                    Button {
                        model.runGeometryStage()
                    } label: {
                        Label("生成 OBJ", systemImage: "cube")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(model.isBusy)

                    Button {
                        model.runTextureStage()
                    } label: {
                        Label("继续生成贴图 GLB", systemImage: "paintbrush")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!model.hasBakeState || model.isBusy)

                    Spacer()

                    Button {
                        model.openOutputDirectory()
                    } label: {
                        Label("打开目录", systemImage: "arrow.up.forward.app")
                    }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(model.outputDirectoryPath.isEmpty)
                }
                .padding(.top, 2)
            }
        }
    }

    private var previewPanel: some View {
        AppCard(title: "3D 预览", subtitle: nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        previewPill(title: previewKindTitle, icon: "cube")
                        previewPill(title: modelPreviewURL == nil ? "等待模型" : "可旋转", icon: "rotate.3d")
                        Button {
                            openWindow(id: "modelPreview")
                        } label: {
                            Label("打开预览窗", systemImage: "rectangle.on.rectangle")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    }
                }

                ZStack {
                    PreviewGridBackground()

                    if let modelPreviewURL {
                        ModelSceneView(modelURL: modelPreviewURL)
                            .id(previewSceneReloadID)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else if let image = inputPreviewImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 18)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "cube")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("暂无预览")
                                .font(.system(size: 13, weight: .semibold))
                            Text("生成 OBJ 后可在这里旋转查看模型。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack {
                        HStack {
                            Spacer()
                            axisIndicator
                        }
                        Spacer()
                    }
                    .padding(12)

                    HStack {
                        Spacer()

                        VStack(spacing: 10) {
                            viewerToolIcon("arrow.triangle.2.circlepath", title: "重置视角") {
                                previewSceneReloadID = UUID()
                            }
                            .disabled(modelPreviewURL == nil)

                            viewerToolIcon("rectangle.on.rectangle", title: "独立窗口") {
                                openWindow(id: "modelPreview")
                            }

                            viewerToolIcon("folder", title: "打开输出目录", action: model.openOutputDirectory)
                                .disabled(model.outputDirectoryPath.isEmpty)

                            viewerToolIcon("magnifyingglass", title: "在访达中显示") {
                                if let url = modelPreviewURL {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                } else {
                                    model.openOutputDirectory()
                                }
                            }
                            .disabled(modelPreviewURL == nil && model.outputDirectoryPath.isEmpty)
                        }
                    }
                    .padding(.trailing, 10)
                }
                .frame(height: 344)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    ForEach(Array(previewThumbnails.enumerated()), id: \.offset) { index, thumbnail in
                        previewThumbnail(thumbnail, isSelected: index == 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var logPanel: some View {
        AppCard(title: "运行日志", subtitle: nil) {
            VStack(alignment: .leading, spacing: 10) {
                if !model.failureHint.isEmpty {
                    statusBanner(title: "失败提示", text: model.failureHint, tint: .orange)
                }

                if model.autoRetryActive {
                    statusBanner(title: "自动尝试中", text: model.autoRetrySummary, tint: .blue)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.isBusy ? "进行中" : "命令输出")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(model.statusText)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Spacer()
                    Button("清空") {
                        model.logs = ""
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .disabled(model.logs.isEmpty)
                }

                ScrollView {
                    Text(model.logs.isEmpty ? "日志会显示在这里。" : model.logs)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Color(red: 0.58, green: 0.93, blue: 0.61))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(minHeight: 196)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    private var footerBar: some View {
        HStack {
            Text("Python 3.11 (\(repoDisplayName))")
                .foregroundStyle(.secondary)
            Spacer()
            Text("版本: \(model.pipelineType)")
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: model.runSetup) {
                Label("检查更新", systemImage: "gear")
            }
            .buttonStyle(ToolbarButtonStyle())
            .disabled(model.isBusy)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var displayTitle: String {
        inputImageURL?.lastPathComponent ?? "请选择输入图片"
    }

    private var displayOutputName: String {
        let trimmed = model.outputName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "output_3d" : trimmed
    }

    private var outputDirectoryDisplayName: String {
        let trimmed = model.outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未选择" }

        let url = URL(fileURLWithPath: trimmed)
        let folderName = url.lastPathComponent.isEmpty ? trimmed : url.lastPathComponent
        return "\(folderName) · \(trimmed)"
    }

    private var runtimeLabel: String {
        if model.isBusy {
            return "进行中"
        }
        if !model.failureHint.isEmpty {
            return "需要处理"
        }
        if modelPreviewURL != nil {
            return "模型已生成"
        }
        return "等待运行"
    }

    private var headerMetaLine: String {
        if model.isBusy {
            return "\(model.statusText) · Pipeline \(model.pipelineType) · Seed \(model.seed)"
        }
        if let modelPreviewURL {
            return "\(runtimeLabel) · \(modelPreviewURL.lastPathComponent) · \(modificationDateText(for: modelPreviewURL))"
        }
        if inputImageURL != nil {
            return "已选择输入 · \(inputMetaLine) · Pipeline \(model.pipelineType) · Seed \(model.seed)"
        }
        return "等待输入图片 · Pipeline \(model.pipelineType) · Seed \(model.seed)"
    }

    private var statusChip: some View {
        Text(currentStatusTitle)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(currentStatusColor.opacity(0.18)))
            .overlay(Capsule().stroke(currentStatusColor.opacity(0.22), lineWidth: 1))
            .foregroundStyle(currentStatusColor)
    }

    private var currentStatusTitle: String {
        if model.isBusy { return "运行中" }
        if !model.failureHint.isEmpty { return "失败" }
        if modelPreviewURL != nil { return "完成" }
        if !model.inputImagePath.isEmpty { return "就绪" }
        return "待机"
    }

    private var currentStatusColor: Color {
        if model.isBusy { return .blue }
        if !model.failureHint.isEmpty { return .orange }
        if modelPreviewURL != nil { return .green }
        if !model.inputImagePath.isEmpty { return .blue }
        return .secondary
    }

    private var repoDisplayName: String {
        let name = URL(fileURLWithPath: model.repoPath).lastPathComponent
        return name.isEmpty ? "trellis-mac" : name
    }

    private var inputImageURL: URL? {
        guard !model.inputImagePath.isEmpty else { return nil }
        return URL(fileURLWithPath: model.inputImagePath)
    }

    private var inputPreviewImage: NSImage? {
        guard let inputImageURL else { return nil }
        return NSImage(contentsOf: inputImageURL)
    }

    private var modelPreviewURL: URL? {
        model.modelPreviewURL
    }

    private var previewKindTitle: String {
        guard let modelPreviewURL else { return "预览" }
        let ext = modelPreviewURL.pathExtension.uppercased()
        return ext.isEmpty ? "模型" : ext
    }

    private var inputMetaLine: String {
        guard let inputImageURL else { return "未选择图片" }
        let dimension = imageResolutionText(for: inputImageURL) ?? "未知尺寸"
        return "\(dimension) · \(byteCountText(for: inputImageURL))"
    }

    private var recentJobs: [RecentJob] {
        var items: [RecentJob] = []

        if let inputImageURL {
            items.append(
                RecentJob(
                    title: inputImageURL.lastPathComponent,
                    subtitle: model.statusText,
                    detail: "\(model.pipelineType) · \(model.textureSize)px",
                    path: inputImageURL.path,
                    status: model.isBusy ? "运行中" : (model.failureHint.isEmpty ? "完成" : "失败"),
                    tint: model.failureHint.isEmpty ? .green : .orange
                )
            )
        }

        let samples = ["shoe_input.png", "backpack.png", "vase.png", "camera.png", "helmet.png"]
        for name in samples {
            let path = URL(fileURLWithPath: model.repoPath).appendingPathComponent("assets/\(name)").path
            items.append(
                RecentJob(
                    title: name,
                    subtitle: "2 分钟前",
                    detail: "512 · 1024px",
                    path: path,
                    status: name == "camera.png" ? "失败" : "完成",
                    tint: name == "camera.png" ? .orange : .green
                )
            )
        }

        return Array(items.prefix(5))
    }

    private var systemRows: [SystemRow] {
        [
            SystemRow(title: "MPS 后端", value: "启用", icon: "cpu", tint: .green),
            SystemRow(title: "Python 环境", value: model.hasPythonEnvironment ? "已就绪" : "未安装", icon: "checkmark.seal", tint: model.hasPythonEnvironment ? .green : .orange),
            SystemRow(title: "磁盘空间", value: freeDiskText, icon: "externaldrive", tint: .secondary),
            SystemRow(title: "温度", value: "Apple Silicon", icon: "thermometer.medium", tint: .secondary)
        ]
    }

    private var freeDiskText: String {
        let repoURL = URL(fileURLWithPath: model.repoPath)
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey]
        if let values = try? repoURL.resourceValues(forKeys: keys),
           let available = values.volumeAvailableCapacityForImportantUsage {
            return ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
        }
        return "未知"
    }

    private var pipelineCaption: String {
        switch model.pipelineType {
        case "512":
            return "最快，适合先看形体"
        case "1024":
            return "细节更多，耗时更长"
        case "1024_cascade":
            return "最高质量，第一阶段也会明显变慢"
        default:
            return "选择生成分辨率"
        }
    }

    private var workflowItems: [WorkflowDisplayItem] {
        let lowerLogs = model.logs.lowercased()
        let isTextureStage = lowerLogs.contains("trellis.2 texture bake stage")
            || lowerLogs.contains("--stage texture")
            || model.statusText.contains("贴图")
        let isGeometryStage = lowerLogs.contains("stage: geometry")
            || lowerLogs.contains("--stage geometry")
            || model.statusText.contains("OBJ")

        let objFinishedInCurrentRun = lowerLogs.contains("saved geometry obj")
            || lowerLogs.contains("saved bake state")
            || model.statusText.contains("生成 OBJ 模型完成")
        let glbFinishedInCurrentRun = lowerLogs.contains("saved baked glb")
            || lowerLogs.contains("texture stage time")
            || model.statusText.contains("生成贴图 GLB完成")
        let objReady = objFinishedInCurrentRun || isTextureStage || (!model.isBusy && model.hasBakeState)
        let glbReady = glbFinishedInCurrentRun || (!model.isBusy && hasBakedGLBOutput)

        var states = Array(repeating: WorkflowDisplayItem.State.pending, count: 6)

        if glbReady {
            states = Array(repeating: .complete, count: 6)
        } else if isTextureStage {
            states[0] = .complete
            states[1] = .complete
            states[2] = .complete
            states[3] = .complete
            states[4] = glbFinishedInCurrentRun ? .complete : .active
            states[5] = glbFinishedInCurrentRun ? .complete : .pending
        } else if objReady {
            states[0] = .complete
            states[1] = .complete
            states[2] = .complete
            states[3] = .complete
        } else if model.isBusy || isGeometryStage {
            if lowerLogs.contains("mesh:") || lowerLogs.contains("generation time:") {
                states[0] = .complete
                states[1] = .complete
                states[2] = .complete
                states[3] = .active
            } else if lowerLogs.contains("sampling sparse structure")
                || lowerLogs.contains("sampling shape slat")
                || lowerLogs.contains("generating obj geometry")
                || lowerLogs.contains("generating 3d model") {
                states[0] = .complete
                states[1] = .complete
                states[2] = .active
            } else if lowerLogs.contains("input:") {
                states[0] = .complete
                states[1] = .active
            } else if !model.inputImagePath.isEmpty {
                states[0] = .active
            }
        }

        let titles = ["图片预处理", "编码 (DINOv3)", "3D 生成", "导出 OBJ", "贴图烘焙", "导出 GLB"]
        return zip(titles, states).map { title, state in
            WorkflowDisplayItem(title: title, duration: workflowDuration(for: state), state: state)
        }
    }

    private var hasBakedGLBOutput: Bool {
        let url = URL(fileURLWithPath: model.outputDirectoryPath)
            .appendingPathComponent("\(displayOutputName)_baked.glb")
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func workflowDuration(for state: WorkflowDisplayItem.State) -> String {
        switch state {
        case .pending:
            return "等待"
        case .active:
            return "进行中"
        case .complete:
            return "完成"
        }
    }

    private var outputArtifacts: [OutputArtifact] {
        let outputURL = URL(fileURLWithPath: model.outputDirectoryPath)
        let manager = FileManager.default
        let prefix = displayOutputName

        if let files = try? manager.contentsOfDirectory(at: outputURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            let matches = files
                .filter { $0.lastPathComponent.hasPrefix(prefix) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            if !matches.isEmpty {
                return matches.map(outputArtifact(for:))
            }
        }

        var placeholders = [
            OutputArtifact(name: "\(prefix).obj", kind: "OBJ", meta: "第一阶段", url: nil, icon: "cube", tint: .blue),
            OutputArtifact(name: "\(prefix).trellis_state.pt", kind: "Bake State", meta: "第二阶段输入", url: nil, icon: "archivebox", tint: .secondary)
        ]
        if model.hasBakeState {
            placeholders.append(OutputArtifact(name: "\(prefix)_baked.glb", kind: "GLB (PBR)", meta: "\(model.textureSize) x \(model.textureSize)", url: nil, icon: "cube.transparent", tint: .cyan))
        }
        return placeholders
    }

    private var previewThumbnails: [URL] {
        guard let inputImageURL else { return [] }
        return [inputImageURL]
    }

    @ViewBuilder
    private func recentJobRow(_ job: RecentJob) -> some View {
        Button(action: {
            if FileManager.default.fileExists(atPath: job.path) {
                model.inputImagePath = job.path
            }
        }) {
            HStack(spacing: 8) {
                recentThumbnail(path: job.path)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(job.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                        Text(job.status)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(job.tint)
                    }

                    Text(job.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(job.detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    private var firstRunStatusTint: Color {
        if model.hasCompletedBackendCheck {
            return .green
        }
        if model.hasPythonEnvironment && model.hasRepoBackend {
            return .blue
        }
        return .orange
    }

    @ViewBuilder
    private func firstRunStepRow(title: String, detail: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.034))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.052), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func recentThumbnail(path: String) -> some View {
        if let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                )
        }
    }

    @ViewBuilder
    private func sideActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 12)
                Text(title)
                Spacer()
            }
        }
        .buttonStyle(SidebarSecondaryButtonStyle())
    }

    @ViewBuilder
    private func workflowStep(_ item: WorkflowDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(item.state.fillColor)
                        .frame(width: 16, height: 16)
                    Image(systemName: item.state.symbolName)
                        .font(.system(size: item.state == .active ? 6 : 8, weight: .bold))
                        .foregroundStyle(item.state.symbolColor)
                }
                Text(item.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(item.state.titleColor)
            }

            Text(item.duration)
                .font(.system(size: 10.5))
                .foregroundStyle(item.state.detailColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func parameterRow<Control: View, Value: View>(title: String, @ViewBuilder control: () -> Control, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                control()
            }
            Spacer()
            value()
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    @ViewBuilder
    private func presetTile(title: String, detail: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(detail)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PresetTileButtonStyle(tint: tint))
    }

    @ViewBuilder
    private func controlSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
            }

            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.032))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func segmentedControl(
        title: String,
        caption: String,
        options: [String],
        selection: Binding<String>,
        display: @escaping (String) -> String = { $0 }
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(caption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(display(option))
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OptionSegmentButtonStyle(isSelected: selection.wrappedValue == option))
                }
            }
        }
    }

    @ViewBuilder
    private func editableField(title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private func compactFaceLabel(_ value: String) -> String {
        guard let count = Int(value) else { return value }
        if count >= 1000 {
            return "\(count / 1000)K"
        }
        return value
    }

    @ViewBuilder
    private func iconBadge(_ systemName: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.12))
                .frame(width: 28, height: 28)
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    @ViewBuilder
    private func outputArtifactRow(_ artifact: OutputArtifact) -> some View {
        HStack(spacing: 12) {
            iconBadge(artifact.icon, tint: artifact.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(artifact.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(artifact.kind)
                    Text("·")
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(artifact.meta)
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { revealArtifact(artifact) }) {
                Image(systemName: "magnifyingglass")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(IconOnlyButtonStyle())

            Button(action: { openArtifact(artifact) }) {
                Image(systemName: "arrow.up.forward")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(IconOnlyButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.034))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.052), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func previewPill(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var axisIndicator: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Y")
                .foregroundStyle(.green)
            HStack(spacing: 6) {
                Text("Z")
                    .foregroundStyle(.cyan)
                Text("X")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 11, weight: .bold))
    }

    @ViewBuilder
    private func viewerToolIcon(_ systemName: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .help(title)
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.24))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func previewThumbnail(_ url: URL, isSelected: Bool) -> some View {
        let image = NSImage(contentsOf: url)

        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 42)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.blue : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        )
    }

    @ViewBuilder
    private func statusBanner(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private func imageResolutionText(for url: URL) -> String? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        guard width > 0, height > 0 else { return nil }
        return "\(width) x \(height)"
    }

    private func byteCountText(for url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return "未知大小"
        }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    private func modificationDateText(for url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else {
            return "更新时间未知"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func outputArtifact(for url: URL) -> OutputArtifact {
        let name = url.lastPathComponent
        let lowerName = name.lowercased()
        let fileSize = byteCountText(for: url)

        if lowerName.hasSuffix("_baked.glb") {
            return OutputArtifact(name: name, kind: "GLB (PBR)", meta: fileSize, url: url, icon: "cube.transparent", tint: .cyan)
        }
        if lowerName.hasSuffix(".glb") {
            return OutputArtifact(name: name, kind: "GLB (几何)", meta: fileSize, url: url, icon: "shippingbox", tint: .blue)
        }
        if lowerName.hasSuffix(".obj") {
            return OutputArtifact(name: name, kind: "OBJ", meta: fileSize, url: url, icon: "cube", tint: .blue)
        }
        if lowerName.hasSuffix(".trellis_state.pt") {
            return OutputArtifact(name: name, kind: "Bake State", meta: fileSize, url: url, icon: "archivebox", tint: .secondary)
        }
        if lowerName.contains("basecolor") {
            return OutputArtifact(name: name, kind: "Base Color", meta: textureMeta(for: url, fallback: fileSize), url: url, icon: "photo", tint: .green)
        }
        if lowerName.contains("metallic") {
            return OutputArtifact(name: name, kind: "Metallic", meta: textureMeta(for: url, fallback: fileSize), url: url, icon: "circle.lefthalf.filled", tint: .yellow)
        }
        if lowerName.contains("roughness") {
            return OutputArtifact(name: name, kind: "Roughness", meta: textureMeta(for: url, fallback: fileSize), url: url, icon: "aqi.medium", tint: .orange)
        }
        if lowerName.contains("normal") {
            return OutputArtifact(name: name, kind: "Normal (OpenGL)", meta: textureMeta(for: url, fallback: fileSize), url: url, icon: "square.stack.3d.up", tint: .purple)
        }
        return OutputArtifact(name: name, kind: url.pathExtension.uppercased(), meta: fileSize, url: url, icon: "doc", tint: .secondary)
    }

    private func textureMeta(for url: URL, fallback: String) -> String {
        if let resolution = imageResolutionText(for: url) {
            return "\(resolution) · \(fallback)"
        }
        return fallback
    }

    private func revealArtifact(_ artifact: OutputArtifact) {
        if let url = artifact.url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            model.openOutputDirectory()
        }
    }

    private func openArtifact(_ artifact: OutputArtifact) {
        if let url = artifact.url {
            NSWorkspace.shared.open(url)
        } else {
            model.openOutputDirectory()
        }
    }

    private func openRepoFolder() {
        let url = URL(fileURLWithPath: model.repoPath)
        NSWorkspace.shared.open(url)
    }

    private func openAboutTrellis() {
        if let url = URL(string: "https://github.com/microsoft/TRELLIS.2") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct AppCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let compact: Bool
    @ViewBuilder var content: Content

    init(title: String? = nil, subtitle: String? = nil, compact: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.compact = compact
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let title {
                        Text(title)
                            .font(.system(size: compact ? 13 : 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content
        }
        .padding(compact ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.052),
                            Color.white.opacity(0.026)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
    }
}

private struct WorkflowStepper: View {
    let items: [WorkflowDisplayItem]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    workflowNode(item)

                    if index < items.count - 1 {
                        Capsule(style: .continuous)
                            .fill(item.connectorColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 2)
                            .padding(.horizontal, 7)
                    }
                }
            }

            HStack(alignment: .top, spacing: 0) {
                ForEach(items) { item in
                    VStack(spacing: 3) {
                        Text(item.shortTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(item.state.titleColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(item.duration)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(item.state.detailColor)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func workflowNode(_ item: WorkflowDisplayItem) -> some View {
        ZStack {
            Circle()
                .fill(item.state.fillColor)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(item.state.ringColor, lineWidth: 1)
                )

            Image(systemName: item.state.symbolName)
                .font(.system(size: item.state == .active ? 7 : 10, weight: .bold))
                .foregroundStyle(item.state.symbolColor)
        }
        .frame(width: 24, height: 24)
        .background(
            Circle()
                .fill(item.state == .active ? Color.green.opacity(0.14) : Color.clear)
                .frame(width: 36, height: 36)
        )
    }
}

private struct StatusBadge: View {
    let text: String
    let isBusy: Bool
    let isReady: Bool

    private var tint: Color {
        if isBusy { return .orange }
        if isReady { return .green }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.14))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .foregroundStyle(tint)
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.07, green: 0.43, blue: 0.98),
                                Color(red: 0.10, green: 0.32, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .opacity(configuration.isPressed ? 0.86 : 1.0)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

private struct SidebarPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.07, green: 0.43, blue: 0.98),
                                Color(red: 0.06, green: 0.31, blue: 0.92)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .opacity(configuration.isPressed ? 0.88 : 1.0)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

private struct SidebarSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.06 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    let isDestructive: Bool

    init(isDestructive: Bool = false) {
        self.isDestructive = isDestructive
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(isDestructive ? Color.red.opacity(0.92) : Color.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke((isDestructive ? Color.red : Color.white).opacity(0.08), lineWidth: 1)
            )
    }
}

private struct PresetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct PresetTileButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .frame(minHeight: 74)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(configuration.isPressed ? 0.16 : 0.12),
                                Color.white.opacity(configuration.isPressed ? 0.06 : 0.035)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(configuration.isPressed ? 0.26 : 0.18), lineWidth: 1)
            )
    }
}

private struct OptionSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.72))
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(configuration.isPressed ? 0.07 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.05), lineWidth: 1)
            )
    }
}

private struct SeedChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.blue : Color.white.opacity(configuration.isPressed ? 0.08 : 0.045))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke((isSelected ? Color.blue : Color.white).opacity(0.08), lineWidth: 1)
            )
    }
}

private struct IconOnlyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.74))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct PreviewGridBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.09, blue: 0.14),
                        Color(red: 0.04, green: 0.05, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Path { path in
                    let horizontalCount = 9
                    for index in 0...horizontalCount {
                        let progress = CGFloat(index) / CGFloat(horizontalCount)
                        let y = height * 0.58 + progress * height * 0.45
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }

                    for index in 0...12 {
                        let x = width * CGFloat(index) / 12
                        path.move(to: CGPoint(x: x, y: height))
                        path.addLine(to: CGPoint(x: width / 2, y: height * 0.56))
                    }
                }
                .stroke(Color.blue.opacity(0.16), lineWidth: 1)

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 180
                )
                .blur(radius: 16)
            }
        }
    }
}

private struct RecentJob: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let detail: String
    let path: String
    let status: String
    let tint: Color
}

private struct SystemRow: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let tint: Color
}

private struct OutputArtifact: Identifiable {
    let id = UUID()
    let name: String
    let kind: String
    let meta: String
    let url: URL?
    let icon: String
    let tint: Color
}

private struct WorkflowDisplayItem: Identifiable {
    enum State {
        case pending
        case active
        case complete

        var fillColor: Color {
            switch self {
            case .pending:
                return Color.white.opacity(0.08)
            case .active:
                return .green
            case .complete:
                return .green
            }
        }

        var ringColor: Color {
            switch self {
            case .pending:
                return Color.white.opacity(0.22)
            case .active:
                return Color.green.opacity(0.95)
            case .complete:
                return Color.green.opacity(0.95)
            }
        }

        var symbolName: String {
            switch self {
            case .pending:
                return "circle"
            case .active:
                return "circle.fill"
            case .complete:
                return "checkmark"
            }
        }

        var symbolColor: Color {
            switch self {
            case .pending:
                return Color.white.opacity(0.62)
            case .active, .complete:
                return .white
            }
        }

        var titleColor: Color {
            switch self {
            case .pending:
                return Color.white.opacity(0.48)
            case .active:
                return .green
            case .complete:
                return Color.white.opacity(0.92)
            }
        }

        var detailColor: Color {
            switch self {
            case .pending:
                return Color.white.opacity(0.42)
            case .active:
                return .green
            case .complete:
                return Color.green.opacity(0.92)
            }
        }
    }

    let id = UUID()
    let title: String
    let duration: String
    let state: State

    var shortTitle: String {
        switch title {
        case "图片预处理":
            return "预处理"
        case "编码 (DINOv3)":
            return "编码"
        case "3D 生成":
            return "生成"
        case "导出 OBJ":
            return "OBJ"
        case "贴图烘焙":
            return "烘焙"
        case "导出 GLB":
            return "GLB"
        default:
            return title
        }
    }

    var connectorColor: Color {
        switch state {
        case .pending, .active:
            return Color.white.opacity(0.10)
        case .complete:
            return Color.green.opacity(0.86)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var repoPath: String {
        didSet { defaults.set(repoPath, forKey: Keys.repoPath) }
    }
    @Published var inputImagePath: String {
        didSet { defaults.set(inputImagePath, forKey: Keys.inputImagePath) }
    }
    @Published var outputDirectoryPath: String {
        didSet { defaults.set(outputDirectoryPath, forKey: Keys.outputDirectoryPath) }
    }
    @Published var outputName: String {
        didSet { defaults.set(outputName, forKey: Keys.outputName) }
    }
    @Published var seed: String {
        didSet { defaults.set(seed, forKey: Keys.seed) }
    }
    @Published var pipelineType: String {
        didSet { defaults.set(pipelineType, forKey: Keys.pipelineType) }
    }
    @Published var textureSize: String {
        didSet { defaults.set(textureSize, forKey: Keys.textureSize) }
    }
    @Published var simplifyTargetFaces: String {
        didSet { defaults.set(simplifyTargetFaces, forKey: Keys.simplifyTargetFaces) }
    }
    @Published var bakeTargetFaces: String {
        didSet { defaults.set(bakeTargetFaces, forKey: Keys.bakeTargetFaces) }
    }
    @Published var noTexture: Bool {
        didSet { defaults.set(noTexture, forKey: Keys.noTexture) }
    }
    @Published var logs = ""
    @Published var isBusy = false
    @Published var statusText = "待机"
    @Published var failureHint = ""
    @Published var autoRetryActive = false
    @Published var autoRetrySummary = ""

    private let defaults = UserDefaults.standard
    private var process: Process?
    private var stopRequested = false
    private let suggestedSeeds = ["7", "42", "123", "256", "512"]
    private var pendingAutoSeeds: [String] = []

    var hasManagedBackend: Bool {
        FileManager.default.fileExists(atPath: managedBackendURL.appendingPathComponent("setup.sh").path)
            && FileManager.default.fileExists(atPath: managedBackendURL.appendingPathComponent("generate.py").path)
    }

    var hasRepoBackend: Bool {
        FileManager.default.fileExists(atPath: setupScriptPath)
            && FileManager.default.fileExists(atPath: generateScriptPath)
    }

    var hasOpenedModelAccess: Bool {
        logs.contains("已打开 Hugging Face 模型授权页面。")
    }

    var hasStartedHuggingFaceLogin: Bool {
        logs.contains("huggingface-cli login")
    }

    var hasCompletedBackendCheck: Bool {
        logs.contains("== 检查后端完成 ==") || statusText == "检查后端完成"
    }

    var setupStatusText: String {
        if !hasManagedBackend { return "等待安装应用内 Backend" }
        if !hasRepoBackend { return "Backend 路径未就绪" }
        if !hasPythonEnvironment { return "Python 环境未安装" }
        if !hasCompletedBackendCheck { return "环境已就绪，建议继续运行后端检查" }
        return "Backend 已就绪，可以开始生成"
    }

    var hasPythonEnvironment: Bool {
        FileManager.default.fileExists(atPath: pythonExecutablePath)
    }

    var hasBakeState: Bool {
        FileManager.default.fileExists(atPath: bakeStatePath)
    }

    var modelPreviewURL: URL? {
        let outputURL = URL(fileURLWithPath: outputDirectoryPath)
        let bakedGLBURL = outputURL.appendingPathComponent("\(resolvedOutputName)_baked.glb")
        if FileManager.default.fileExists(atPath: bakedGLBURL.path) {
            return bakedGLBURL
        }

        let objURL = outputURL.appendingPathComponent("\(resolvedOutputName).obj")
        if FileManager.default.fileExists(atPath: objURL.path) {
            return objURL
        }

        let glbURL = outputURL.appendingPathComponent("\(resolvedOutputName).glb")
        if FileManager.default.fileExists(atPath: glbURL.path) {
            return glbURL
        }

        return nil
    }

    private var resolvedOutputName: String {
        let trimmed = outputName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "output_3d" : trimmed
    }

    private var bakeStatePath: String {
        URL(fileURLWithPath: outputDirectoryPath)
            .appendingPathComponent("\(resolvedOutputName).trellis_state.pt")
            .path
    }

    private var setupScriptPath: String {
        URL(fileURLWithPath: repoPath).appendingPathComponent("setup.sh").path
    }

    private var generateScriptPath: String {
        URL(fileURLWithPath: repoPath).appendingPathComponent("generate.py").path
    }

    private var pythonExecutablePath: String {
        URL(fileURLWithPath: repoPath).appendingPathComponent(".venv/bin/python").path
    }

    private var applicationSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TrellisMac", isDirectory: true)
    }

    private var managedBackendURL: URL {
        applicationSupportURL.appendingPathComponent("Backend", isDirectory: true)
    }

    private var managedOutputURL: URL {
        applicationSupportURL.appendingPathComponent("Outputs", isDirectory: true)
    }

    private var bundledBackendURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Backend", isDirectory: true)
    }

    init() {
        let repoDefault = AppModel.defaultRepoPath()
        let outputDefault = AppModel.defaultOutputDirectoryPath()
        repoPath = defaults.string(forKey: Keys.repoPath) ?? repoDefault
        inputImagePath = defaults.string(forKey: Keys.inputImagePath) ?? ""
        outputDirectoryPath = defaults.string(forKey: Keys.outputDirectoryPath) ?? outputDefault
        outputName = defaults.string(forKey: Keys.outputName) ?? "output_3d"
        seed = defaults.string(forKey: Keys.seed) ?? "42"
        pipelineType = defaults.string(forKey: Keys.pipelineType) ?? "512"
        let hasBakeFacesPreference = defaults.object(forKey: Keys.bakeTargetFaces) != nil
        if hasBakeFacesPreference {
            textureSize = defaults.string(forKey: Keys.textureSize) ?? "512"
            simplifyTargetFaces = defaults.string(forKey: Keys.simplifyTargetFaces) ?? ""
            bakeTargetFaces = defaults.string(forKey: Keys.bakeTargetFaces) ?? "100000"
            noTexture = defaults.object(forKey: Keys.noTexture) == nil ? true : defaults.bool(forKey: Keys.noTexture)
        } else {
            textureSize = "512"
            simplifyTargetFaces = ""
            bakeTargetFaces = "100000"
            noTexture = true
            defaults.set(textureSize, forKey: Keys.textureSize)
            defaults.set(simplifyTargetFaces, forKey: Keys.simplifyTargetFaces)
            defaults.set(bakeTargetFaces, forKey: Keys.bakeTargetFaces)
            defaults.set(noTexture, forKey: Keys.noTexture)
        }
    }

    func applyFastPreset() {
        pipelineType = "512"
        textureSize = "512"
        simplifyTargetFaces = ""
        bakeTargetFaces = "50000"
        noTexture = true
        appendLog("已应用快速预设：pipeline=512，仅导出几何体 GLB/OBJ\n")
    }

    func applyBalancedPreset() {
        pipelineType = "512"
        textureSize = "512"
        simplifyTargetFaces = ""
        bakeTargetFaces = "100000"
        noTexture = false
        appendLog("已应用标准预设：pipeline=512, texture=512, bake_faces=100000\n")
    }

    func applyHighQualityPreset() {
        pipelineType = "1024_cascade"
        textureSize = "1024"
        simplifyTargetFaces = ""
        bakeTargetFaces = "200000"
        noTexture = false
        appendLog("已应用高质量预设：pipeline=1024_cascade, texture=1024, bake_faces=200000\n")
    }

    func setSeed(_ newSeed: String) {
        seed = newSeed
        appendLog("已切换 Seed: \(newSeed)\n")
    }

    func retryWithNextSuggestedSeed() {
        let currentIndex = suggestedSeeds.firstIndex(of: seed) ?? -1
        let nextIndex = (currentIndex + 1) % suggestedSeeds.count
        let nextSeed = suggestedSeeds[nextIndex]
        seed = nextSeed
        appendLog("已切换到下一个推荐 Seed: \(nextSeed)\n")
        runGeneration()
    }

    func startAutoSeedSearch() {
        let currentSeed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseSeed = currentSeed.isEmpty ? "42" : currentSeed
        pendingAutoSeeds = [baseSeed] + suggestedSeeds.filter { $0 != baseSeed }
        autoRetryActive = true
        autoRetrySummary = "准备依次尝试: \(pendingAutoSeeds.joined(separator: ", "))"
        appendLog("开始自动尝试 Seeds: \(pendingAutoSeeds.joined(separator: ", "))\n")
        runNextAutoSeedAttempt()
    }

    func chooseRepoFolder() {
        guard let url = chooseDirectory(prompt: "选择 trellis-mac 仓库目录") else { return }
        repoPath = url.path
        defaults.set(true, forKey: Keys.repoPathCustomized)
        if outputDirectoryPath.isEmpty {
            outputDirectoryPath = url.path
        }
        appendLog("已切换 Repo 路径: \(url.path)\n")
    }

    func chooseInputImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "选择图片"

        if panel.runModal() == .OK, let url = panel.url {
            inputImagePath = url.path
            appendLog("已选择输入图片: \(url.path)\n")
        }
    }

    func chooseOutputDirectory() {
        guard let url = chooseDirectory(prompt: "选择模型输出目录") else { return }
        outputDirectoryPath = url.path
        defaults.set(true, forKey: Keys.outputDirectoryPathCustomized)
        appendLog("已选择输出目录: \(url.path)\n")
    }

    func openModelAccessPages() {
        openURL("https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m")
        openURL("https://huggingface.co/briaai/RMBG-2.0")
        appendLog("已打开 Hugging Face 模型授权页面。\n")
    }

    func launchHuggingFaceLogin() {
        guard validateRepo() else { return }

        guard hasPythonEnvironment else {
            presentError("未检测到 `.venv/bin/python`，请先运行环境安装。")
            return
        }

        let shellCommand = "cd \(shellQuoted(repoPath)); source .venv/bin/activate; huggingface-cli login"
        let script = """
        tell application "Terminal"
            activate
            do script "\(appleScriptEscaped(shellCommand))"
        end tell
        """

        runDetachedCommand(
            label: "启动 Hugging Face 登录",
            executable: "/usr/bin/osascript",
            arguments: ["-e", script]
        )
        appendLog("已在 Terminal 中打开 `huggingface-cli login`。\n")
    }

    func downloadMetalToolchain() {
        runCommand(
            label: "下载 Metal Toolchain",
            executable: "/usr/bin/xcodebuild",
            arguments: ["-downloadComponent", "MetalToolchain"],
            workingDirectory: repoPath
        )
    }

    func runSetup() {
        guard validateRepo() else { return }

        runCommand(
            label: "环境安装",
            executable: "/bin/bash",
            arguments: ["setup.sh"],
            workingDirectory: repoPath
        )
    }

    func installBundledBackendIfNeeded() {
        guard let bundledBackendURL else {
            presentError("应用包内未找到 Backend 资源。请重新下载 TrellisMac。")
            return
        }

        let manager = FileManager.default
        let setupPath = managedBackendURL.appendingPathComponent("setup.sh").path
        let generatePath = managedBackendURL.appendingPathComponent("generate.py").path
        let currentRepoIsValid = manager.fileExists(atPath: setupScriptPath) && manager.fileExists(atPath: generateScriptPath)
        let repoWasCustomized = defaults.object(forKey: Keys.repoPathCustomized) == nil
            ? (currentRepoIsValid && repoPath != managedBackendURL.path)
            : defaults.bool(forKey: Keys.repoPathCustomized)
        let outputWasCustomized = defaults.object(forKey: Keys.outputDirectoryPathCustomized) == nil
            ? (!outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && outputDirectoryPath != managedOutputURL.path
                && outputDirectoryPath != managedBackendURL.path)
            : defaults.bool(forKey: Keys.outputDirectoryPathCustomized)
        let shouldRefreshRepoPath =
            repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !currentRepoIsValid ||
            !repoWasCustomized ||
            repoPath == managedBackendURL.path
        let shouldRefreshOutputDirectory =
            outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (!outputWasCustomized && outputDirectoryPath != managedOutputURL.path)

        do {
            try manager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
            try manager.createDirectory(at: managedOutputURL, withIntermediateDirectories: true)
        } catch {
            presentError("无法准备应用数据目录: \(error.localizedDescription)")
            return
        }

        if manager.fileExists(atPath: setupPath), manager.fileExists(atPath: generatePath) {
            if shouldRefreshRepoPath {
                repoPath = managedBackendURL.path
            }
            if shouldRefreshOutputDirectory {
                outputDirectoryPath = managedOutputURL.path
            }
            appendLog("已使用现有托管 Backend: \(managedBackendURL.path)\n")
            return
        }

        do {
            let temporaryBackendURL = applicationSupportURL.appendingPathComponent("Backend.tmp", isDirectory: true)
            let bundledItems = ["setup.sh", "generate.py", "pyproject.toml", "LICENSE", "README.md", "backends", "patches", "assets"]
            if manager.fileExists(atPath: temporaryBackendURL.path) {
                try manager.removeItem(at: temporaryBackendURL)
            }
            try manager.copyItem(at: bundledBackendURL, to: temporaryBackendURL)
            try manager.createDirectory(at: managedBackendURL, withIntermediateDirectories: true)

            for item in bundledItems {
                let destinationURL = managedBackendURL.appendingPathComponent(item)
                if manager.fileExists(atPath: destinationURL.path) {
                    try manager.removeItem(at: destinationURL)
                }
                try manager.moveItem(
                    at: temporaryBackendURL.appendingPathComponent(item),
                    to: destinationURL
                )
            }
            try manager.removeItem(at: temporaryBackendURL)

            if shouldRefreshRepoPath {
                repoPath = managedBackendURL.path
            }
            if shouldRefreshOutputDirectory {
                outputDirectoryPath = managedOutputURL.path
            }
            appendLog("已安装托管 Backend: \(managedBackendURL.path)\n")
        } catch {
            presentError("无法安装应用内 Backend: \(error.localizedDescription)")
        }
    }

    func checkBackends() {
        guard validateRepo() else { return }
        guard FileManager.default.fileExists(atPath: generateScriptPath) else {
            presentError("未找到 `generate.py`，请确认 Repo 路径是否正确。")
            return
        }
        guard hasPythonEnvironment else {
            presentError("未检测到 `.venv/bin/python`，请先运行环境安装。")
            return
        }

        runCommand(
            label: "检查后端",
            executable: pythonExecutablePath,
            arguments: [generateScriptPath, "--check-backends"],
            workingDirectory: repoPath
        )
    }

    func runGeometryStage() {
        runGeneration()
    }

    func runTextureStage() {
        guard validateRepo() else { return }
        guard FileManager.default.fileExists(atPath: generateScriptPath) else {
            presentError("未找到 `generate.py`，请确认 Repo 路径是否正确。")
            return
        }
        guard hasPythonEnvironment else {
            presentError("未检测到 `.venv/bin/python`，请先运行环境安装。")
            return
        }
        guard FileManager.default.fileExists(atPath: outputDirectoryPath) else {
            presentError("输出目录不存在，请重新选择。")
            return
        }
        guard hasBakeState else {
            presentError("还没有可用于烘焙的中间文件。请先生成 OBJ 模型。")
            return
        }
        guard ["512", "1024", "2048"].contains(textureSize) else {
            presentError("纹理尺寸选项无效。")
            return
        }

        let cleanBakeTargetFaces = bakeTargetFaces.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "100000"
            : bakeTargetFaces.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bakeFaces = Int(cleanBakeTargetFaces), bakeFaces > 0 else {
            presentError("Bake 面数必须是大于 0 的整数。")
            return
        }
        if bakeFaces < 1000 {
            presentError("Bake 面数过小，建议至少为 1000。")
            return
        }

        let arguments = [
            generateScriptPath,
            "--stage", "texture",
            "--state", bakeStatePath,
            "--output", resolvedOutputName,
            "--texture-size", textureSize,
            "--bake-faces", cleanBakeTargetFaces
        ]

        runCommand(
            label: "生成贴图 GLB",
            executable: pythonExecutablePath,
            arguments: arguments,
            workingDirectory: outputDirectoryPath
        )
    }

    func runGeneration() {
        guard validateRepo() else { return }
        guard FileManager.default.fileExists(atPath: generateScriptPath) else {
            presentError("未找到 `generate.py`，请确认 Repo 路径是否正确。")
            return
        }
        guard hasPythonEnvironment else {
            presentError("未检测到 `.venv/bin/python`，请先运行环境安装。")
            return
        }
        guard FileManager.default.fileExists(atPath: inputImagePath) else {
            presentError("请先选择有效的输入图片。")
            return
        }
        guard FileManager.default.fileExists(atPath: outputDirectoryPath) else {
            presentError("输出目录不存在，请重新选择。")
            return
        }
        guard Int(seed) != nil else {
            presentError("随机种子必须是整数。")
            return
        }
        guard ["512", "1024", "1024_cascade"].contains(pipelineType) else {
            presentError("Pipeline 选项无效。")
            return
        }
        guard ["512", "1024", "2048"].contains(textureSize) else {
            presentError("纹理尺寸选项无效。")
            return
        }
        let cleanSimplifyTargetFaces = simplifyTargetFaces.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSimplifyTargetFaces.isEmpty {
            guard let targetFaces = Int(cleanSimplifyTargetFaces), targetFaces > 0 else {
                presentError("目标面数必须是大于 0 的整数，或留空。")
                return
            }
            if targetFaces < 1000 {
                presentError("目标面数过小，建议至少为 1000。")
                return
            }
        }

        let cleanOutputName = outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "output_3d"
            : outputName.trimmingCharacters(in: .whitespacesAndNewlines)

        var arguments = [
            generateScriptPath,
            inputImagePath,
            "--stage", "geometry",
            "--state", bakeStatePath,
            "--seed", seed,
            "--output", cleanOutputName,
            "--pipeline-type", pipelineType,
            "--texture-size", textureSize,
        ]

        if !cleanSimplifyTargetFaces.isEmpty {
            arguments += ["--simplify-target-faces", cleanSimplifyTargetFaces]
        }

        runCommand(
            label: "生成 OBJ 模型",
            executable: pythonExecutablePath,
            arguments: arguments,
            workingDirectory: outputDirectoryPath
        )
    }

    func stopCurrentTask() {
        autoRetryActive = false
        autoRetrySummary = ""
        pendingAutoSeeds = []
        guard let process, process.isRunning else { return }
        stopRequested = true
        appendLog("正在停止当前任务...\n")
        process.terminate()
    }

    func openOutputDirectory() {
        guard !outputDirectoryPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: outputDirectoryPath))
    }

    private func runCommand(label: String, executable: String, arguments: [String], workingDirectory: String) {
        guard !isBusy else {
            appendLog("已有任务正在运行，请先等待完成或点击“停止任务”。\n")
            return
        }

        let cwdURL = URL(fileURLWithPath: workingDirectory)
        guard FileManager.default.fileExists(atPath: cwdURL.path) else {
            presentError("工作目录不存在: \(cwdURL.path)")
            return
        }

        if autoRetryActive && !logs.isEmpty {
            appendLog("\n---- 自动尝试下一组 Seed ----\n")
        } else {
            logs = ""
        }
        isBusy = true
        stopRequested = false
        if !autoRetryActive {
            failureHint = ""
        }
        statusText = "\(label)中..."
        appendLog("== \(label) ==\n")
        appendLog("工作目录: \(workingDirectory)\n")
        appendLog("命令: \(displayCommand(executable: executable, arguments: arguments))\n\n")

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwdURL
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.appendLog(text)
                }
            }
        }

        process.terminationHandler = { [weak self] task in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                self?.process = nil
                self?.isBusy = false

                if task.terminationReason == .exit && task.terminationStatus == 0 {
                    if self?.autoRetryActive == true {
                        self?.autoRetryActive = false
                        self?.pendingAutoSeeds = []
                        self?.autoRetrySummary = "已在 Seed \(self?.seed ?? "") 找到通过检查的结果"
                        self?.failureHint = ""
                    }
                    self?.statusText = "\(label)完成"
                    self?.appendLog("\n== \(label)完成 ==\n")
                } else if task.terminationReason == .uncaughtSignal {
                    let signal = task.terminationStatus
                    let signalText = self?.signalDescription(signal) ?? "signal \(signal)"
                    let requested = self?.stopRequested == true
                    self?.autoRetryActive = false
                    self?.pendingAutoSeeds = []
                    self?.autoRetrySummary = ""
                    self?.statusText = requested ? "\(label)已停止" : "\(label)被外部中断"
                    self?.appendLog("\n== \(label)已停止: \(signalText), requested=\(requested) ==\n")
                    self?.stopRequested = false
                } else {
                    let failure = self?.describeFailure(label: label, exitCode: task.terminationStatus)
                    self?.statusText = failure?.statusText ?? "\(label)失败"
                    self?.failureHint = failure?.hint ?? ""
                    self?.appendLog("\n== \(label)失败，退出码 \(task.terminationStatus) ==\n")

                    if self?.autoRetryActive == true, task.terminationReason == .exit, task.terminationStatus == 3 {
                        if let nextSeed = self?.pendingAutoSeeds.first {
                            self?.autoRetrySummary = "当前 Seed \(self?.seed ?? "") 失败，准备继续尝试 \(nextSeed)"
                            self?.appendLog("自动尝试继续：准备切换到 Seed \(nextSeed)\n")
                            self?.runNextAutoSeedAttempt()
                        } else {
                            self?.autoRetryActive = false
                            self?.autoRetrySummary = "推荐 Seeds 已尝试完，仍未找到通过碎片检查的结果"
                            self?.appendLog("自动尝试结束：推荐 Seeds 已全部尝试。\n")
                        }
                    } else {
                        self?.autoRetryActive = false
                        self?.pendingAutoSeeds = []
                        if self?.autoRetrySummary.isEmpty == false {
                            self?.autoRetrySummary = ""
                        }
                    }
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            isBusy = false
            statusText = "\(label)启动失败"
            presentError("无法启动任务: \(error.localizedDescription)")
        }
    }

    private func signalDescription(_ signal: Int32) -> String {
        switch signal {
        case 2:
            return "SIGINT(2)"
        case 9:
            return "SIGKILL(9)"
        case 13:
            return "SIGPIPE(13)"
        case 15:
            return "SIGTERM(15)"
        default:
            return "signal \(signal)"
        }
    }

    private func runDetachedCommand(label: String, executable: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            presentError("\(label)失败: \(error.localizedDescription)")
        }
    }

    private func chooseDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func validateRepo() -> Bool {
        let setupExists = FileManager.default.fileExists(atPath: setupScriptPath)
        let generateExists = FileManager.default.fileExists(atPath: generateScriptPath)

        guard setupExists, generateExists else {
            presentError("当前 Repo 路径下未找到 `setup.sh` 和 `generate.py`。请在 app 顶部重新选择 trellis-mac 仓库目录。")
            return false
        }

        return true
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func appendLog(_ text: String) {
        logs += text
    }

    private func runNextAutoSeedAttempt() {
        guard autoRetryActive else { return }
        guard !pendingAutoSeeds.isEmpty else {
            autoRetryActive = false
            autoRetrySummary = "推荐 Seeds 已尝试完，仍未找到通过碎片检查的结果"
            return
        }

        let nextSeed = pendingAutoSeeds.removeFirst()
        seed = nextSeed
        autoRetrySummary = "正在自动尝试 Seed \(nextSeed)，剩余 \(pendingAutoSeeds.count) 个候选"
        appendLog("自动尝试 Seed: \(nextSeed)\n")
        runGeneration()
    }

    private func describeFailure(label: String, exitCode: Int32) -> (statusText: String, hint: String)? {
        if logs.contains("Error: generation produced a heavily fragmented mesh") {
            return (
                "\(label)失败: 生成阶段",
                "原始生成网格在进入 bake 前已经碎裂。建议切换高质量预设，保持目标面数留空，并尝试 7、123、256、512 这些 Seed。"
            )
        }

        if logs.contains("Error: Metal bake pre-simplification produced a heavily fragmented mesh") {
            return (
                "\(label)失败: Bake 预处理",
                "原始网格已生成，但用于 Metal bake 的简化网格在预处理阶段碎裂。建议先保留原始 OBJ，再重试其他 Seed。"
            )
        }

        if logs.contains("Error: KDTree bake mesh is heavily fragmented") {
            return (
                "\(label)失败: KDTree Bake",
                "KDTree 贴图路径使用的网格发生严重碎片化。优先确认 Metal 路径可用，或重试高质量预设。"
            )
        }

        if logs.contains("Error: generation produced an empty mesh") {
            return (
                "\(label)失败: 空网格",
                "这次生成没有解出有效几何体。建议换 Seed，或使用主体更清晰、背景更干净的输入图。"
            )
        }

        if exitCode == 3 {
            return (
                "\(label)失败: 网格碎片化",
                "本次输出在连通块检查中被判定为严重碎片化。可以继续重试推荐 Seed。"
            )
        }

        return nil
    }

    private func presentError(_ message: String) {
        statusText = "需要处理"
        appendLog("错误: \(message)\n")

        let alert = NSAlert()
        alert.messageText = "操作未完成"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func displayCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(shellQuoted).joined(separator: " ")
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func devRepoPathCandidates() -> [String] {
        let manager = FileManager.default
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent()
        return [
            bundleParent.deletingLastPathComponent().path,
            manager.currentDirectoryPath,
            NSHomeDirectory()
        ]
    }

    private static func defaultRepoPath() -> String {
        let manager = FileManager.default
        let managed = defaultManagedBackendPath()
        let candidates = [managed] + devRepoPathCandidates()

        for candidate in candidates {
            let setup = URL(fileURLWithPath: candidate).appendingPathComponent("setup.sh").path
            let generate = URL(fileURLWithPath: candidate).appendingPathComponent("generate.py").path
            if manager.fileExists(atPath: setup), manager.fileExists(atPath: generate) {
                return candidate
            }
        }

        return managed
    }

    private static func defaultOutputDirectoryPath() -> String {
        defaultManagedOutputPath()
    }

    private static func defaultManagedBackendPath() -> String {
        let manager = FileManager.default
        let supportBase = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return supportBase.appendingPathComponent("TrellisMac/Backend", isDirectory: true).path
    }

    private static func defaultManagedOutputPath() -> String {
        let manager = FileManager.default
        let supportBase = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return supportBase.appendingPathComponent("TrellisMac/Outputs", isDirectory: true).path
    }

    private enum Keys {
        static let repoPath = "repoPath"
        static let inputImagePath = "inputImagePath"
        static let outputDirectoryPath = "outputDirectoryPath"
        static let repoPathCustomized = "repoPathCustomized"
        static let outputDirectoryPathCustomized = "outputDirectoryPathCustomized"
        static let outputName = "outputName"
        static let seed = "seed"
        static let pipelineType = "pipelineType"
        static let textureSize = "textureSize"
        static let simplifyTargetFaces = "simplifyTargetFaces"
        static let bakeTargetFaces = "bakeTargetFaces"
        static let noTexture = "noTexture"
    }
}
