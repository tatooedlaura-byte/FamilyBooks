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

    let sheetsService = GoogleSheetsService()

    init() {
        self.userName = UserDefaults.standard.string(forKey: "userName") ?? ""
    }

    func loadBooks() async {
        isLoading = true
        error = nil

        do {
            books = try await sheetsService.fetchBooks()
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
            try await sheetsService.addBook(bookToAdd)
            await loadBooks()
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func deleteBook(_ book: Book) async -> Bool {
        isLoading = true
        error = nil

        do {
            try await sheetsService.deleteBook(book)
            await loadBooks()
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }
}
