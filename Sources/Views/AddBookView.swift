import SwiftUI

struct AddBookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bookStore: BookStore

    @State var book: Book
    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var hasLookedUp = false

    private let openLibrary = OpenLibraryService()

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
                }

                if let error = lookupError {
                    Section {
                        Text(error)
                            .foregroundStyle(.orange)
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
            guard !hasLookedUp else { return }
            hasLookedUp = true
            await lookupBook()
        }
    }

    private func lookupBook() async {
        isLookingUp = true
        lookupError = nil

        do {
            if let foundBook = try await openLibrary.lookupBook(isbn: book.isbn) {
                book.title = foundBook.title
                book.authors = foundBook.authors
                book.publisher = foundBook.publisher
                book.publishDate = foundBook.publishDate
                book.numberOfPages = foundBook.numberOfPages
                book.coverURL = foundBook.coverURL
            } else {
                lookupError = "Book not found in Open Library. Enter details manually."
            }
        } catch {
            lookupError = "Lookup failed. Enter details manually."
        }

        isLookingUp = false
    }
}

#Preview {
    AddBookView(book: Book(isbn: "9780143127796"))
        .environmentObject(BookStore())
}
