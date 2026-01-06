import SwiftUI
import UniformTypeIdentifiers

struct CSVImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bookStore: BookStore

    @State private var isPickerPresented = false
    @State private var isImporting = false
    @State private var importResult: ImportResult?
    @State private var importProgress: ImportProgress?
    @State private var previewBooks: [Book] = []
    @State private var showPreview = false

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
                    Button {
                        isPickerPresented = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Select CSV File")
                        }
                    }
                    .disabled(isImporting)
                } footer: {
                    Text("Select a CSV file with book data. Common columns: Title, Author, ISBN, Publisher, Pages, Notes")
                }

                if showPreview && !previewBooks.isEmpty {
                    Section {
                        Text("Found \(previewBooks.count) books")
                            .font(.headline)

                        ForEach(previewBooks.prefix(5), id: \.isbn) { book in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if !book.authors.isEmpty {
                                    Text(book.authors)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if previewBooks.count > 5 {
                            Text("... and \(previewBooks.count - 5) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Preview")
                    }

                    Section {
                        Button {
                            Task {
                                await importBooks()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if isImporting {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                    Text("Importing...")
                                } else {
                                    Text("Import \(previewBooks.count) Books")
                                }
                                Spacer()
                            }
                        }
                        .disabled(isImporting)
                    }
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
            }
            .navigationTitle("Import CSV")
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
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                importResult = .error("Couldn't access the file")
                return
            }

            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                previewBooks = parseCSV(content)

                if previewBooks.isEmpty {
                    importResult = .error("No books found in CSV. Make sure it has a Title column.")
                } else {
                    showPreview = true
                    importResult = nil
                }
            } catch {
                importResult = .error("Couldn't read file: \(error.localizedDescription)")
            }

        case .failure(let error):
            importResult = .error("File selection failed: \(error.localizedDescription)")
        }
    }

    private func parseCSV(_ content: String) -> [Book] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard lines.count > 1 else { return [] }

        // Parse header row
        let headers = parseCSVLine(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Map columns
        let columnMap = CSVColumnMap(headers: headers)

        // Parse data rows
        var books: [Book] = []

        for i in 1..<lines.count {
            let values = parseCSVLine(lines[i])

            let title = columnMap.value(from: values, for: .title)

            // Skip rows without a title
            guard !title.isEmpty else { continue }

            // Use ISBN if available, otherwise generate from title
            var isbn = columnMap.value(from: values, for: .isbn)
            if isbn.isEmpty {
                isbn = "imported-\(i)-\(title.prefix(20).replacingOccurrences(of: " ", with: "-").lowercased())"
            }

            let book = Book(
                isbn: isbn,
                title: title,
                authors: columnMap.value(from: values, for: .authors),
                publisher: columnMap.value(from: values, for: .publisher),
                publishDate: columnMap.value(from: values, for: .publishDate),
                numberOfPages: columnMap.value(from: values, for: .numberOfPages),
                coverURL: columnMap.value(from: values, for: .coverURL),
                notes: columnMap.value(from: values, for: .notes),
                addedBy: columnMap.value(from: values, for: .addedBy).isEmpty ? "CSV Import" : columnMap.value(from: values, for: .addedBy),
                addedAt: Date()
            )

            books.append(book)
        }

        return books
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false

        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }

        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    private func importBooks() async {
        isImporting = true
        importResult = nil

        let totalBooks = previewBooks.count
        var importedCount = 0

        importProgress = ImportProgress(current: 0, total: totalBooks, status: "Importing books...")

        // Import in batches of 100
        let batchSize = 100

        for batchStart in stride(from: 0, to: totalBooks, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, totalBooks)
            let batch = Array(previewBooks[batchStart..<batchEnd])

            do {
                try await bookStore.addBooks(batch)
                importedCount += batch.count
                importProgress = ImportProgress(current: importedCount, total: totalBooks, status: "Importing books...")
            } catch {
                // Continue with next batch
            }
        }

        importResult = .success(count: importedCount)
        importProgress = nil
        showPreview = false
        previewBooks = []
        await bookStore.loadBooks()

        isImporting = false
    }
}

private struct CSVColumnMap {
    enum Column: CaseIterable {
        case isbn, title, authors, publisher, publishDate, numberOfPages, coverURL, notes, addedBy

        var possibleNames: [String] {
            switch self {
            case .isbn: return ["isbn", "isbn-13", "isbn-10", "isbn13", "isbn10", "barcode", "upc", "ean"]
            case .title: return ["title", "book title", "name", "book name", "book"]
            case .authors: return ["authors", "author", "by", "written by", "writer", "author(s)"]
            case .publisher: return ["publisher", "published by", "pub", "publishing"]
            case .publishDate: return ["publish date", "published", "date published", "publication date", "year", "pub date", "date", "publication year"]
            case .numberOfPages: return ["pages", "number of pages", "page count", "# pages", "numofpages", "page"]
            case .coverURL: return ["cover", "cover url", "cover image", "image", "thumbnail", "coverurl", "image url"]
            case .notes: return ["notes", "note", "comments", "description", "memo", "summary", "review"]
            case .addedBy: return ["added by", "addedby", "added_by", "user", "owner", "who added", "contributor", "reader", "read by"]
            }
        }
    }

    private var indices: [Column: Int] = [:]

    init(headers: [String]) {
        for column in Column.allCases {
            for name in column.possibleNames {
                if let index = headers.firstIndex(of: name) {
                    indices[column] = index
                    break
                }
            }
        }
    }

    func value(from row: [String], for column: Column) -> String {
        guard let index = indices[column], index < row.count else {
            return ""
        }
        return row[index]
    }
}

#Preview {
    CSVImportView()
        .environmentObject(BookStore())
}
