import Foundation
import FirebaseCore
import FirebaseDatabase

class FirebaseService {
    static let shared = FirebaseService()

    private let database: Database
    private let booksRef: DatabaseReference

    private init() {
        // Configure Firebase if not already configured
        if FirebaseApp.app() == nil {
            let options = FirebaseOptions(
                googleAppID: "1:307834373790:ios:familybooks",
                gcmSenderID: "307834373790"
            )
            options.apiKey = "AIzaSyDrI3Y7IVC_H7W4iWxvOwf-bybt3SO-u_8"
            options.projectID = "familyrecipes-9809d"
            options.databaseURL = "https://familyrecipes-9809d-default-rtdb.europe-west1.firebasedatabase.app"
            FirebaseApp.configure(options: options)
        }

        database = Database.database()
        booksRef = database.reference().child("books")
    }

    func fetchBooks() async throws -> [Book] {
        return try await withCheckedThrowingContinuation { continuation in
            booksRef.observeSingleEvent(of: .value) { snapshot in
                var books: [Book] = []

                for child in snapshot.children {
                    guard let childSnapshot = child as? DataSnapshot,
                          let dict = childSnapshot.value as? [String: Any] else {
                        continue
                    }

                    let book = Book(
                        id: childSnapshot.key,
                        isbn: dict["isbn"] as? String ?? "",
                        title: dict["title"] as? String ?? "",
                        authors: dict["authors"] as? String ?? "",
                        publisher: dict["publisher"] as? String ?? "",
                        publishDate: dict["publishDate"] as? String ?? "",
                        numberOfPages: dict["numberOfPages"] as? String ?? "",
                        coverURL: dict["coverURL"] as? String ?? "",
                        notes: dict["notes"] as? String ?? "",
                        addedBy: dict["addedBy"] as? String ?? "",
                        addedAt: Date(timeIntervalSince1970: (dict["addedAt"] as? Double ?? 0) / 1000)
                    )
                    books.append(book)
                }

                continuation.resume(returning: books)
            } withCancel: { error in
                continuation.resume(throwing: error)
            }
        }
    }

    func addBook(_ book: Book) async throws {
        try await addBooks([book])
    }

    func addBooks(_ books: [Book]) async throws {
        for book in books {
            let bookData: [String: Any] = [
                "isbn": book.isbn,
                "title": book.title,
                "authors": book.authors,
                "publisher": book.publisher,
                "publishDate": book.publishDate,
                "numberOfPages": book.numberOfPages,
                "coverURL": book.coverURL,
                "notes": book.notes,
                "addedBy": book.addedBy,
                "addedAt": book.addedAt.timeIntervalSince1970 * 1000
            ]

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                booksRef.childByAutoId().setValue(bookData) { error, _ in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    func deleteBook(_ book: Book) async throws {
        guard let bookId = book.id else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            booksRef.child(bookId).removeValue { error, _ in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func observeBooks(onChange: @escaping ([Book]) -> Void) {
        booksRef.observe(.value) { snapshot in
            var books: [Book] = []

            for child in snapshot.children {
                guard let childSnapshot = child as? DataSnapshot,
                      let dict = childSnapshot.value as? [String: Any] else {
                    continue
                }

                let book = Book(
                    id: childSnapshot.key,
                    isbn: dict["isbn"] as? String ?? "",
                    title: dict["title"] as? String ?? "",
                    authors: dict["authors"] as? String ?? "",
                    publisher: dict["publisher"] as? String ?? "",
                    publishDate: dict["publishDate"] as? String ?? "",
                    numberOfPages: dict["numberOfPages"] as? String ?? "",
                    coverURL: dict["coverURL"] as? String ?? "",
                    notes: dict["notes"] as? String ?? "",
                    addedBy: dict["addedBy"] as? String ?? "",
                    addedAt: Date(timeIntervalSince1970: (dict["addedAt"] as? Double ?? 0) / 1000)
                )
                books.append(book)
            }

            onChange(books)
        }
    }
}
