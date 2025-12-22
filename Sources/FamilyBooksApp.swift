import SwiftUI

@main
struct FamilyBooksApp: App {
    @StateObject private var bookStore = BookStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bookStore)
        }
    }
}
