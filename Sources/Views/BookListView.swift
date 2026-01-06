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
                        ForEach(bookStore.books) { book in
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
                        }
                    }
                    .refreshable {
                        await bookStore.loadBooks()
                    }
                }
            }
            .navigationTitle("Family Books")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Text("Logged in as \(bookStore.userName)")
                        Button("Change Name") {
                            bookStore.userName = ""
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
                    bookToAdd = Book(isbn: isbn)
                    showingAddBook = true
                    scannedISBN = nil
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
        }
        .task {
            await bookStore.loadBooks()
        }
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
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BookListView()
        .environmentObject(BookStore())
}
