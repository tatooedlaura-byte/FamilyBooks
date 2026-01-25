import Foundation

enum StorageMode: String {
    case local = "local"
    case googleSheets = "googleSheets"
}

@MainActor
class BookStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var userName: String {
        didSet {
            UserDefaults.standard.set(userName, forKey: "userName")
        }
    }

    @Published var storageMode: StorageMode {
        didSet {
            UserDefaults.standard.set(storageMode.rawValue, forKey: "storageMode")
        }
    }

    private let googleSheetsService: GoogleSheetsService
    private let localStorageService = LocalStorageService.shared

    var isGoogleSheetsConfigured: Bool {
        GoogleSheetsService.isConfigured
    }

    init() {
        self.userName = UserDefaults.standard.string(forKey: "userName") ?? ""
        let savedMode = UserDefaults.standard.string(forKey: "storageMode") ?? StorageMode.local.rawValue
        self.storageMode = StorageMode(rawValue: savedMode) ?? .local
        self.googleSheetsService = GoogleSheetsService()
    }

    func loadBooks() async {
        isLoading = true
        error = nil

        do {
            switch storageMode {
            case .local:
                books = try localStorageService.fetchBooks()
            case .googleSheets:
                books = try await googleSheetsService.fetchBooks()
            }
            books.sort { $0.title.lowercased() < $1.title.lowercased() }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func addBook(_ book: Book) async -> Bool {
        isLoading = true
        error = nil

        var bookToAdd = book
        bookToAdd.addedBy = userName

        do {
            switch storageMode {
            case .local:
                try localStorageService.addBook(bookToAdd)
            case .googleSheets:
                try await googleSheetsService.addBook(bookToAdd)
            }
            await loadBooks()
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func addBooks(_ books: [Book]) async throws {
        let booksToAdd = books.map { book -> Book in
            var b = book
            b.addedBy = userName
            return b
        }

        switch storageMode {
        case .local:
            try localStorageService.addBooks(booksToAdd)
        case .googleSheets:
            try await googleSheetsService.addBooks(booksToAdd)
        }
        await loadBooks()
    }

    func deleteBook(_ book: Book) async -> Bool {
        isLoading = true
        error = nil

        do {
            switch storageMode {
            case .local:
                try localStorageService.deleteBook(book)
            case .googleSheets:
                try await googleSheetsService.deleteBook(book)
            }
            await loadBooks()
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func updateBook(_ book: Book) async -> Bool {
        do {
            switch storageMode {
            case .local:
                try localStorageService.updateBook(book)
            case .googleSheets:
                try await googleSheetsService.deleteBook(book)
                try await googleSheetsService.addBook(book)
            }
            await loadBooks()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func lookupAndUpdateBook(_ book: Book) async -> Bool {
        guard let info = try? await OpenLibraryService.shared.searchBook(title: book.title, author: book.authors) else {
            return false
        }

        var updatedBook = book

        if updatedBook.isbn.isEmpty || updatedBook.isbn.hasPrefix("imported-") {
            updatedBook.isbn = info.isbn
        }
        if updatedBook.coverURL.isEmpty && !info.coverURL.isEmpty {
            updatedBook.coverURL = info.coverURL
        }
        if updatedBook.publisher.isEmpty && !info.publisher.isEmpty {
            updatedBook.publisher = info.publisher
        }
        if updatedBook.publishDate.isEmpty && !info.publishDate.isEmpty {
            updatedBook.publishDate = info.publishDate
        }
        if updatedBook.numberOfPages.isEmpty && !info.numberOfPages.isEmpty {
            updatedBook.numberOfPages = info.numberOfPages
        }

        return await updateBook(updatedBook)
    }

    // Sync local books to Google Sheets
    func syncToGoogleSheets() async throws {
        guard isGoogleSheetsConfigured else {
            throw NSError(domain: "BookStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Google Sheets not configured"])
        }

        let localBooks = try localStorageService.fetchBooks()
        try await googleSheetsService.addBooks(localBooks)
    }

    // Import from Google Sheets to local
    func importFromGoogleSheets() async throws {
        guard isGoogleSheetsConfigured else {
            throw NSError(domain: "BookStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Google Sheets not configured"])
        }

        let sheetBooks = try await googleSheetsService.fetchBooks()
        try localStorageService.saveBooks(sheetBooks)
        await loadBooks()
    }
}
