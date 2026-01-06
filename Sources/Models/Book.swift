import Foundation

enum ReadingStatus: String, Codable, CaseIterable {
    case none = ""
    case wantToRead = "Want to Read"
    case reading = "Reading"
    case read = "Read"

    var icon: String {
        switch self {
        case .none: return ""
        case .wantToRead: return "bookmark"
        case .reading: return "book"
        case .read: return "checkmark.circle"
        }
    }
}

struct Book: Identifiable, Codable {
    var id: String?
    var isbn: String
    var title: String
    var authors: String
    var publisher: String
    var publishDate: String
    var numberOfPages: String
    var coverURL: String
    var notes: String
    var addedBy: String
    var addedAt: Date
    var copies: Int
    var readingStatus: ReadingStatus
    var isWishlist: Bool

    init(
        id: String? = nil,
        isbn: String,
        title: String = "",
        authors: String = "",
        publisher: String = "",
        publishDate: String = "",
        numberOfPages: String = "",
        coverURL: String = "",
        notes: String = "",
        addedBy: String = "",
        addedAt: Date = Date(),
        copies: Int = 1,
        readingStatus: ReadingStatus = .none,
        isWishlist: Bool = false
    ) {
        self.id = id ?? isbn
        self.isbn = isbn
        self.title = title
        self.authors = authors
        self.publisher = publisher
        self.publishDate = publishDate
        self.numberOfPages = numberOfPages
        self.coverURL = coverURL
        self.notes = notes
        self.addedBy = addedBy
        self.addedAt = addedAt
        self.copies = copies
        self.readingStatus = readingStatus
        self.isWishlist = isWishlist
    }
}
