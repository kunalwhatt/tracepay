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
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 42, height: 42).background(.ultraThinMaterial, in: Circle()) }.accessibilityLabel("Close scanner")
                    Spacer()
                    VStack(spacing: 3) { Text("Scan a QR").font(.system(size: 17, weight: .bold)).foregroundStyle(.white); Text("TRACE.PAY & UPI QR").font(.system(size: 9, weight: .heavy)).tracking(1.3).foregroundStyle(.white.opacity(0.64)) }
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
                Text("Trace.Pay QR codes identify registered accounts. External UPI QR codes can be read, but bank payment rails are not connected.").font(.system(size: 11)).lineSpacing(3).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.68)).padding(.horizontal, 42).padding(.top, 7)
                Spacer()
                if cameraDenied {
                    VStack(spacing: 10) { Text("Camera access is off").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white); Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.buttonStyle(ScannerActionStyle()) }
                }
                if let scannerError { Text(scannerError).font(.system(size: 11)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 8) }
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    HStack(spacing: 9) { if isReadingImage { ProgressView().tint(TP.ink) } else { Image(systemName: "photo.on.rectangle.angled") }; Text(isReadingImage ? "Reading QR image…" : "Choose QR from Photos") }.font(.system(size: 13, weight: .semibold)).foregroundStyle(TP.ink).frame(maxWidth: .infinity).frame(height: 52).background(.white, in: RoundedRectangle(cornerRadius: 17))
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
