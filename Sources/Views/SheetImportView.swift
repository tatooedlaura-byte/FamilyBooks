import SwiftUI

struct SheetImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bookStore: BookStore

    @State private var sheetURL = ""
    @State private var isImporting = false
    @State private var importResult: ImportResult?

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

        // Extract spreadsheet ID from URL
        guard let spreadsheetId = extractSpreadsheetId(from: sheetURL) else {
            importResult = .error("Invalid Google Sheet URL")
            isImporting = false
            return
        }

        do {
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
                return
            }

            // Add each book to our sheet
            var importedCount = 0
            for book in books {
                do {
                    try await bookStore.sheetsService.addBook(book)
                    importedCount += 1
                } catch {
                    // Continue with other books if one fails
                }
            }

            importResult = .success(count: importedCount)
            await bookStore.loadBooks()
        } catch {
            importResult = .error("Failed to fetch books: \(error.localizedDescription)")
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
