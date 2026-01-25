import SwiftUI
import AVFoundation

struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bookStore: BookStore
    @Binding var scannedCode: String?
    var quickScanMode: Bool = false

    @State private var isScanning = true
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined
    @State private var localScannedCode: String?
    @State private var scannedBooks: [String] = []
    @State private var isLookingUp = false
    @State private var lastScannedTitle: String?

    var body: some View {
        ZStack {
            if cameraPermission == .authorized {
                CameraPreview(scannedCode: $localScannedCode, isScanning: $isScanning)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 280, height: 150)
                        .background(.clear)

                    if quickScanMode {
                        if isLookingUp {
                            Text("Looking up...")
                                .foregroundStyle(.yellow)
                                .padding(.top, 20)
                                .shadow(radius: 2)
                        } else if let title = lastScannedTitle {
                            Text("Added: \(title)")
                                .foregroundStyle(.green)
                                .padding(.top, 20)
                                .shadow(radius: 2)
                                .lineLimit(1)
                        } else {
                            Text("Quick Scan - Point at barcodes")
                                .foregroundStyle(.white)
                                .padding(.top, 20)
                                .shadow(radius: 2)
                        }

                        Text("\(scannedBooks.count) books scanned")
                            .foregroundStyle(.white.opacity(0.8))
                            .font(.caption)
                            .padding(.top, 4)
                    } else {
                        Text("Point at a book's barcode")
                            .foregroundStyle(.white)
                            .padding(.top, 20)
                            .shadow(radius: 2)
                    }

                    Spacer()

                    Button(quickScanMode ? "Done (\(scannedBooks.count) books)" : "Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    Text("Camera Access Required")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Please allow camera access in Settings to scan barcodes")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .task {
            await checkCameraPermission()
        }
        .onChange(of: localScannedCode) { _, newValue in
            if let code = newValue {
                if quickScanMode {
                    // Quick scan mode - add directly and continue scanning
                    guard !scannedBooks.contains(code) else {
                        // Already scanned this one, reset and continue
                        localScannedCode = nil
                        isScanning = true
                        return
                    }
                    scannedBooks.append(code)
                    Task {
                        await quickAddBook(isbn: code)
                        localScannedCode = nil
                        isScanning = true
                    }
                } else {
                    // Normal mode - pass code back and dismiss
                    scannedCode = code
                    dismiss()
                }
            }
        }
    }

    private func checkCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermission = status

        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraPermission = granted ? .authorized : .denied
        }
    }

    private func quickAddBook(isbn: String) async {
        isLookingUp = true
        lastScannedTitle = nil

        var book = Book(isbn: isbn)
        book.addedBy = bookStore.userName

        // Try to lookup book info
        if let foundBook = try? await OpenLibraryService.shared.lookupBook(isbn: isbn) {
            book.title = foundBook.title
            book.authors = foundBook.authors
            book.publisher = foundBook.publisher
            book.publishDate = foundBook.publishDate
            book.numberOfPages = foundBook.numberOfPages
            book.coverURL = foundBook.coverURL
            lastScannedTitle = foundBook.title
        } else {
            lastScannedTitle = "ISBN: \(isbn)"
        }

        // Add to database
        _ = await bookStore.addBook(book)

        isLookingUp = false
    }
}

struct CameraPreview: UIViewRepresentable {
    @Binding var scannedCode: String?
    @Binding var isScanning: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black

        DispatchQueue.main.async {
            self.setupCamera(in: view, context: context)
        }

        return view
    }

    private func setupCamera(in view: UIView, context: Context) {
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        context.coordinator.captureSession = captureSession

        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("No camera available")
            return
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            print("Could not create video input")
            return
        }

        guard captureSession.canAddInput(videoInput) else {
            print("Could not add video input")
            return
        }

        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            print("Could not add metadata output")
            return
        }

        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce]

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
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
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

            // Set the code after a tiny delay to let UI update
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.scannedCode = code
            }
        }
    }
}
