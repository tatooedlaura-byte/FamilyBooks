import SwiftUI

struct SheetImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bookStore: BookStore

    @State private var sheetURL = ""
    @State private var isImporting = false
    @State private var importResult: ImportResult?
    @State private var importProgress: ImportProgress?

    struct ImportProgress {
        var current: Int
        var total: Int
        var status: String
    }

    enum ImportResult {
        case success(count: Int)
        case error(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Google Sheet URL", text: $sheetURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Sheet URL")
                } footer: {
                    Text("Paste the full URL of a Google Sheet with book data. The sheet should have columns: ISBN, Title, Authors, Publisher, Publish Date, Pages, Cover URL, Notes, Added By, Added At")
                }

                Section {
                    Button {
                        Task {
                            await importSheet()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isImporting {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Importing...")
                            } else {
                                Text("Import Books")
                            }
                            Spacer()
                        }
                    }
                    .disabled(sheetURL.isEmpty || isImporting)
                }

                if let progress = importProgress, isImporting {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(progress.status)
                                .font(.subheadline)
                            ProgressView(value: Double(progress.current), total: Double(progress.total))
                            Text("\(progress.current) of \(progress.total) books")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let result = importResult {
                    Section {
                        switch result {
                        case .success(let count):
                            Label("\(count) books imported successfully", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .error(let message):
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Text("Current Sheet ID:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(GoogleSheetsService.currentSpreadsheetId)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import Sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func importSheet() async {
        isImporting = true
        importResult = nil
        importProgress = nil

        // Extract spreadsheet ID from URL
        guard let spreadsheetId = extractSpreadsheetId(from: sheetURL) else {
            importResult = .error("Invalid Google Sheet URL")
            isImporting = false
            return
        }

        do {
            importProgress = ImportProgress(current: 0, total: 0, status: "Fetching books from sheet...")

            // Try different sheet names
            var books: [Book] = []
            let sheetNames = ["Books", "Sheet1", "books", "Library", "library"]

            for sheetName in sheetNames {
                do {
                    let service = GoogleSheetsService(spreadsheetId: spreadsheetId, sheetName: sheetName)
                    books = try await service.fetchBooks()
                    if !books.isEmpty { break }
                } catch {
                    continue
                }
            }

            if books.isEmpty {
                importResult = .error("No books found. Check sheet is shared publicly and has ISBN column.")
                isImporting = false
                importProgress = nil
                return
            }

            // Import in batches of 100
            let batchSize = 100
            let totalBooks = books.count
            var importedCount = 0

            importProgress = ImportProgress(current: 0, total: totalBooks, status: "Importing books...")

            for batchStart in stride(from: 0, to: totalBooks, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, totalBooks)
                let batch = Array(books[batchStart..<batchEnd])

                do {
                    try await bookStore.sheetsService.addBooks(batch)
                    importedCount += batch.count
                    importProgress = ImportProgress(current: importedCount, total: totalBooks, status: "Importing books...")
                } catch {
                    // Continue with next batch if one fails
                }
            }

            importResult = .success(count: importedCount)
            importProgress = nil
            await bookStore.loadBooks()
        } catch {
            importResult = .error("Failed to fetch books: \(error.localizedDescription)")
            importProgress = nil
        }

        isImporting = false
    }

    private func extractSpreadsheetId(from url: String) -> String? {
        // URL format: https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit
        let pattern = #"/spreadsheets/d/([a-zA-Z0-9-_]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let range = Range(match.range(at: 1), in: url) else {
            return nil
        }
        return String(url[range])
    }
}

#Preview {
    SheetImportView()
        .environmentObject(BookStore())
}
