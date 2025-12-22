import Foundation

class GoogleSheetsService {
    // CONFIGURE THESE VALUES
    private static let defaultApiKey = "AIzaSyDYaCJGAUrZyrqaDEMKCSVa3BgQNapZfV0"
    private static let defaultSpreadsheetId = "189Iwq3CGmFcNQjqhExXGh2XAMOJyHY4oklUMa5QUdWU"

    static var currentSpreadsheetId: String { defaultSpreadsheetId }

    private let apiKey: String
    private let spreadsheetId: String
    private let sheetName: String

    private let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"

    init(spreadsheetId: String? = nil, apiKey: String? = nil, sheetName: String = "Books") {
        self.spreadsheetId = spreadsheetId ?? Self.defaultSpreadsheetId
        self.apiKey = apiKey ?? Self.defaultApiKey
        self.sheetName = sheetName
    }

    func fetchBooks() async throws -> [Book] {
        // Fetch all data including header row
        let range = "\(sheetName)!A1:Z"
        let urlString = "\(baseURL)/\(spreadsheetId)/values/\(range)?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SheetResponse.self, from: data)

        guard let values = response.values, values.count > 1 else {
            return []
        }

        // First row is headers
        let headers = values[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let dataRows = Array(values.dropFirst())

        // Map column names to indices
        let columnMap = ColumnMap(headers: headers)

        let dateFormatter = ISO8601DateFormatter()

        return dataRows.compactMap { row -> Book? in
            let isbn = columnMap.value(from: row, for: .isbn)
            guard !isbn.isEmpty else { return nil }

            let addedAtString = columnMap.value(from: row, for: .addedAt)
            let addedAt = dateFormatter.date(from: addedAtString) ?? Date()

            return Book(
                isbn: isbn,
                title: columnMap.value(from: row, for: .title),
                authors: columnMap.value(from: row, for: .authors),
                publisher: columnMap.value(from: row, for: .publisher),
                publishDate: columnMap.value(from: row, for: .publishDate),
                numberOfPages: columnMap.value(from: row, for: .numberOfPages),
                coverURL: columnMap.value(from: row, for: .coverURL),
                notes: columnMap.value(from: row, for: .notes),
                addedBy: columnMap.value(from: row, for: .addedBy),
                addedAt: addedAt
            )
        }
    }

    private struct ColumnMap {
        enum Column: CaseIterable {
            case isbn, title, authors, publisher, publishDate, numberOfPages, coverURL, notes, addedBy, addedAt

            var possibleNames: [String] {
                switch self {
                case .isbn: return ["isbn", "isbn-13", "isbn-10", "isbn13", "isbn10", "barcode"]
                case .title: return ["title", "book title", "name", "book name", "book"]
                case .authors: return ["authors", "author", "by", "written by", "writer"]
                case .publisher: return ["publisher", "published by", "pub"]
                case .publishDate: return ["publish date", "published", "date published", "publication date", "year", "pub date"]
                case .numberOfPages: return ["pages", "number of pages", "page count", "# pages", "numofpages"]
                case .coverURL: return ["cover", "cover url", "cover image", "image", "thumbnail", "coverurl"]
                case .notes: return ["notes", "note", "comments", "description", "memo"]
                case .addedBy: return ["added by", "addedby", "added_by", "user", "owner", "who added", "contributor"]
                case .addedAt: return ["added at", "addedat", "added_at", "date added", "added", "created", "timestamp"]
                }
            }
        }

        private var indices: [Column: Int] = [:]

        init(headers: [String]) {
            for column in Column.allCases {
                for name in column.possibleNames {
                    if let index = headers.firstIndex(of: name) {
                        indices[column] = index
                        break
                    }
                }
            }
        }

        func value(from row: [String], for column: Column) -> String {
            guard let index = indices[column], index < row.count else {
                return ""
            }
            return row[index]
        }
    }

    func addBook(_ book: Book) async throws {
        let range = "\(sheetName)!A:J"
        let urlString = "\(baseURL)/\(spreadsheetId)/values/\(range):append?valueInputOption=USER_ENTERED&key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let dateFormatter = ISO8601DateFormatter()
        let values: [[String]] = [[
            book.isbn,
            book.title,
            book.authors,
            book.publisher,
            book.publishDate,
            book.numberOfPages,
            book.coverURL,
            book.notes,
            book.addedBy,
            dateFormatter.string(from: book.addedAt)
        ]]

        let body = ["values": values]
        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    func deleteBook(_ book: Book) async throws {
        // Fetch all books, filter out the one to delete, clear sheet, rewrite
        var allBooks = try await fetchBooks()
        allBooks.removeAll { $0.isbn == book.isbn }

        // Clear existing data
        let clearRange = "\(sheetName)!A2:J"
        let clearURL = "\(baseURL)/\(spreadsheetId)/values/\(clearRange):clear?key=\(apiKey)"

        guard let url = URL(string: clearURL) else {
            throw URLError(.badURL)
        }

        var clearRequest = URLRequest(url: url)
        clearRequest.httpMethod = "POST"
        let (_, _) = try await URLSession.shared.data(for: clearRequest)

        // Rewrite remaining books
        for remainingBook in allBooks {
            try await addBook(remainingBook)
        }
    }
}

struct SheetResponse: Codable {
    let values: [[String]]?
}
