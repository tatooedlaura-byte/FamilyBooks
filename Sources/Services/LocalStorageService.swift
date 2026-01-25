import Foundation

class LocalStorageService {
    static let shared = LocalStorageService()

    private let fileManager = FileManager.default
    private let fileName = "books.json"

    private var booksFileURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent(fileName)
    }

    func fetchBooks() throws -> [Book] {
        guard fileManager.fileExists(atPath: booksFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: booksFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode([Book].self, from: data)
    }

    func saveBooks(_ books: [Book]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(books)
        try data.write(to: booksFileURL)
    }

    func addBook(_ book: Book) throws {
        var books = try fetchBooks()
        books.append(book)
        try saveBooks(books)
    }

    func addBooks(_ newBooks: [Book]) throws {
        var books = try fetchBooks()
        books.append(contentsOf: newBooks)
        try saveBooks(books)
    }

    func deleteBook(_ book: Book) throws {
        var books = try fetchBooks()
        books.removeAll { $0.isbn == book.isbn }
        try saveBooks(books)
    }

    func updateBook(_ book: Book) throws {
        var books = try fetchBooks()
        if let index = books.firstIndex(where: { $0.isbn == book.isbn }) {
            books[index] = book
        }
        try saveBooks(books)
    }
}
