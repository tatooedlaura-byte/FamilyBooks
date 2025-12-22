import Foundation

class OpenLibraryService {
    func lookupBook(isbn: String) async throws -> Book? {
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
}
