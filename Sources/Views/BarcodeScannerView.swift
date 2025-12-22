import SwiftUI
import AVFoundation

struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var scannedCode: String?
    @State private var isScanning = true

    var body: some View {
        ZStack {
            CameraPreview(scannedCode: $scannedCode, isScanning: $isScanning)
                .ignoresSafeArea()

            VStack {
                Spacer()

                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white, lineWidth: 3)
                    .frame(width: 280, height: 150)
                    .background(.clear)

                Text("Point at a book's barcode")
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                    .shadow(radius: 2)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(.white)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 40)
            }
        }
        .onChange(of: scannedCode) { _, newValue in
            if newValue != nil {
                dismiss()
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    @Binding var scannedCode: String?
    @Binding var isScanning: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let captureSession = AVCaptureSession()
        context.coordinator.captureSession = captureSession

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession.canAddInput(videoInput) else {
            return view
        }

        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: .main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce]
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = UIScreen.main.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(scannedCode: $scannedCode, isScanning: $isScanning)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        @Binding var scannedCode: String?
        @Binding var isScanning: Bool
        var captureSession: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?

        init(scannedCode: Binding<String?>, isScanning: Binding<Bool>) {
            _scannedCode = scannedCode
            _isScanning = isScanning
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard isScanning,
                  let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = metadataObject.stringValue else {
                return
            }

            isScanning = false
            captureSession?.stopRunning()

            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            scannedCode = code
        }
    }
}
