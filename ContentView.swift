import SwiftUI
import PhotosUI
import CryptoKit
import ImageIO
import AVFoundation
import SwiftData 
internal import Combine

// ===== GLOBAL CORE ENUMS =====

enum AppSkin: String, CaseIterable, Identifiable {
    case secureLog = "Shield Secure Log"
    case optimizer = "Exif Margin Studio"
    var id: String { self.rawValue }
}

enum CamouflageTarget: String, CaseIterable, Identifiable {
    case calendar = "System Calendar"
    case stocks = "System Stocks"
    case calculator = "Utility Calculator"
    
    var id: String { self.rawValue }
    
    var urlScheme: String {
        switch self {
        case .calendar: return "calshow://"
        case .stocks: return "stocks://"
        case .calculator: return "connectivity-utility://"
        }
    }
}

// ===== GLOBAL UTILITY HELPERS =====

func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// ===== GLOBAL CORE TYPES =====

struct AlertConfig: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let primaryButton: String
    var secondaryButton: String? = nil
    var primaryAction: () -> Void = {}
    var secondaryAction: (() -> Void)? = nil
}

enum VaultError: LocalizedError {
    case loadFailed(String)
    case saveFailed(String)
    case deleteFailed(String)
    case invalidImage
    case insufficientStorage
    case noAssetsToExport
    case missingRequiredFields
    case pdfGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let msg): return "Load Failed: \(msg)"
        case .saveFailed(let msg): return "Save Failed: \(msg)"
        case .deleteFailed(let msg): return "Delete Failed: \(msg)"
        case .invalidImage: return "Invalid Image Data"
        case .insufficientStorage: return "Insufficient Storage Available"
        case .noAssetsToExport: return "No Assets Found in Vault to Export"
        case .missingRequiredFields: return "Missing Required Context Fields"
        case .pdfGenerationFailed: return "Failed to Compile Certified PDF Document"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .insufficientStorage: return "Please free up disk space on your iOS device."
        case .missingRequiredFields: return "Please specify a location or supply chronology notes before generation."
        case .noAssetsToExport: return "Capture or import evidence assets before generating a report."
        default: return "Please try your action again or restart the application."
        }
    }
}

@MainActor
class PersistenceController: ObservableObject {
    static let shared = PersistenceController()
    
    let container: ModelContainer
    let context: ModelContext
    
    private init() {
        do {
            let schema = Schema([EvidenceAsset.self, GeneratedReport.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.container = try ModelContainer(for: schema, configurations: [config])
            self.context = container.mainContext
            self.context.autosaveEnabled = true
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error.localizedDescription)")
        }
    }
    
    func cleanupTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        if let urls = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
    
    func fetchAssets() throws -> [EvidenceAsset] {
        let descriptor = FetchDescriptor<EvidenceAsset>(sortBy: [SortDescriptor(\.dateSaved, order: .reverse)])
        return try context.fetch(descriptor)
    }
    
    func fetchReports() throws -> [GeneratedReport] {
        let descriptor = FetchDescriptor<GeneratedReport>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return try context.fetch(descriptor)
    }
    
    func saveAsset(_ asset: EvidenceAsset) throws {
        context.insert(asset)
        try context.save()
        objectWillChange.send()
    }
    
    func deleteAsset(_ asset: EvidenceAsset) throws {
        if let fileURL = asset.localURL { try? FileManager.default.removeItem(at: fileURL) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let thumbURL = docs.appendingPathComponent(asset.relativeThumbPath)
        try? FileManager.default.removeItem(at: thumbURL)
        
        context.delete(asset)
        try context.save()
        objectWillChange.send()
    }
    
    func saveReport(_ report: GeneratedReport) throws {
        context.insert(report)
        try context.save()
        objectWillChange.send()
    }
}

// ===== REAL CRYPTOGRAPHIC & EXIF STORAGE ENGINE =====

extension FileManager {
    static func hasEnoughStorage() -> Bool {
        let path = NSHomeDirectory() as NSString
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path as String),
              let freeSpace = attributes[.systemFreeSize] as? Int64 else { return false }
        return freeSpace > (50 * 1024 * 1024)
    }
    
    static func saveImageSecurely(_ image: UIImage, isVideo: Bool) throws -> (fileURL: URL, thumbnailURL: URL, hash: String, size: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw VaultError.invalidImage
        }
        
        let digest = SHA256.hash(data: data)
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
        
        let fileUUID = UUID().uuidString
        let filename = "SECURE_\(fileUUID).jpg"
        let thumbName = "THUMB_\(fileUUID).jpg"
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent(filename)
        let thumbURL = docs.appendingPathComponent(thumbName)
        
        try data.write(to: fileURL, options: .atomic)
        
        let thumbSize = CGSize(width: 160, height: 160)
        UIGraphicsBeginImageContextWithOptions(thumbSize, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: thumbSize))
        let thumbnailImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        if let thumbData = thumbnailImage?.jpegData(compressionQuality: 0.7) {
            try thumbData.write(to: thumbURL, options: .atomic)
        }
        
        let sizeMetric = String(format: "%.2f MB", Double(data.count) / (1024.0 * 1024.0))
        return (fileURL, thumbURL, hashString, sizeMetric)
    }
    
    static func saveVideoSecurely(from url: URL) throws -> (fileURL: URL, thumbnailURL: URL, hash: String, size: String) {
        let videoData = try Data(contentsOf: url)
        
        let digest = SHA256.hash(data: videoData)
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
        
        let fileUUID = UUID().uuidString
        let filename = "SECURE_\(fileUUID).mp4"
        let thumbName = "THUMB_\(fileUUID).jpg"
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent(filename)
        let thumbURL = docs.appendingPathComponent(thumbName)
        
        // FIXED: Now correctly writing raw data to the clean target storage URL
        try videoData.write(to: fileURL, options: .atomic)
        
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.0, preferredTimescale: 600)
        
        if let imageRef = try? generator.copyCGImage(at: time, actualTime: nil) {
            let thumbData = UIImage(cgImage: imageRef).jpegData(compressionQuality: 0.6)
            try? thumbData?.write(to: thumbURL, options: .atomic)
        }
        
        let sizeMetric = String(format: "%.2f MB", Double(videoData.count) / (1024.0 * 1024.0))
        return (fileURL, thumbURL, hashString, sizeMetric)
    }
    
    static func extractEXIFData(from data: Data) -> (deviceModel: String, dateTaken: String) {
        let fallbackDate = Date().formatted(date: .abbreviated, time: .shortened)
        let fallbackModel = "iPhone Hardware Profile"
        
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (fallbackModel, fallbackDate)
        }
        
        let tiffModel = (metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String
        let currentModel = tiffModel ?? fallbackModel
        
        if let exifDict = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let originalDateTime = exifDict[kCGImagePropertyExifDateTimeOriginal] as? String {
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            if let parsedDate = formatter.date(from: originalDateTime) {
                return (currentModel, parsedDate.formatted(date: .abbreviated, time: .shortened))
            }
            return (currentModel, originalDateTime)
        }
        
        return (currentModel, fallbackDate)
    }
}

// ===== ISOLATED FORM VIEW =====
struct IncidentFormView: View {
    @Binding var peopleInvolved: String
    @Binding var incidentLocation: String
    @Binding var incidentNotes: String
    var onGenerateReport: () -> Void
    
    var body: some View {
        Section(header: Text("Incident Tracking Profile")
            .font(.system(.caption, design: .rounded))
            .bold()
            .accessibilityAddTraits(.isHeader)) {
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("WHO WAS PRESENT / INVOLVED?")
                        .font(.system(.caption2, design: .rounded))
                        .bold()
                        .foregroundColor(.secondary)
                        .accessibilityLabel("People involved field")
                    
                    TextField("Names, witnesses, identifiers...", text: $peopleInvolved)
                        .font(.system(.body, design: .rounded))
                        .accessibilityLabel("People involved")
                        .accessibilityHint("Enter names of people present")
                }
                .padding(.vertical, 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("SPECIFIC LOCATION CONTEXT")
                        .font(.system(.caption2, design: .rounded))
                        .bold()
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Location field")
                    
                    TextField("e.g., Living room entryway", text: $incidentLocation)
                        .font(.system(.body, design: .rounded))
                        .accessibilityLabel("Incident location")
                        .accessibilityHint("Enter specific location details")
                }
                .padding(.vertical, 2)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("WHAT OCCURRED? (CHRONOLOGY NOTES)")
                        .font(.system(.caption2, design: .rounded))
                        .bold()
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Incident notes field")
                    
                    TextEditor(text: $incidentNotes)
                        .frame(minHeight: 110)
                        .accessibilityLabel("Incident chronology notes")
                        .accessibilityHint("Describe what occurred in detail")
                }
            }
        
        Section {
            Button(action: onGenerateReport) {
                HStack {
                    Spacer()
                    Label("Generate Certified Case Package", systemImage: "folder.badge.plus")
                        .font(.system(.body, design: .rounded))
                        .bold()
                        .foregroundColor(.white)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Generate report button")
            .accessibilityHint("Creates PDF report with all evidence")
            .listRowBackground(Color.blue)
        }
    }
}

// ===== MAIN VIEW =====
struct ContentView: View {
    @StateObject private var persistence = PersistenceController.shared
    @State private var selectedSkin: AppSkin = .secureLog
    @State private var selectedItems: [PhotosPickerItem] = []
    
    @State private var evidenceVault: [EvidenceAsset] = []
    @State private var selectedAsset: EvidenceAsset? = nil
    @State private var certifiedReportsHistory: [GeneratedReport] = []
    
    @State private var peopleInvolved: String = ""
    @State private var incidentLocation: String = ""
    @State private var incidentNotes: String = ""
    @State private var selectedEscapeApp: CamouflageTarget = .calendar
    
    @State private var isLoading = false
    @State private var loadingMessage = ""
    
    @State private var alertConfig: AlertConfig?
    @State private var showAlert = false
    
    @State private var shareSheetItems: [Any] = []
    @State private var showShareSheet = false
    
    @StateObject private var cameraManager = CameraManager()
    @State private var showLiveCamera = false
    
    var canvasBackground: Color {
        selectedSkin == .secureLog ? Color(red: 0.05, green: 0.06, blue: 0.09) : Color(.systemGroupedBackground)
    }
    
    var listRowBackground: Color {
        selectedSkin == .secureLog ? Color(red: 0.11, green: 0.14, blue: 0.19).opacity(0.4) : Color(.secondarySystemGroupedBackground)
    }
    
    var body: some View {
        TabView {
            vaultTab
            historyTab
        }
        .preferredColorScheme(selectedSkin == .secureLog ? .dark : .light)
        .overlay(loadingOverlay)
        .alert(alertConfig?.title ?? "Alert", isPresented: $showAlert, presenting: alertConfig) { config in
            if let secondaryButton = config.secondaryButton {
                Button(secondaryButton, role: .cancel, action: config.secondaryAction ?? {})
                Button(config.primaryButton, action: config.primaryAction)
            } else {
                Button(config.primaryButton, action: config.primaryAction)
            }
        } message: { config in
            Text(config.message)
        }
        .onAppear {
            loadPersistedData()
            persistence.cleanupTempFiles()
        }
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if isLoading {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text(loadingMessage)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(30)
                .background(Color(red: 0.11, green: 0.14, blue: 0.19))
                .cornerRadius(16)
            }
        }
    }
    
    private var vaultTab: some View {
        NavigationView {
            ZStack {
                canvasBackground.ignoresSafeArea()
                
                if selectedSkin == .secureLog {
                    RadialGradient(colors: [Color.blue.opacity(0.18), Color.clear], center: .topTrailing, startRadius: 5, endRadius: 480)
                        .ignoresSafeArea()
                }
                
                List {
                    Section {
                        onboardingHeaderCard
                    }
                    .listRowBackground(listRowBackground)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    
                    Section(header: Text(selectedSkin == .secureLog ? "Secure Sandbox Assets" : "Geometry Elements")
                        .font(.system(.caption, design: .rounded))
                        .bold()
                        .accessibilityAddTraits(.isHeader)) {
                            mediaCarouselRow
                            captureControlsRow
                        }
                        .listRowBackground(listRowBackground)
                    
                    if selectedSkin == .secureLog {
                        IncidentFormView(
                            peopleInvolved: $peopleInvolved,
                            incidentLocation: $incidentLocation,
                            incidentNotes: $incidentNotes,
                            onGenerateReport: {
                                dismissKeyboard()
                                
                                if cameraManager.session.isRunning {
                                    cameraManager.session.stopRunning()
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    validateAndGenerateReport()
                                }
                            }
                        )
                        .listRowBackground(listRowBackground)
                    }
                    
                    Section(header: Text(selectedSkin == .secureLog ? "Cryptographic Verification Ledger" : "Asset Specifications")
                        .font(.system(.caption, design: .rounded))
                        .bold()
                        .accessibilityAddTraits(.isHeader)) {
                            if let asset = selectedAsset {
                                ledgerContent(for: asset)
                            } else {
                                Text("Select an asset thumbnail from the gallery carousel above to load its cryptographic validation data.")
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .accessibilityLabel("No asset selected")
                            }
                        }
                        .listRowBackground(listRowBackground)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        dismissKeyboard()
                    }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(selectedSkin == .secureLog ? "Shield Vault" : "Optimizer")
                        .font(.system(.headline, design: .rounded))
                        .bold()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    toolbarControlsMenu
                }
            }
            .sheet(isPresented: $showLiveCamera, onDismiss: {
                DispatchQueue.global(qos: .userInitiated).async {
                    if !self.cameraManager.session.isRunning {
                        self.cameraManager.session.startRunning()
                    }
                }
            }) {
                CameraCaptureStage(cameraManager: cameraManager) { data, url, isVideo in
                    handleCapturedMedia(data: data, url: url, isVideo: isVideo)
                }
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            DispatchQueue.global(qos: .userInitiated).async {
                if !self.cameraManager.session.isRunning {
                    self.cameraManager.session.startRunning()
                }
            }
        }) {
            ShareActivityView(activityItems: shareSheetItems)
        }
        .tabItem {
            Label("Vault", systemImage: "lock.shield.fill")
        }
        .accessibilityLabel("Vault tab")
    }
    
    private var historyTab: some View {
        NavigationView {
            ZStack {
                canvasBackground.ignoresSafeArea()
                
                List {
                    if certifiedReportsHistory.isEmpty {
                        Section {
                            emptyHistoryView
                        }
                        .listRowBackground(listRowBackground)
                    } else {
                        Section(header: Text("Certified Property Packages")
                            .font(.system(.caption, design: .rounded))
                            .bold()
                            .accessibilityAddTraits(.isHeader)) {
                                ForEach(certifiedReportsHistory) { report in
                                    reportRow(for: report)
                                }
                            }
                            .listRowBackground(listRowBackground)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("History")
        }
        .tabItem {
            Label("History", systemImage: "clock.arrow.circlepath")
        }
        .accessibilityLabel("History tab")
    }
    
    // MARK: - Subviews
    
    private var onboardingHeaderCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if selectedSkin == .secureLog {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text("Shield Secure Storage Active")
                        .font(.system(.caption, design: .rounded))
                        .bold()
                        .foregroundColor(.green)
                }
                .accessibilityElement(children: .combine)
                
                Text("Photos and recordings are encrypted and stored securely within your device. Data never syncs to cloud services.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
            } else {
                Text("Exif Layout Optimization Studio:")
                    .font(.system(.caption, design: .rounded))
                    .bold()
                    .foregroundColor(.secondary)
                Text("Configure local bounding variables across fluid vector margins.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var mediaCarouselRow: some View {
        Group {
            if !evidenceVault.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        forIn()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
                .frame(height: 92)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Evidence gallery with \(evidenceVault.count) items")
            } else {
                emptyGalleryView
            }
        }
    }
    
    @ViewBuilder
    private func forIn() -> some View {
        ForEach(evidenceVault) { asset in
            assetThumbnail(for: asset)
        }
    }
    
    private func assetThumbnail(for asset: EvidenceAsset) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomTrailing) {
                Image(uiImage: asset.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(asset.isVideo ? "Video evidence" : "Photo evidence")
                
                if asset.isVideo {
                    Image(systemName: "video.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .padding(4)
                        .accessibilityHidden(true)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selectedAsset == asset ? Color.blue : Color.clear, lineWidth: 3))
            .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 2)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedAsset = asset
                UIAccessibility.post(notification: .announcement, argument: "Asset selected")
            }
            
            Button(action: { confirmDelete(asset: asset) }) { // <-- RESTORED: Standard safety prompt call
                Image(systemName: "minus.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .background(Color.white.clipShape(Circle()))
                    .offset(x: 5, y: -5)
            }
            .accessibilityLabel("Delete asset")
            .accessibilityHint("Double tap to delete this evidence item")
        }
        .padding(.top, 4)
    }
    
    private var emptyGalleryView: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                Text(selectedSkin == .secureLog ? "No Media Objects Cached" : "Empty Canvas Array")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
        }
        .padding(.vertical, 10)
    }
    
    private var captureControlsRow: some View {
        HStack(spacing: 16) {
            Button(action: { showLiveCamera = true }) {
                HStack {
                    Spacer()
                    Label(selectedSkin == .secureLog ? "Capture Media" : "Live Scan", systemImage: "camera.fill")
                        .font(.system(.body, design: .rounded))
                        .bold()
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
            .foregroundColor(.blue)
            .accessibilityLabel("Capture new media")
            .accessibilityHint("Opens camera to take photo or video")
            
            Divider()
            
            PhotosPicker(selection: $selectedItems, matching: .images) {
                HStack {
                    Spacer()
                    Label(selectedSkin == .secureLog ? "Import" : "Load Asset", systemImage: "photo.stack.fill")
                        .font(.system(.body, design: .rounded))
                        .bold()
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
            .foregroundColor(.blue)
        }
        .padding(.vertical, 2)
        .onChange(of: selectedItems) { _, items in
            handlePhotoPickerSelection(items)
        }
    }
    
    private var toolbarControlsMenu: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Camouflage App Target", selection: $selectedEscapeApp) {
                    ForEach(CamouflageTarget.allCases) { target in
                        Text("Mask as: \(target.rawValue)").tag(target)
                    }
                }
                Divider()
                Picker("Skin Preset", selection: $selectedSkin) {
                    ForEach(AppSkin.allCases) { skin in
                        Text(skin.rawValue).tag(skin)
                    }
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body)
            }
            .accessibilityLabel("Settings menu")
            
            Button(action: triggerCamouflageAppLaunch) {
                Text("QUICK HIDE")
                    .font(.system(.caption, design: .rounded))
                    .bold()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .accessibilityLabel("Quick hide button")
            .accessibilityHint("Switches to camouflage app")
        }
    }
    
    private func ledgerContent(for asset: EvidenceAsset) -> some View {
        Group {
            nativeLedgerRow(label: "Asset Media Format Class",
                            value: asset.isVideo ? "📹 MP4 High-Compression Video Stream" : "📸 JPEG Static Evidence Artifact")
            nativeLedgerRow(label: "SHA-256 Authentication Footprint",
                            value: asset.fileHash, mono: true, highlightGreen: true)
            nativeLedgerRow(label: "Hardware Source Profile",
                            value: asset.deviceModel)
            nativeLedgerRow(label: "EXIF Timestamp (Taken)",
                            value: asset.dateTaken, highlightBlue: true)
            nativeLedgerRow(label: "Vault Timestamp (Saved)",
                            value: asset.dateSaved)
            nativeLedgerRow(label: "Package Metric Size",
                            value: asset.fileSize)
        }
    }
    
    private var emptyHistoryView: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                Text("No Export History Recorded")
                    .font(.system(.subheadline, design: .rounded))
                    .bold()
                    .foregroundColor(.secondary)
                Text("Certified property packages you build will automatically register here for instant recovery.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 30)
            .accessibilityElement(children: .combine)
            Spacer()
        }
    }
    
    private func reportRow(for report: GeneratedReport) -> some View {
        Button(action: {
            DispatchQueue.main.async {
                self.shareSheetItems = report.payloadPackageURLs
                self.showShareSheet = true
            }
        }) {
            HStack(spacing: 14) {
                Image(systemName: "doc.zip.fill")
                    .font(.title)
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Report Log: \(report.locationContext.isEmpty ? "General Case" : report.locationContext)")
                        .font(.system(.body, design: .rounded))
                        .bold()
                        .foregroundColor(.primary)
                    
                    Text("\(report.itemsCount) Media Artifacts • \(report.timestamp)")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Report from \(report.locationContext), \(report.itemsCount) items")
        .accessibilityHint("Double tap to share this report")
    }
    
    private func nativeLedgerRow(label: String, value: String, mono: Bool = false, highlightGreen: Bool = false, highlightBlue: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded))
                .bold()
                .foregroundColor(.secondary)
                .accessibilityAddTraits(.isHeader)
            
            Text(value)
                .font(mono ? .system(.footnote, design: .monospaced) : .system(.body, design: .rounded))
                .foregroundColor(highlightGreen && selectedSkin == .secureLog ? .green : (highlightBlue ? .blue : .primary))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
    
    // MARK: - Data Management & Presentation Helpers
    
    private func setLoading(_ loading: Bool, message: String = "") {
        isLoading = loading
        loadingMessage = message
    }
    
    private func showError(_ error: VaultError) {
        let description = error.errorDescription ?? "An unknown data error occurred."
        let suggestion = error.recoverySuggestion ?? "Please try your action again."
        
        let config = AlertConfig(
            title: "Error",
            message: "\(description)\n\n\(suggestion)",
            primaryButton: "OK"
        )
        
        alertConfig = config
        showAlert = true
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    private func purgeAssetFromVault(asset: EvidenceAsset) {
        DispatchQueue.main.async {
            do {
                try PersistenceController.shared.deleteAsset(asset)
                if let index = self.evidenceVault.firstIndex(of: asset) {
                    self.evidenceVault.remove(at: index)
                }
                if self.selectedAsset == asset {
                    self.selectedAsset = self.evidenceVault.last
                }
            } catch {
                self.showError(VaultError.deleteFailed(error.localizedDescription))
            }
        }
    }
    
    private func loadPersistedData() {
        setLoading(true, message: "Loading vault...")
        
        Task.detached(priority: .userInitiated) {
            do {
                let assets = try PersistenceController.shared.fetchAssets()
                let reports = try PersistenceController.shared.fetchReports()
                
                await MainActor.run {
                    self.evidenceVault = assets
                    self.certifiedReportsHistory = reports
                    self.selectedAsset = assets.first
                    self.setLoading(false)
                }
            } catch {
                await MainActor.run {
                    self.setLoading(false)
                    self.showError(VaultError.loadFailed(error.localizedDescription))
                }
            }
        }
    }
    
    private func validateAndGenerateReport() {
        guard !evidenceVault.isEmpty else {
            showError(VaultError.noAssetsToExport)
            return
        }
        
        let locationTrimmed = self.incidentLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesTrimmed = self.incidentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !locationTrimmed.isEmpty || !notesTrimmed.isEmpty else {
            showError(VaultError.missingRequiredFields)
            return
        }
        
        compileAndSharePackageDossier()
    }
    
    private func handlePhotoPickerSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        
        setLoading(true, message: "Importing media...")
        
        let snapshotItems = items
        Task {
            for item in snapshotItems {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            handleCapturedMedia(data: data, url: nil, isVideo: false)
                        }
                    }
                } catch {
                    await MainActor.run {
                        showError(VaultError.loadFailed("Failed to import item"))
                    }
                }
            }
            
            await MainActor.run {
                self.selectedItems.removeAll()
                self.setLoading(false)
            }
        }
    }
    
    private func handleCapturedMedia(data: Data, url: URL?, isVideo: Bool) {
        guard FileManager.hasEnoughStorage() else {
            showError(VaultError.insufficientStorage)
            return
        }
        
        setLoading(true, message: "Securing media...")
        
        Task.detached(priority: .userInitiated) {
            do {
                let secureData: (fileURL: URL, thumbnailURL: URL, hash: String, size: String)
                if isVideo, let sourceURL = url {
                    secureData = try FileManager.saveVideoSecurely(from: sourceURL)
                } else {
                    secureData = try FileManager.saveImageSecurely(UIImage(data: data) ?? UIImage(), isVideo: isVideo)
                }
                
                let exifData = FileManager.extractEXIFData(from: data)
                let dateSaved = Date().formatted(date: .abbreviated, time: .shortened)
                
                let newAsset = EvidenceAsset(
                    fileHash: secureData.hash,
                    fileSize: secureData.size,
                    deviceModel: exifData.deviceModel,
                    dateTaken: exifData.dateTaken,
                    dateSaved: dateSaved,
                    isVideo: isVideo,
                    relativeFilePath: secureData.fileURL.lastPathComponent,
                    relativeThumbPath: secureData.thumbnailURL.lastPathComponent
                )
                
                try PersistenceController.shared.saveAsset(newAsset)
                
                await MainActor.run {
                    self.evidenceVault.append(newAsset)
                    self.selectedAsset = newAsset
                    self.setLoading(false)
                    
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    UIAccessibility.post(notification: .announcement, argument: "Media saved securely")
                }
            } catch {
                await MainActor.run {
                    self.setLoading(false)
                    self.showError(error as? VaultError ?? VaultError.saveFailed(error.localizedDescription))
                }
            }
        }
    }
    
    private func confirmDelete(asset: EvidenceAsset) {
        let config = AlertConfig(
            title: "Delete Evidence?",
            message: "This will permanently remove this item from your vault. This action cannot be undone.",
            primaryButton: "Delete",
            secondaryButton: "Cancel",
            primaryAction: {
                purgeAssetFromVault(asset: asset)
            },
            secondaryAction: {}
        )
        
        alertConfig = config
        showAlert = true
    }
    
    
    private func triggerCamouflageAppLaunch() {
        if let schemeUrl = URL(string: selectedEscapeApp.urlScheme) {
            UIApplication.shared.open(schemeUrl)
        }
    }
    
    private func compileAndSharePackageDossier() {
        setLoading(true, message: "Generating certified report...")
        
        let vaultCopy = self.evidenceVault
        let peopleCopy = self.peopleInvolved
        let locationCopy = self.incidentLocation
        let notesCopy = self.incidentNotes
        
        Task.detached(priority: .userInitiated) {
            do {
                let fileManager = FileManager.default
                let tempRoot = fileManager.temporaryDirectory
                let packageDirectory = tempRoot.appendingPathComponent("Shield_Case_\(UUID().uuidString)")
                
                try fileManager.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
                
                var relativePathsToExport: [String] = []
                var filesToExport: [URL] = []
                
                let pdfBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
                let renderer = UIGraphicsPDFRenderer(bounds: pdfBounds)
                
                let pdfData = renderer.pdfData { context in
                    context.beginPage()
                    var cursorY: CGFloat = 50
                    let sideMargin: CGFloat = 45
                    let contentWidth: CGFloat = 522
                    
                    let titleAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 20),
                        .foregroundColor: UIColor.black
                    ]
                    "OFFICIAL SHIELD CERTIFIED CASE FILE".draw(at: CGPoint(x: sideMargin, y: cursorY), withAttributes: titleAttrs)
                    cursorY += 30
                    
                    context.cgContext.setLineWidth(1.5)
                    context.cgContext.setStrokeColor(UIColor.systemBlue.cgColor)
                    context.cgContext.move(to: CGPoint(x: sideMargin, y: cursorY))
                    context.cgContext.addLine(to: CGPoint(x: sideMargin + contentWidth, y: cursorY))
                    context.cgContext.strokePath()
                    cursorY += 20
                    
                    let metaLabelAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 11),
                        .foregroundColor: UIColor.gray
                    ]
                    let metaValAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 11),
                        .foregroundColor: UIColor.black
                    ]
                    
                    let fields = [
                        ("GENERATED TIME:", Date().formatted(date: .complete, time: .complete)),
                        ("PERSONS INVOLVED:", peopleCopy.isEmpty ? "None Stated" : peopleCopy),
                        ("LOCATION CONTEXT:", locationCopy.isEmpty ? "Not Provided" : locationCopy)
                    ]
                    
                    for field in fields {
                        field.0.draw(at: CGPoint(x: sideMargin, y: cursorY), withAttributes: metaLabelAttrs)
                        field.1.draw(at: CGPoint(x: sideMargin + 130, y: cursorY), withAttributes: metaValAttrs)
                        cursorY += 18
                    }
                    cursorY += 15
                    
                    "CHRONOLOGY DOSSIER NOTES:".draw(at: CGPoint(x: sideMargin, y: cursorY), withAttributes: [
                        .font: UIFont.boldSystemFont(ofSize: 12),
                        .foregroundColor: UIColor.systemBlue
                    ])
                    cursorY += 20
                    
                    let notesText = notesCopy.isEmpty ? "No detailed log notes attached to case package record assets." : notesCopy
                    let notesRect = CGRect(x: sideMargin, y: cursorY, width: contentWidth, height: 110)
                    notesText.draw(in: notesRect, withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                    cursorY += 130
                    
                    context.cgContext.setLineWidth(0.5)
                    context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
                    context.cgContext.move(to: CGPoint(x: sideMargin, y: cursorY))
                    context.cgContext.addLine(to: CGPoint(x: sideMargin + contentWidth, y: cursorY))
                    context.cgContext.strokePath()
                    cursorY += 25
                    
                    // ===== HIGH RES ORIGINAL IMAGE ENGINE LOOP =====
                    for (index, item) in vaultCopy.enumerated() {
                        var renderingSourceImage = item.thumbnail
                        if let uncompressedURL = item.localURL,
                           let rawDiskImage = UIImage(contentsOfFile: uncompressedURL.path) {
                            renderingSourceImage = rawDiskImage
                        }
                        
                        let targetPhotoWidth: CGFloat = 240
                        let imageSize = renderingSourceImage.size
                        
                        let aspectRatio = imageSize.height / imageSize.width
                        let renderedHeight = targetPhotoWidth * aspectRatio
                        
                        if (cursorY + renderedHeight + 50) > 740 {
                            context.beginPage()
                            cursorY = 50
                        }
                        
                        "Evidence Item #\(index + 1) [\(item.isVideo ? "COMPRESSED VIDEO" : "STATIC PHOTO")]".draw(
                            at: CGPoint(x: sideMargin, y: cursorY),
                            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: UIColor.black]
                        )
                        cursorY += 22
                        
                        let imageRect = CGRect(x: sideMargin, y: cursorY, width: targetPhotoWidth, height: renderedHeight)
                        renderingSourceImage.draw(in: imageRect)
                        
                        let textColumnX = sideMargin + targetPhotoWidth + 24
                        var textY = cursorY + 6
                        
                        let itemFields = [
                            ("SHA-256 Hash:", String(item.fileHash.prefix(20)) + "..."),
                            ("Source Device:", item.deviceModel),
                            ("EXIF Timestamp:", item.dateTaken),
                            ("Metric Size:", item.fileSize)
                        ]
                        
                        for dataField in itemFields {
                            dataField.0.draw(at: CGPoint(x: textColumnX, y: textY),
                                             withAttributes: [.font: UIFont.boldSystemFont(ofSize: 9.5), .foregroundColor: UIColor.darkGray])
                            dataField.1.draw(at: CGPoint(x: textColumnX + 85, y: textY),
                                             withAttributes: [.font: UIFont.systemFont(ofSize: 9.5), .foregroundColor: UIColor.black])
                            textY += 18
                        }
                        
                        if item.isVideo, let validURL = item.localURL {
                            let videoFilename = "Evidence_Video_\(index + 1).mp4"
                            let targetURL = packageDirectory.appendingPathComponent(videoFilename)
                            try? fileManager.copyItem(at: validURL, to: targetURL)
                            filesToExport.append(targetURL)
                            relativePathsToExport.append(targetURL.lastPathComponent)
                        }
                        
                        cursorY += renderedHeight + 40
                    }
                }
                
                let pdfActivityItem: Any = pdfData
                let timestamp = Date().formatted(date: .abbreviated, time: .shortened)
                
                let report = GeneratedReport(
                    timestamp: timestamp,
                    itemsCount: vaultCopy.count,
                    locationContext: locationCopy,
                    relativePayloadPaths: relativePathsToExport
                )
                
                try PersistenceController.shared.saveReport(report)
                
                await MainActor.run {
                    self.certifiedReportsHistory.append(report)
                    self.shareSheetItems = [pdfActivityItem] + filesToExport
                    self.showShareSheet = true
                    self.setLoading(false)
                    
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    UIAccessibility.post(notification: .announcement, argument: "Report generated successfully")
                }
                
            } catch {
                await MainActor.run {
                    self.setLoading(false)
                    self.showError(VaultError.pdfGenerationFailed)
                }
            }
        }
    }
}

// ===== SHARE SHEET =====
struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.excludedActivityTypes = [.addToReadingList, .assignToContact, .saveToCameraRoll]
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
