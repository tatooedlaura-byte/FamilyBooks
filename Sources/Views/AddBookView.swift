import SwiftUI

struct AddBookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bookStore: BookStore

    @State var book: Book
    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var hasLookedUp = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("ISBN")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(book.isbn)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                if isLookingUp {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Looking up book...")
                            Spacer()
                        }
                    }
                } else {
                    Section("Book Details") {
                        TextField("Title", text: $book.title)
                        TextField("Authors", text: $book.authors)
                        TextField("Publisher", text: $book.publisher)
                        TextField("Publish Date", text: $book.publishDate)
                        TextField("Number of Pages", text: $book.numberOfPages)
                            .keyboardType(.numberPad)
                    }

                    Section("Cover") {
                        if !book.coverURL.isEmpty {
                            HStack {
                                Spacer()
                                AsyncImage(url: URL(string: book.coverURL)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(height: 150)
                                Spacer()
                            }
                        } else {
                            Text("No cover found")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Notes") {
                        TextField("Add notes (optional)", text: $book.notes, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    Section("Format") {
                        Picker("Format", selection: $book.format) {
                            ForEach(BookFormat.allCases, id: \.self) { format in
                                Label(format.rawValue, systemImage: format.icon)
                                    .tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if let error = lookupError {
                    Section {
                        Text(error)
                            .foregroundStyle(.orange)

                        Button("Retry Lookup") {
                            hasLookedUp = false
                            Task {
                                await lookupBook()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            if await bookStore.addBook(book) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(book.title.isEmpty || isLookingUp)
                }
            }
        }
        .task {
            // Skip lookup if book already has data (was looked up before sheet opened)
            guard !hasLookedUp && book.title.isEmpty else { return }
            hasLookedUp = true
            // Wait for sheet animation to complete before starting lookup
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await lookupBook()
        }
    }

    private func lookupBook() async {
        isLookingUp = true
        lookupError = nil

        do {
            if let foundBook = try await OpenLibraryService.shared.lookupBook(isbn: book.isbn) {
                book.title = foundBook.title
                book.authors = foundBook.authors
                book.publisher = foundBook.publisher
                book.publishDate = foundBook.publishDate
                book.numberOfPages = foundBook.numberOfPages
                book.coverURL = foundBook.coverURL
            } else {
                lookupError = "Book not found in Open Library (ISBN: \(book.isbn)). Enter details manually."
            }
        } catch {
            lookupError = "Lookup failed: \(error.localizedDescription)"
        }

        isLookingUp = false
    }
}

#Preview {
    AddBookView(book: Book(isbn: "9780143127796"))
        .environmentObject(BookStore())
}
