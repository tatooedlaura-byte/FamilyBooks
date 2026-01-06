import SwiftUI

struct BookListView: View {
    @EnvironmentObject var bookStore: BookStore
    @State private var showingScanner = false
    @State private var scannedISBN: String?
    @State private var showingAddBook = false
    @State private var bookToAdd: Book?
    @State private var showingManualEntry = false
    @State private var manualISBN = ""
    @State private var showingSheetImport = false
    @State private var showingCSVImport = false
    @State private var sheetURL = ""
    @State private var searchText = ""
    @State private var isLookingUp = false
    @State private var lookupProgress: (current: Int, total: Int)?
    @State private var showingDuplicates = false

    var filteredBooks: [Book] {
        if searchText.isEmpty {
            return bookStore.books
        }
        let query = searchText.lowercased()
        return bookStore.books.filter {
            $0.title.lowercased().contains(query) ||
            $0.authors.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if bookStore.books.isEmpty && !bookStore.isLoading {
                    ContentUnavailableView(
                        "No Books Yet",
                        systemImage: "book.closed",
                        description: Text("Tap + to scan a book barcode")
                    )
                } else {
                    List {
                        ForEach(filteredBooks) { book in
                            BookRowView(book: book)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task {
                                            await bookStore.deleteBook(book)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        Task {
                                            await bookStore.lookupAndUpdateBook(book)
                                        }
                                    } label: {
                                        Label("Lookup", systemImage: "magnifyingglass")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                    .refreshable {
                        await bookStore.loadBooks()
                    }
                }
            }
            .navigationTitle("Family Books")
            .searchable(text: $searchText, prompt: "Search by title or author")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Text("Logged in as \(bookStore.userName)")
                        Button("Change Name") {
                            bookStore.userName = ""
                        }

                        Divider()

                        Button {
                            Task {
                                await lookupAllMissing()
                            }
                        } label: {
                            Label("Lookup Missing Info", systemImage: "magnifyingglass")
                        }
                        .disabled(isLookingUp)

                        Button {
                            showingDuplicates = true
                        } label: {
                            Label("Find Duplicates", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Label(bookStore.userName, systemImage: "person.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Scan Barcode", systemImage: "barcode.viewfinder")
                        }

                        Button {
                            manualISBN = ""
                            showingManualEntry = true
                        } label: {
                            Label("Enter ISBN", systemImage: "keyboard")
                        }

                        Button {
                            showingSheetImport = true
                        } label: {
                            Label("Import Google Sheet", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            showingCSVImport = true
                        } label: {
                            Label("Import CSV File", systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if bookStore.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .alert("Error", isPresented: .constant(bookStore.error != nil)) {
                Button("OK") {
                    bookStore.error = nil
                }
            } message: {
                Text(bookStore.error ?? "")
            }
            .fullScreenCover(isPresented: $showingScanner) {
                BarcodeScannerView(scannedCode: $scannedISBN)
            }
            .onChange(of: scannedISBN) { _, newValue in
                if let isbn = newValue {
                    scannedISBN = nil
                    bookToAdd = Book(isbn: isbn)
                    // Delay to let scanner dismiss first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingAddBook = true
                    }
                }
            }
            .sheet(isPresented: $showingAddBook) {
                if let book = bookToAdd {
                    AddBookView(book: book)
                }
            }
            .alert("Enter ISBN", isPresented: $showingManualEntry) {
                TextField("ISBN", text: $manualISBN)
                    .keyboardType(.numberPad)
                Button("Cancel", role: .cancel) { }
                Button("Look Up") {
                    let isbn = manualISBN.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !isbn.isEmpty {
                        bookToAdd = Book(isbn: isbn)
                        showingAddBook = true
                    }
                }
            } message: {
                Text("Enter the book's ISBN number")
            }
            .sheet(isPresented: $showingSheetImport) {
                SheetImportView()
            }
            .sheet(isPresented: $showingCSVImport) {
                CSVImportView()
            }
            .sheet(isPresented: $showingDuplicates) {
                DuplicatesView()
            }
        }
        .task {
            await bookStore.loadBooks()
        }
        .overlay {
            if isLookingUp, let progress = lookupProgress {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Looking up book info...")
                        .font(.headline)
                    Text("\(progress.current) of \(progress.total)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func lookupAllMissing() async {
        let booksToLookup = bookStore.books.filter { $0.coverURL.isEmpty }

        guard !booksToLookup.isEmpty else { return }

        isLookingUp = true
        lookupProgress = (0, booksToLookup.count)

        for (index, book) in booksToLookup.enumerated() {
            lookupProgress = (index + 1, booksToLookup.count)
            _ = await bookStore.lookupAndUpdateBook(book)

            // Small delay to avoid rate limiting
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        isLookingUp = false
        lookupProgress = nil
    }
}

struct BookRowView: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: book.coverURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "book.closed.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50, height: 70)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title.isEmpty ? "Unknown Title" : book.title)
                    .font(.headline)
                    .lineLimit(2)

                if !book.authors.isEmpty {
                    Text(book.authors)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("Added by \(book.addedBy)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if book.copies > 1 {
                Text("\(book.copies)x")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BookListView()
        .environmentObject(BookStore())
}
