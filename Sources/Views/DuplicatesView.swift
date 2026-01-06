import SwiftUI

struct DuplicatesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bookStore: BookStore

    @State private var duplicateGroups: [[Book]] = []
    @State private var isScanning = false
    @State private var isMerging = false

    var body: some View {
        NavigationStack {
            Group {
                if isScanning {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Scanning for duplicates...")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if duplicateGroups.isEmpty {
                    ContentUnavailableView(
                        "No Duplicates Found",
                        systemImage: "checkmark.circle",
                        description: Text("All books appear to be unique")
                    )
                } else {
                    List {
                        ForEach(duplicateGroups.indices, id: \.self) { groupIndex in
                            Section {
                                ForEach(duplicateGroups[groupIndex]) { book in
                                    DuplicateBookRow(book: book)
                                }

                                Button {
                                    Task {
                                        await mergeGroup(at: groupIndex)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.triangle.merge")
                                        Text("Merge into 1 (keep \(duplicateGroups[groupIndex].count) copies)")
                                    }
                                }
                                .disabled(isMerging)
                            } header: {
                                Text("\(duplicateGroups[groupIndex].count) copies")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Find Duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await scanForDuplicates()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isScanning)
                }
            }
        }
        .task {
            await scanForDuplicates()
        }
    }

    private func scanForDuplicates() async {
        isScanning = true

        // Group books by normalized title + author
        var groups: [String: [Book]] = [:]

        for book in bookStore.books {
            let key = normalizeForComparison(title: book.title, author: book.authors)
            groups[key, default: []].append(book)
        }

        // Filter to only groups with 2+ books
        duplicateGroups = groups.values
            .filter { $0.count > 1 }
            .sorted { $0.first?.title ?? "" < $1.first?.title ?? "" }

        isScanning = false
    }

    private func normalizeForComparison(title: String, author: String) -> String {
        let normalizedTitle = title.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "the ", with: "")
            .replacingOccurrences(of: "a ", with: "")

        let normalizedAuthor = author.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return "\(normalizedTitle)|\(normalizedAuthor)"
    }

    private func mergeGroup(at index: Int) async {
        guard index < duplicateGroups.count else { return }

        isMerging = true

        let group = duplicateGroups[index]
        guard var keepBook = group.first else {
            isMerging = false
            return
        }

        // Set copies to total count
        keepBook.copies = group.count

        // Merge notes from all copies
        let allNotes = group.compactMap { $0.notes.isEmpty ? nil : $0.notes }
        if !allNotes.isEmpty {
            keepBook.notes = allNotes.joined(separator: "\n---\n")
        }

        // Use the best cover URL (first non-empty one)
        if keepBook.coverURL.isEmpty {
            keepBook.coverURL = group.first { !$0.coverURL.isEmpty }?.coverURL ?? ""
        }

        // Update the kept book
        _ = await bookStore.updateBook(keepBook)

        // Delete the other copies
        for book in group.dropFirst() {
            _ = await bookStore.deleteBook(book)
        }

        // Refresh duplicates list
        await scanForDuplicates()

        isMerging = false
    }
}

struct DuplicateBookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: book.coverURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 55)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if !book.authors.isEmpty {
                    Text(book.authors)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("Added by \(book.addedBy)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if book.copies > 1 {
                Text("\(book.copies)x")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }
}

#Preview {
    DuplicatesView()
        .environmentObject(BookStore())
}
