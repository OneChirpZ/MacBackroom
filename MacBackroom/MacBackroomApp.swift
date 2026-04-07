import SwiftUI

@main
struct MacBackroomApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra("MacBackroom", systemImage: "rectangle.2.swap") {
            ContentView()
                .environmentObject(appModel)
        }
        .menuBarExtraStyle(.window)
    }
}
