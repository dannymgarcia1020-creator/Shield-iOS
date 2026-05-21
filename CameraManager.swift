import SwiftUI
import AVFoundation
internal import Combine

class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    @Published var session = AVCaptureSession()
    @Published var isRecordingVideo = false
    
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureMovieFileOutput()
    
    var onCaptureCompletion: ((Data, URL?, Bool) -> Void)?
    private var videoRecordingURL: URL?
    
    override init() {
        super.init()
        checkPermissionsAndSetup()
    }
    
    private func checkPermissionsAndSetup() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        if status == .authorized && audioStatus == .authorized {
            setupSession()
        } else {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                    if granted && audioGranted {
                        DispatchQueue.main.async { self.setupSession() }
                    }
                }
            }
        }
    }
    
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .high
        
        // 1. Core Hardware Camera Component
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let cameraInput = try? AVCaptureDeviceInput(device: camera) else { return }
        if session.canAddInput(cameraInput) { session.addInput(cameraInput) }
        
        // 2. Core Hardware Microphone Component
        guard let microphone = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: microphone) else { return }
        if session.canAddInput(audioInput) { session.addInput(audioInput) }
        
        // 3. Dual Route Outputs
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
    
    func capturePhoto(completion: @escaping (Data, URL?, Bool) -> Void) {
        self.onCaptureCompletion = completion
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func toggleVideoRecording(completion: @escaping (Data, URL?, Bool) -> Void) {
        self.onCaptureCompletion = completion
        
        if videoOutput.isRecording {
            videoOutput.stopRecording()
        } else {
            let tempDir = NSTemporaryDirectory()
            let videoName = "Shield_Rec_\(UUID().uuidString).mp4"
            let outputURL = URL(fileURLWithPath: tempDir).appendingPathComponent(videoName)
            self.videoRecordingURL = outputURL
            
            videoOutput.startRecording(to: outputURL, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecordingVideo = true }
        }
    }
    
    // ===== AVFOUNDATION PHOTO COMPLETE ROUTINE =====
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let fileData = photo.fileDataRepresentation() else { return }
        DispatchQueue.main.async {
            self.onCaptureCompletion?(fileData, nil, false)
        }
    }
    
    // ===== AVFOUNDATION VIDEO COMPLETE ROUTINE =====
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { self.isRecordingVideo = true }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { self.isRecordingVideo = false }
        
        guard let videoData = try? Data(contentsOf: outputFileURL) else { return }
        
        // Generate a localized video file placeholder frame snapshot asset instantly
        let asset = AVAsset(url: outputFileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        let timestamp = CMTime(seconds: 1, preferredTimescale: 60)
        if let cgImage = try? generator.copyCGImage(at: timestamp, actualTime: nil) {
            let thumbnail = UIImage(cgImage: cgImage)
            if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) {
                DispatchQueue.main.async {
                    self.onCaptureCompletion?(thumbnailData, outputFileURL, true)
                }
                return
            }
        }
        
        // Safe standard systemic fallback frame if image compiler loop bounds drop
        let blankImage = UIImage(systemName: "video.circle.fill")?.jpegData(compressionQuality: 0.5) ?? Data()
        DispatchQueue.main.async {
            self.onCaptureCompletion?(blankImage, outputFileURL, true)
        }
    }
}
