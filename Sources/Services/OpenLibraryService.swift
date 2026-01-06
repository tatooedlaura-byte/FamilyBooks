import Foundation

class OpenLibraryService {
    static let shared = OpenLibraryService()

    struct BookInfo {
        var isbn: String
        var title: String
        var authors: String
        var publisher: String
        var publishDate: String
        var numberOfPages: String
        var coverURL: String
    }

    func searchBook(title: String, author: String) async throws -> BookInfo? {
        // Build search query
        var queryItems: [String] = []

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanTitle.isEmpty {
            if let encoded = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                queryItems.append("title=\(encoded)")
            }
        }

        if !cleanAuthor.isEmpty {
            if let encoded = cleanAuthor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                queryItems.append("author=\(encoded)")
            }
        }

        guard !queryItems.isEmpty else { return nil }

        let urlString = "https://openlibrary.org/search.json?\(queryItems.joined(separator: "&"))&limit=1"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = json["docs"] as? [[String: Any]],
              let firstDoc = docs.first else {
            return nil
        }

        // Extract ISBN
        var isbn = ""
        if let isbns = firstDoc["isbn"] as? [String], let firstISBN = isbns.first {
            isbn = firstISBN
        }

        // Extract cover
        var coverURL = ""
        if let coverID = firstDoc["cover_i"] as? Int {
            coverURL = "https://covers.openlibrary.org/b/id/\(coverID)-M.jpg"
        }

        // Extract other fields
        let foundTitle = firstDoc["title"] as? String ?? ""
        let foundAuthors = (firstDoc["author_name"] as? [String])?.joined(separator: ", ") ?? ""
        let publisher = (firstDoc["publisher"] as? [String])?.first ?? ""
        let publishYear = (firstDoc["first_publish_year"] as? Int).map { String($0) } ?? ""
        let pages = (firstDoc["number_of_pages_median"] as? Int).map { String($0) } ?? ""

        return BookInfo(
            isbn: isbn,
            title: foundTitle,
            authors: foundAuthors,
            publisher: publisher,
            publishDate: publishYear,
            numberOfPages: pages,
            coverURL: coverURL
        )
    }

    func lookupBook(isbn: String) async throws -> Book? {
        // Try direct ISBN lookup first
        if let book = try await directISBNLookup(isbn: isbn) {
            return book
        }

        // Fallback to search by ISBN
        if let info = try await searchByISBN(isbn: isbn) {
            return Book(
                isbn: isbn,
                title: info.title,
                authors: info.authors,
                publisher: info.publisher,
                publishDate: info.publishDate,
                numberOfPages: info.numberOfPages,
                coverURL: info.coverURL
            )
        }

        return nil
    }

    private func directISBNLookup(isbn: String) async throws -> Book? {
        let urlString = "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bookData = json["ISBN:\(isbn)"] as? [String: Any] else {
            return nil
        }

        let title = bookData["title"] as? String ?? ""
        guard !title.isEmpty else { return nil }

        var authors = ""
        if let authorList = bookData["authors"] as? [[String: Any]] {
            authors = authorList.compactMap { $0["name"] as? String }.joined(separator: ", ")
        }

        var publisher = ""
        if let publisherList = bookData["publishers"] as? [[String: Any]],
           let firstPublisher = publisherList.first {
            publisher = firstPublisher["name"] as? String ?? ""
        }

        let publishDate = bookData["publish_date"] as? String ?? ""
        let numberOfPages = (bookData["number_of_pages"] as? Int).map { String($0) } ?? ""

        var coverURL = ""
        if let cover = bookData["cover"] as? [String: Any] {
            coverURL = cover["medium"] as? String ?? cover["small"] as? String ?? ""
        }

        return Book(
            isbn: isbn,
            title: title,
            authors: authors,
            publisher: publisher,
            publishDate: publishDate,
            numberOfPages: numberOfPages,
            coverURL: coverURL
        )
    }

    private func searchByISBN(isbn: String) async throws -> BookInfo? {
        let urlString = "https://openlibrary.org/search.json?isbn=\(isbn)&limit=1"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = json["docs"] as? [[String: Any]],
              let firstDoc = docs.first else {
            return nil
        }

        let title = firstDoc["title"] as? String ?? ""
        guard !title.isEmpty else { return nil }

        var coverURL = ""
        if let coverID = firstDoc["cover_i"] as? Int {
            coverURL = "https://covers.openlibrary.org/b/id/\(coverID)-M.jpg"
        }

        let authors = (firstDoc["author_name"] as? [String])?.joined(separator: ", ") ?? ""
        let publisher = (firstDoc["publisher"] as? [String])?.first ?? ""
        let publishYear = (firstDoc["first_publish_year"] as? Int).map { String($0) } ?? ""
        let pages = (firstDoc["number_of_pages_median"] as? Int).map { String($0) } ?? ""

        return BookInfo(
            isbn: isbn,
            title: title,
            authors: authors,
            publisher: publisher,
            publishDate: publishYear,
            numberOfPages: pages,
            coverURL: coverURL
        )
    }
}
