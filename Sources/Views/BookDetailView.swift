import SwiftUI

struct BookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bookStore: BookStore

    @State var book: Book
    @State private var isEditing = false
    @State private var isLookingUp = false

    var body: some View {
        Form {
            Section {
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
                        .frame(height: 200)
                        Spacer()
                    }
                }
            }

            Section("Book Details") {
                if isEditing {
                    TextField("Title", text: $book.title)
                    TextField("Authors", text: $book.authors)
                    TextField("Publisher", text: $book.publisher)
                    TextField("Publish Date", text: $book.publishDate)
                    TextField("Number of Pages", text: $book.numberOfPages)
                        .keyboardType(.numberPad)
                    TextField("ISBN", text: $book.isbn)
                        .font(.system(.body, design: .monospaced))
                } else {
                    LabeledContent("Title", value: book.title.isEmpty ? "Unknown" : book.title)
                    LabeledContent("Authors", value: book.authors.isEmpty ? "Unknown" : book.authors)
                    LabeledContent("Publisher", value: book.publisher.isEmpty ? "Unknown" : book.publisher)
                    LabeledContent("Published", value: book.publishDate.isEmpty ? "Unknown" : book.publishDate)
                    LabeledContent("Pages", value: book.numberOfPages.isEmpty ? "Unknown" : book.numberOfPages)
                    LabeledContent("ISBN", value: book.isbn)
                }
            }

            Section("Status") {
                Picker("Reading Status", selection: $book.readingStatus) {
                    Text("None").tag(ReadingStatus.none)
                    Label("Want to Read", systemImage: "bookmark").tag(ReadingStatus.wantToRead)
                    Label("Reading", systemImage: "book").tag(ReadingStatus.reading)
                    Label("Read", systemImage: "checkmark.circle").tag(ReadingStatus.read)
                }
                .onChange(of: book.readingStatus) { _, _ in
                    Task { await bookStore.updateBook(book) }
                }

                Toggle("Wishlist (don't own yet)", isOn: $book.isWishlist)
                    .onChange(of: book.isWishlist) { _, _ in
                        Task { await bookStore.updateBook(book) }
                    }
            }

            Section("Copies") {
                if isEditing {
                    Stepper("Copies: \(book.copies)", value: $book.copies, in: 1...99)
                } else {
                    LabeledContent("Copies", value: "\(book.copies)")
                }
            }

            Section("Notes") {
                if isEditing {
                    TextField("Notes", text: $book.notes, axis: .vertical)
                        .lineLimit(3...6)
                } else {
                    Text(book.notes.isEmpty ? "No notes" : book.notes)
                        .foregroundStyle(book.notes.isEmpty ? .secondary : .primary)
                }
            }

            Section {
                LabeledContent("Added by", value: book.addedBy)
                LabeledContent("Added on", value: book.addedAt.formatted(date: .abbreviated, time: .omitted))
            }

            if !isEditing {
                Section {
                    Button {
                        Task {
                            await lookupBook()
                        }
                    } label: {
                        HStack {
                            if isLookingUp {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Lookup Book Info")
                        }
                    }
                    .disabled(isLookingUp)
                }
            }
        }
        .navigationTitle(book.title.isEmpty ? "Book Details" : book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isEditing {
                    Button("Save") {
                        Task {
                            await bookStore.updateBook(book)
                            isEditing = false
                        }
                    }
                } else {
                    Button("Edit") {
                        isEditing = true
                    }
                }
            }

            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isEditing = false
                    }
                }
            }
        }
    }

    private func lookupBook() async {
        isLookingUp = true

        do {
            if let foundBook = try await OpenLibraryService.shared.lookupBook(isbn: book.isbn) {
                book.title = foundBook.title
                book.authors = foundBook.authors
                book.publisher = foundBook.publisher
                book.publishDate = foundBook.publishDate
                book.numberOfPages = foundBook.numberOfPages
                book.coverURL = foundBook.coverURL
                await bookStore.updateBook(book)
            }
        } catch {
            // Silently fail - user can retry
        }

        isLookingUp = false
    }
}

#Preview {
    NavigationStack {
        BookDetailView(book: Book(
            isbn: "9780143127796",
            title: "The Great Gatsby",
            authors: "F. Scott Fitzgerald",
            publisher: "Scribner",
            publishDate: "1925",
            numberOfPages: "180",
            addedBy: "Laura"
        ))
        .environmentObject(BookStore())
    }
}
