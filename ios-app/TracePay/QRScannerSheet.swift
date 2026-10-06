import SwiftUI
import AVFoundation
import UIKit
import PhotosUI
import Vision

struct UPIPayload {
    let payeeAddress: String
    let payeeName: String?
    let originalURL: URL
    init?(rawValue: String) {
        let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned), ["upi", "tracepay"].contains(url.scheme?.lowercased() ?? ""), url.host?.lowercased() == "pay",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let pa = components.queryItems?.first(where: { $0.name.lowercased() == "pa" })?.value,
              !pa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        payeeAddress = pa
        payeeName = components.queryItems?.first(where: { $0.name.lowercased() == "pn" })?.value
        originalURL = url
    }
}

struct QRScannerSheet: View {
    let onScan: (String) -> Void
    var onClose: (() -> Void)? = nil
    var onMyQR: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var cameraDenied = false
    @State private var scannerError: String?
    @State private var scanLineOffset: CGFloat = -112
    @State private var torchOn = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isReadingImage = false

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.075, blue: 0.17).ignoresSafeArea()
            CameraQRScanner(torchOn: $torchOn, onCode: { value in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onScan(value)
            }, onFailure: { message in scannerError = message }).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { if let onClose { onClose() } else { dismiss() } } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 42, height: 42).background(.ultraThinMaterial, in: Circle()) }.accessibilityLabel("Close scanner")
                    Spacer()
                    VStack(spacing: 3) { Text("Scan to pay").font(.system(size: 17, weight: .bold)).foregroundStyle(.white); Text("TRACE.PAY QR").font(.system(size: 9, weight: .heavy)).tracking(1.3).foregroundStyle(.white.opacity(0.64)) }
                    Spacer()
                    Button { torchOn.toggle(); UIImpactFeedbackGenerator(style: .light).impactOccurred() } label: { Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(torchOn ? TP.mint : .white).frame(width: 42, height: 42).background(.ultraThinMaterial, in: Circle()) }.accessibilityLabel(torchOn ? "Turn flashlight off" : "Turn flashlight on")
                }.padding(.horizontal, 20).padding(.top, 14)
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 28).stroke(LinearGradient(colors: [TP.mint, .white, TP.blue], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2).frame(width: 272, height: 272)
                    VStack { HStack { CornerMark().rotationEffect(.degrees(0)); Spacer(); CornerMark().rotationEffect(.degrees(90)) }; Spacer(); HStack { CornerMark().rotationEffect(.degrees(-90)); Spacer(); CornerMark().rotationEffect(.degrees(180)) } }.frame(width: 272, height: 272)
                    Capsule().fill(TP.blue).frame(width: 232, height: 2).shadow(color: TP.blue, radius: 9).offset(y: scanLineOffset).onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { scanLineOffset = 112 } }
                }
                Text("Fit the complete QR code inside the frame").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).padding(.top, 25)
                Text("Point at a Trace.Pay QR code to pay instantly.").font(.system(size: 11)).lineSpacing(3).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.68)).padding(.horizontal, 42).padding(.top, 7)
                Spacer()
                if cameraDenied {
                    VStack(spacing: 10) { Text("Camera access is off").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white); Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.buttonStyle(ScannerActionStyle()) }
                }
                if let scannerError { Text(scannerError).font(.system(size: 11)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 8) }
                if let onMyQR {
                    Button { onMyQR() } label: {
                        Label("Show my QR", systemImage: "qrcode").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10).background(Color.white.opacity(0.16), in: Capsule())
                    }.padding(.bottom, 10)
                }
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    HStack(spacing: 9) { if isReadingImage { ProgressView().tint(TP.ink) } else { Image(systemName: "photo.on.rectangle.angled") }; Text(isReadingImage ? "Reading QR image…" : "Import from photos") }.font(.system(size: 13, weight: .semibold)).foregroundStyle(TP.ink).frame(maxWidth: .infinity).frame(height: 52).background(.white, in: RoundedRectangle(cornerRadius: 17))
                }.disabled(isReadingImage).padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
        .task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
            cameraDenied = AVCaptureDevice.authorizationStatus(for: .video) != .authorized
        }
        .onChange(of: selectedPhoto) { _, item in if let item { Task { await readQRImage(item) } } }
    }

    private func readQRImage(_ item: PhotosPickerItem) async {
        isReadingImage = true
        defer { isReadingImage = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let cgImage = image.cgImage else { scannerError = "That image could not be opened. Choose another image."; return }
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            guard let raw = request.results?.compactMap({ $0.payloadStringValue }).first else { scannerError = "No QR code was found in that image."; UINotificationFeedbackGenerator().notificationOccurred(.error); return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onScan(raw)
        } catch { scannerError = "Could not read that image. Try another QR image." }
    }
}

struct CornerMark: View {
    var body: some View { ZStack(alignment: .topLeading) { Path { path in path.move(to: CGPoint(x: 0, y: 25)); path.addLine(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 25, y: 0)) }.stroke(TP.mint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)) }.frame(width: 26, height: 26) }
}

struct ScannerActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 11).background(.white.opacity(0.14), in: Capsule()).opacity(configuration.isPressed ? 0.7 : 1) }
}

private struct CameraQRScanner: UIViewControllerRepresentable {
    @Binding var torchOn: Bool
    let onCode: (String) -> Void
    let onFailure: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        controller.onFailure = onFailure
        return controller
    }
    func updateUIViewController(_ controller: ScannerController, context: Context) { controller.setTorch(torchOn) }
}

private final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var camera: AVCaptureDevice?
    private var didEmit = false
    private var configured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.055, green: 0.075, blue: 0.17, alpha: 1)
        guard let device = AVCaptureDevice.default(for: .video) else { onFailure?("This device does not have an available camera."); return }
        camera = device
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { onFailure?("Camera input is unavailable."); return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { onFailure?("QR scanning is unavailable."); return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            previewLayer = layer
            configured = true
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        } catch { onFailure?("Unable to start the camera: \(error.localizedDescription)") }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); previewLayer?.frame = view.bounds }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if session.isRunning { session.stopRunning() }; setTorch(false) }
    func setTorch(_ enabled: Bool) {
        guard let camera, camera.hasTorch else { return }
        do { try camera.lockForConfiguration(); camera.torchMode = enabled ? .on : .off; camera.unlockForConfiguration() }
        catch { onFailure?("The flashlight could not be changed.") }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didEmit, let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let value = object.stringValue else { return }
        didEmit = true
        if session.isRunning { session.stopRunning() }
        setTorch(false)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCode?(value)
    }
}


// MARK: - Live selfie with real-time face detection (camera only, no gallery)

struct FaceGuidance: Equatable { var ok: Bool; var text: String }

struct LiveSelfieView: View {
    let onCaptured: (Data) -> Void
    let onCancel: () -> Void
    @State private var guidance = FaceGuidance(ok: false, text: "Looking for your face…")
    @State private var captureTrigger = 0
    @State private var capturing = false
    @State private var cameraDenied = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !cameraDenied {
                FaceCameraView(captureTrigger: captureTrigger,
                               onGuidance: { g in if !capturing { guidance = g } },
                               onPhoto: { data in onCaptured(data) },
                               onFailure: { message in capturing = false; guidance = FaceGuidance(ok: false, text: message) })
                    .ignoresSafeArea()
                GeometryReader { geo in
                    let w = geo.size.width * 0.72
                    let h = w * 1.3
                    let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.42)
                    ZStack {
                        Color.black.opacity(0.5)
                            .mask(ZStack { Rectangle(); Ellipse().frame(width: w, height: h).position(centre).blendMode(.destinationOut) }.compositingGroup())
                        Ellipse().stroke(guidance.ok ? TP.lime : Color.white.opacity(0.85), lineWidth: 6)
                            .frame(width: w, height: h)
                            .scaleEffect(guidance.ok ? 1 : (pulse ? 1.03 : 0.97))
                            .position(centre)
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                            .animation(.easeOut(duration: 0.2), value: guidance.ok)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.system(size: 36)).foregroundStyle(.white)
                    Text("Camera access is off").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    Text("Allow the camera to take your live selfie.").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.7))
                    Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(TP.ink).padding(.horizontal, 20).padding(.vertical, 12).background(TP.lime, in: Capsule())
                }
            }
            VStack {
                HStack {
                    Button { onCancel() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 42, height: 42).background(Color.black.opacity(0.4), in: Circle())
                    }
                    .accessibilityLabel("Cancel")
                    Spacer()
                    Text("Live selfie").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 42, height: 42)
                }
                .padding(.horizontal, 20).padding(.top, 12)
                Spacer()
                Text(capturing ? "Capturing…" : guidance.text)
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(guidance.ok ? TP.ink : Color.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(guidance.ok ? TP.lime : Color.black.opacity(0.5), in: Capsule())
                    .animation(.easeOut(duration: 0.2), value: guidance)
                Button { take() } label: {
                    Circle().fill(guidance.ok ? Color.white : Color.white.opacity(0.3)).frame(width: 64, height: 64)
                        .padding(7).overlay(Circle().stroke(guidance.ok ? TP.lime : Color.white.opacity(0.5), lineWidth: 5))
                }
                .disabled(!guidance.ok || capturing)
                .accessibilityLabel("Take selfie")
                .padding(.top, 14)
                Text("No gallery uploads: the photo must be live.").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.7)).padding(.top, 10).padding(.bottom, 24)
            }
        }
        .onAppear { pulse = true }
        .task {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
            cameraDenied = AVCaptureDevice.authorizationStatus(for: .video) != .authorized
        }
        .onChange(of: guidance.ok) { _, ok in
            guard ok, !capturing else { return }
            // Auto-capture once the face has stayed well framed for a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { if guidance.ok && !capturing { take() } }
        }
    }

    private func take() {
        guard !capturing else { return }
        capturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        captureTrigger += 1
    }
}

struct FaceCameraView: UIViewControllerRepresentable {
    let captureTrigger: Int
    let onGuidance: (FaceGuidance) -> Void
    let onPhoto: (Data) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> FaceCameraController {
        let controller = FaceCameraController()
        controller.onGuidance = onGuidance; controller.onPhoto = onPhoto; controller.onFailure = onFailure
        return controller
    }
    func updateUIViewController(_ controller: FaceCameraController, context: Context) {
        controller.onGuidance = onGuidance; controller.onPhoto = onPhoto; controller.onFailure = onFailure
        if captureTrigger != controller.lastTrigger { controller.lastTrigger = captureTrigger; controller.capture() }
    }
}

final class FaceCameraController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    var onGuidance: ((FaceGuidance) -> Void)?
    var onPhoto: ((Data) -> Void)?
    var onFailure: ((String) -> Void)?
    var lastTrigger = 0
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "tech.tracepay.face")
    private var preview: AVCaptureVideoPreviewLayer?
    private var lastAnalysis = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            onFailure?("The front camera is not available."); return
        }
        do {
            session.beginConfiguration()
            session.sessionPreset = .photo
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
                session.commitConfiguration(); onFailure?("The camera could not start."); return
            }
            session.addInput(input)
            session.addOutput(photoOutput)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
            session.commitConfiguration()
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            preview = layer
            queue.async { self.session.startRunning() }
        } catch {
            onFailure?("The camera could not start: \(error.localizedDescription)")
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(lastAnalysis) > 0.15, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = Date()
        let request = VNDetectFaceRectanglesRequest()
        do { try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .leftMirrored).perform([request]) } catch { return }
        let guidance = Self.check(request.results ?? [])
        DispatchQueue.main.async { self.onGuidance?(guidance) }
    }

    static func check(_ faces: [VNFaceObservation]) -> FaceGuidance {
        guard !faces.isEmpty else { return FaceGuidance(ok: false, text: "Looking for your face…") }
        guard faces.count == 1, let face = faces.first else { return FaceGuidance(ok: false, text: "Only one face, please") }
        let width = face.boundingBox.width
        if width < 0.32 { return FaceGuidance(ok: false, text: "Move a little closer") }
        if width > 0.85 { return FaceGuidance(ok: false, text: "Move a little further away") }
        if let yaw = face.yaw?.doubleValue, abs(yaw) > 0.32 { return FaceGuidance(ok: false, text: "Look straight at the camera") }
        return FaceGuidance(ok: true, text: "Perfect, hold still")
    }

    func capture() {
        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data), let jpeg = Self.normalized(image) else {
            DispatchQueue.main.async { self.onFailure?("Could not take the photo. Try again.") }
            return
        }
        DispatchQueue.main.async { self.onPhoto?(jpeg) }
    }

    /// Upright, mirrored like the preview, at most 1280 px, JPEG 88%.
    static func normalized(_ image: UIImage) -> Data? {
        let scale = min(1, 1280 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let upright = UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.translateBy(x: size.width, y: 0)
            context.cgContext.scaleBy(x: -1, y: 1)
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return upright.jpegData(compressionQuality: 0.88)
    }
}
