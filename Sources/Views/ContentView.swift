import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bookStore: BookStore
    @State private var showingNameEntry = false

    var body: some View {
        Group {
            if bookStore.userName.isEmpty {
                NameEntryView()
            } else {
                BookListView()
            }
        }
    }
}

struct NameEntryView: View {
    @EnvironmentObject var bookStore: BookStore
    @State private var name = ""

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "books.vertical.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Family Books")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Track your family's book collection")
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                TextField("Enter your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .padding(.horizontal, 40)

                Button {
                    bookStore.userName = name
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(name.isEmpty ? Color.gray : Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(name.isEmpty)
                .padding(.horizontal, 40)
            }

            Spacer()
            Spacer()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(BookStore())
}
