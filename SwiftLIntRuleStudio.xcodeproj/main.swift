import SwiftUI

@main
struct AppEntryPoint: App {
    var body: some Scene {
        WindowGroup {
            // Replace `PlaceholderView()` with your app's root view if available.
            PlaceholderView()
        }
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("App Started")
                .font(.title2)
                .bold()
            Text("Replace PlaceholderView with your app's root view.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

