import SwiftUI
import UniformTypeIdentifiers

struct JSONImportView: View {
    @EnvironmentObject var bookStore: BookStore
    @Environment(\.dismiss) var dismiss

    @State private var isImporting = false
    @State private var importProgress: (current: Int, total: Int)?
    @State private var importError: String?
    @State private var importComplete = false
    @State private var importedCount = 0
    @State private var showingFilePicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Import Books from JSON")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Select the books_for_import.json file from your FamilyBooks folder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if isImporting {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        if let progress = importProgress {
                            Text("Importing \(progress.current) of \(progress.total)...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 20)
                } else if importComplete {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.green)
                        Text("Successfully imported \(importedCount) books!")
                            .font(.headline)
                    }
                    .padding(.top, 20)
                } else {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Select JSON File", systemImage: "folder")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                }

                if let error = importError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding()
                }

                Spacer()
                Spacer()
            }
            .navigationTitle("Import JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if importComplete {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [UTType.json],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await handleFileSelection(result)
                }
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            await importFromURL(url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func importFromURL(_ url: URL) async {
        isImporting = true
        importError = nil

        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Cannot access the selected file"
            isImporting = false
            return
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
                importError = "Invalid JSON format"
                isImporting = false
                return
            }

            let totalBooks = json.count
            importProgress = (0, totalBooks)

            var booksToImport: [Book] = []

            for (index, (_, bookData)) in json.enumerated() {
                importProgress = (index + 1, totalBooks)

                let statusString = bookData["readingStatus"] as? String ?? ""
                let readingStatus = ReadingStatus(rawValue: statusString) ?? .none
                let formatString = bookData["format"] as? String ?? "Physical"
                let format = BookFormat(rawValue: formatString) ?? .physical

                let book = Book(
                    isbn: bookData["isbn"] as? String ?? "",
                    title: bookData["title"] as? String ?? "",
                    authors: bookData["authors"] as? String ?? "",
                    publisher: bookData["publisher"] as? String ?? "",
                    publishDate: bookData["publishDate"] as? String ?? "",
                    numberOfPages: bookData["numberOfPages"] as? String ?? "",
                    coverURL: bookData["coverURL"] as? String ?? "",
                    notes: bookData["notes"] as? String ?? "",
                    addedBy: bookData["addedBy"] as? String ?? "JSON Import",
                    addedAt: Date(),
                    copies: bookData["copies"] as? Int ?? 1,
                    readingStatus: readingStatus,
                    isWishlist: bookData["isWishlist"] as? Bool ?? false,
                    format: format
                )

                booksToImport.append(book)
            }

            // Import in batches
            let batchSize = 50
            for i in stride(from: 0, to: booksToImport.count, by: batchSize) {
                let end = min(i + batchSize, booksToImport.count)
                let batch = Array(booksToImport[i..<end])
                try await bookStore.addBooks(batch)
                importProgress = (end, totalBooks)
            }

            importedCount = booksToImport.count
            importComplete = true

        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }

        isImporting = false
    }
}

#Preview {
    JSONImportView()
        .environmentObject(BookStore())
}
