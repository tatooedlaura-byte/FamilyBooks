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
    @State private var showingJSONImport = false
    @State private var sheetURL = ""
    @State private var searchText = ""
    @State private var isLookingUp = false
    @State private var lookupProgress: (current: Int, total: Int)?
    @State private var showingDuplicates = false
    @State private var isLookingUpScanned = false
    @State private var sortByAuthor = false
    @State private var showWishlist = false
    @State private var showingQuickScan = false
    @State private var showGridView = false
    @State private var showingSettings = false

    // Strip leading articles (a, an, the) from a string for sorting
    func sortableTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let articles = ["the ", "a ", "an "]
        for article in articles {
            if trimmed.hasPrefix(article) {
                return String(title.dropFirst(article.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return title
    }

    var filteredBooks: [Book] {
        var books = bookStore.books.filter { $0.isWishlist == showWishlist }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            books = books.filter {
                $0.title.lowercased().contains(query) ||
                $0.authors.lowercased().contains(query)
            }
        }

        if sortByAuthor {
            return books.sorted {
                let author1 = $0.authors.isEmpty ? "ZZZ" : $0.authors
                let author2 = $1.authors.isEmpty ? "ZZZ" : $1.authors
                return author1.localizedCaseInsensitiveCompare(author2) == .orderedAscending
            }
        } else {
            return books.sorted {
                sortableTitle($0.title).localizedCaseInsensitiveCompare(sortableTitle($1.title)) == .orderedAscending
            }
        }
    }

    var ownedBookCount: Int {
        bookStore.books.filter { !$0.isWishlist }.count
    }

    var wishlistCount: Int {
        bookStore.books.filter { $0.isWishlist }.count
    }

    var groupedBooks: [(letter: String, books: [Book])] {
        let grouped = Dictionary(grouping: filteredBooks) { book -> String in
            let text: String
            if sortByAuthor {
                let authors = book.authors.trimmingCharacters(in: .whitespacesAndNewlines)
                text = authors.isEmpty ? "" : authors
            } else {
                text = sortableTitle(book.title)
            }
            guard let first = text.first else { return "#" }
            let letter = String(first).uppercased()
            return letter.first?.isLetter == true ? letter : "#"
        }
        return grouped.sorted { $0.key < $1.key }.map { (letter: $0.key, books: $0.value) }
    }

    var availableLetters: [String] {
        groupedBooks.map { $0.letter }
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
                } else if showGridView {
                    // Grid View
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)
                        ], spacing: 16) {
                            ForEach(filteredBooks) { book in
                                NavigationLink {
                                    BookDetailView(book: book)
                                } label: {
                                    BookGridItem(book: book)
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await bookStore.loadBooks()
                    }
                } else {
                    // List View
                    ScrollViewReader { proxy in
                        ZStack {
                            List {
                                ForEach(groupedBooks, id: \.letter) { group in
                                    Section {
                                        ForEach(group.books) { book in
                                            NavigationLink {
                                                BookDetailView(book: book)
                                            } label: {
                                                BookRowView(book: book)
                                            }
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
                                    } header: {
                                        Text(group.letter)
                                            .id(group.letter)
                                    }
                                }
                            }
                            .refreshable {
                                await bookStore.loadBooks()
                            }
                            .contentMargins(.leading, 0, for: .scrollContent)
                            .contentMargins(.trailing, 36, for: .scrollContent)

                            // Alphabet index on the right side
                            if searchText.isEmpty && availableLetters.count > 1 {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 0) {
                                        ForEach(availableLetters, id: \.self) { letter in
                                            Button {
                                                withAnimation {
                                                    proxy.scrollTo(letter, anchor: .top)
                                                }
                                            } label: {
                                                Text(letter)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .frame(width: 16, height: 16)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 2)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .padding(.trailing, 4)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(showWishlist ? "Wishlist (\(wishlistCount))" : "Library (\(ownedBookCount))")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search by title or author")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        // View picker
                        Button {
                            showWishlist = false
                        } label: {
                            Label("Library", systemImage: showWishlist ? "" : "checkmark")
                        }
                        Button {
                            showWishlist = true
                        } label: {
                            Label("Wishlist", systemImage: showWishlist ? "checkmark" : "")
                        }

                        Divider()

                        // Sort options
                        Button {
                            sortByAuthor = false
                        } label: {
                            Label("Sort by Title", systemImage: sortByAuthor ? "" : "checkmark")
                        }
                        Button {
                            sortByAuthor = true
                        } label: {
                            Label("Sort by Author", systemImage: sortByAuthor ? "checkmark" : "")
                        }
                    } label: {
                        Label("Options", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
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

                        Button {
                            exportToCSV()
                        } label: {
                            Label("Export to CSV", systemImage: "square.and.arrow.up")
                        }

                        Divider()

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

                        Button {
                            showingJSONImport = true
                        } label: {
                            Label("Import JSON File", systemImage: "doc.badge.plus")
                        }

                        Divider()

                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    } label: {
                        Label(bookStore.userName, systemImage: "person.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            showGridView.toggle()
                        }
                    } label: {
                        Image(systemName: showGridView ? "list.bullet" : "square.grid.2x2")
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
                            showingQuickScan = true
                        } label: {
                            Label("Quick Scan (Multiple)", systemImage: "barcode")
                        }

                        Button {
                            manualISBN = ""
                            showingManualEntry = true
                        } label: {
                            Label("Enter ISBN", systemImage: "keyboard")
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
            .fullScreenCover(isPresented: $showingQuickScan) {
                BarcodeScannerView(scannedCode: .constant(nil), quickScanMode: true)
            }
            .onChange(of: scannedISBN) { _, newValue in
                if let isbn = newValue {
                    scannedISBN = nil
                    isLookingUpScanned = true
                    // Lookup book info before showing the sheet
                    Task {
                        var book = Book(isbn: isbn)
                        // Try to lookup book info
                        if let foundBook = try? await OpenLibraryService.shared.lookupBook(isbn: isbn) {
                            book.title = foundBook.title
                            book.authors = foundBook.authors
                            book.publisher = foundBook.publisher
                            book.publishDate = foundBook.publishDate
                            book.numberOfPages = foundBook.numberOfPages
                            book.coverURL = foundBook.coverURL
                        }
                        isLookingUpScanned = false
                        bookToAdd = book
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
            .sheet(isPresented: $showingJSONImport) {
                JSONImportView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
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
            } else if isLookingUpScanned {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Looking up scanned book...")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func exportToCSV() {
        var csv = "Title,Authors,ISBN,Publisher,Published,Pages,Notes,Added By,Reading Status,Wishlist,Copies\n"

        for book in bookStore.books {
            let title = book.title.replacingOccurrences(of: "\"", with: "\"\"")
            let authors = book.authors.replacingOccurrences(of: "\"", with: "\"\"")
            let notes = book.notes.replacingOccurrences(of: "\"", with: "\"\"")

            csv += "\"\(title)\",\"\(authors)\",\"\(book.isbn)\",\"\(book.publisher)\",\"\(book.publishDate)\",\"\(book.numberOfPages)\",\"\(notes)\",\"\(book.addedBy)\",\"\(book.readingStatus.rawValue)\",\"\(book.isWishlist)\",\"\(book.copies)\"\n"
        }

        let activityVC = UIActivityViewController(
            activityItems: [csv],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
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

            VStack(spacing: 4) {
                if book.readingStatus != .none {
                    Image(systemName: book.readingStatus.icon)
                        .font(.caption)
                        .foregroundStyle(book.readingStatus == .read ? .green : .blue)
                }

                if book.format != .physical {
                    Image(systemName: book.format.icon)
                        .font(.caption)
                        .foregroundStyle(book.format == .ebook ? .blue : .purple)
                }

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
        }
        .padding(.vertical, 4)
    }
}

struct BookGridItem: View {
    let book: Book

    var formatColor: Color {
        switch book.format {
        case .physical: return .brown
        case .ebook: return .blue
        case .audiobook: return .purple
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                AsyncImage(url: URL(string: book.coverURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.gray.opacity(0.15)
                        Image(systemName: "book.closed.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                // Reading status badge (top right)
                if book.readingStatus != .none {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: book.readingStatus.icon)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(book.readingStatus == .read ? Color.green : Color.blue)
                                .clipShape(Circle())
                                .offset(x: 6, y: -6)
                        }
                        Spacer()
                    }
                }

                // Format badge (bottom left)
                if book.format != .physical {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: book.format.icon)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(formatColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .offset(x: -4, y: 4)
                            Spacer()
                        }
                    }
                }
            }
            .frame(width: 100, height: 150)

            Text(book.title.isEmpty ? "Unknown" : book.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            if !book.authors.isEmpty {
                Text(book.authors)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 100)
    }
}

#Preview {
    BookListView()
        .environmentObject(BookStore())
}
