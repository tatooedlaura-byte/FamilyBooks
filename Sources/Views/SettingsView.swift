import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bookStore: BookStore

    @State private var sheetURL: String = ""
    @State private var showingHelp = false
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var isSyncing = false
    @State private var syncResult: String?

    private let templateURL = "https://docs.google.com/spreadsheets/d/1VHGjb2sZ9dtJgxtGZ_oH1VyWGhe5kMkWMQt3fUpZczI/copy"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Storage Settings")
                            .font(.headline)

                        Text("Choose where to store your book library. Local storage keeps everything on this device. Google Sheets lets you share with family.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Storage Location") {
                    Picker("Storage", selection: $bookStore.storageMode) {
                        HStack {
                            Image(systemName: "iphone")
                            Text("Local (This Device)")
                        }
                        .tag(StorageMode.local)

                        HStack {
                            Image(systemName: "cloud")
                            Text("Google Sheets")
                        }
                        .tag(StorageMode.googleSheets)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: bookStore.storageMode) { _, _ in
                        Task {
                            await bookStore.loadBooks()
                        }
                    }

                    if bookStore.storageMode == .local {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Books saved on device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if bookStore.storageMode == .googleSheets {
                    Section("Step 1: Create Your Sheet") {
                        Link(destination: URL(string: templateURL)!) {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                    .foregroundStyle(.blue)
                                Text("Copy Template Sheet")
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("This creates your own copy of the template with the correct columns.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Step 2: Make It Accessible") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("In your Google Sheet:")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            VStack(alignment: .leading, spacing: 4) {
                                Label("Click Share (top right)", systemImage: "1.circle.fill")
                                Label("Click 'Change to anyone with link'", systemImage: "2.circle.fill")
                                Label("Set to 'Viewer'", systemImage: "3.circle.fill")
                                Label("Copy the link", systemImage: "4.circle.fill")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Step 3: Paste Your Sheet URL") {
                        TextField("https://docs.google.com/spreadsheets/d/...", text: $sheetURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        if let result = testResult {
                            HStack {
                                Image(systemName: result.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.contains("Success") ? .green : .red)
                                Text(result)
                                    .font(.caption)
                            }
                        }

                        Button {
                            Task {
                                await testConnection()
                            }
                        } label: {
                            HStack {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text(isTesting ? "Testing..." : "Test Connection")
                            }
                        }
                        .disabled(sheetURL.isEmpty || isTesting)
                    }

                    Section {
                        Button {
                            saveConfiguration()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Save Google Sheet Configuration")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(sheetURL.isEmpty)
                    }

                    Section("Current Configuration") {
                        if GoogleSheetsService.isConfigured {
                            let currentID = GoogleSheetsService.currentSpreadsheetId
                            LabeledContent("Spreadsheet ID") {
                                Text(currentID.prefix(20) + "...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No Google Sheet configured")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Share With Family") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("To share your library with family:")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("1. Share your Google Sheet with their email\n2. Install the app on their device\n3. Have them paste the same Sheet URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if bookStore.storageMode == .local && GoogleSheetsService.isConfigured {
                    Section("Sync Options") {
                        Button {
                            Task {
                                await importFromSheets()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle")
                                Text("Import from Google Sheets")
                            }
                        }
                        .disabled(isSyncing)

                        Button {
                            Task {
                                await syncToSheets()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.circle")
                                Text("Backup to Google Sheets")
                            }
                        }
                        .disabled(isSyncing)

                        if let result = syncResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(result.contains("Success") ? .green : .red)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Books in Library", value: "\(bookStore.books.count)")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadCurrentURL()
            }
        }
    }

    private func loadCurrentURL() {
        if let savedURL = UserDefaults.standard.string(forKey: "googleSheetURL") {
            sheetURL = savedURL
        }
    }

    private func extractSpreadsheetId(from url: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "/d/([a-zA-Z0-9_-]+)", options: []) else {
            return nil
        }

        let range = NSRange(url.startIndex..., in: url)
        guard let match = regex.firstMatch(in: url, options: [], range: range) else {
            return nil
        }

        guard let idRange = Range(match.range(at: 1), in: url) else {
            return nil
        }

        return String(url[idRange])
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil

        guard let spreadsheetId = extractSpreadsheetId(from: sheetURL) else {
            testResult = "Invalid URL format"
            isTesting = false
            return
        }

        let testService = GoogleSheetsService(spreadsheetId: spreadsheetId)

        do {
            let books = try await testService.fetchBooks()
            testResult = "Success! Found \(books.count) books"
        } catch {
            testResult = "Failed: \(error.localizedDescription)"
        }

        isTesting = false
    }

    private func saveConfiguration() {
        guard let spreadsheetId = extractSpreadsheetId(from: sheetURL) else {
            testResult = "Invalid URL format"
            return
        }

        UserDefaults.standard.set(sheetURL, forKey: "googleSheetURL")
        UserDefaults.standard.set(spreadsheetId, forKey: "googleSpreadsheetId")

        Task {
            await bookStore.loadBooks()
        }

        testResult = "Configuration saved!"
    }

    private func importFromSheets() async {
        isSyncing = true
        syncResult = nil

        do {
            try await bookStore.importFromGoogleSheets()
            syncResult = "Success! Imported books from Google Sheets"
        } catch {
            syncResult = "Failed: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    private func syncToSheets() async {
        isSyncing = true
        syncResult = nil

        do {
            try await bookStore.syncToGoogleSheets()
            syncResult = "Success! Backed up to Google Sheets"
        } catch {
            syncResult = "Failed: \(error.localizedDescription)"
        }

        isSyncing = false
    }
}

#Preview {
    SettingsView()
        .environmentObject(BookStore())
}
