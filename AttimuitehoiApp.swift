import SwiftUI

#if os(macOS)
@main
struct AttimuitehoiApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
#else
@main
struct AttimuitehoiApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
#endif
