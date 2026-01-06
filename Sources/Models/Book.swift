import Foundation

struct Book: Identifiable, Codable {
    var id: String?
    let isbn: String
    var title: String
    var authors: String
    var publisher: String
    var publishDate: String
    var numberOfPages: String
    var coverURL: String
    var notes: String
    var addedBy: String
    var addedAt: Date

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
        addedAt: Date = Date()
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
    }
}
