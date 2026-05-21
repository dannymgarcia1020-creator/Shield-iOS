import SwiftUI
import AVFoundation

struct CameraCaptureStage: View {
    @ObservedObject var cameraManager: CameraManager
    var onAssetCaptured: (Data, URL?, Bool) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            CameraPreviewRepresentable(session: cameraManager.session)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.system(.body, design: .rounded)).bold()
                        .padding().background(Color.black.opacity(0.5)).foregroundColor(.white).cornerRadius(8)
                    Spacer()
                }.padding()
                Spacer()
                
                // CONTROL ZONE BAR
                HStack(spacing: 40) {
                    // LEFT: STILL PHOTO SNAP
                    Button(action: {
                        cameraManager.capturePhoto { data, url, isVideo in
                            onAssetCaptured(data, url, isVideo)
                            dismiss()
                        }
                    }) {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                            .shadow(radius: 8)
                    }
                    .disabled(cameraManager.isRecordingVideo)
                    .opacity(cameraManager.isRecordingVideo ? 0.3 : 1.0)
                    
                    // RIGHT: VIDEO STREAM LOOP SHUTTER
                    Button(action: {
                        cameraManager.toggleVideoRecording { data, url, isVideo in
                            onAssetCaptured(data, url, isVideo)
                            dismiss()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(cameraManager.isRecordingVideo ? Color.red : Color.white)
                                .frame(width: 65, height: 65)
                            Circle()
                                .stroke(Color.black, lineWidth: 3)
                                .frame(width: 65, height: 65)
                            if cameraManager.isRecordingVideo {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                            } else {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .shadow(radius: 12)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.frame = view.frame
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
