import Foundation

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

    let firebaseService = FirebaseService.shared

    init() {
        self.userName = UserDefaults.standard.string(forKey: "userName") ?? ""
        setupObserver()
    }

    private func setupObserver() {
        firebaseService.observeBooks { [weak self] books in
            Task { @MainActor in
                self?.books = books.sorted { $0.title.lowercased() < $1.title.lowercased() }
                self?.isLoading = false
            }
        }
    }

    func loadBooks() async {
        isLoading = true
        error = nil

        do {
            books = try await firebaseService.fetchBooks()
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
            try await firebaseService.addBook(bookToAdd)
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func addBooks(_ books: [Book]) async throws {
        try await firebaseService.addBooks(books)
    }

    func deleteBook(_ book: Book) async -> Bool {
        isLoading = true
        error = nil

        do {
            try await firebaseService.deleteBook(book)
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func updateBook(_ book: Book) async -> Bool {
        do {
            try await firebaseService.updateBook(book)
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

        // Only update fields that are empty or if we found better data
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
}
