import SwiftUI
import AVFoundation
import UIKit
import Vision

// MARK: - Live selfie camera with on-device face detection (kept from 5.x)

struct FaceGuidance: Equatable { var ok: Bool; var text: String }

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
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90   // portrait
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
