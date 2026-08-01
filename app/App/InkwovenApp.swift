import SwiftUI

@main
struct InkwovenApp: App {
    @State private var di = AppDI.live()

    var body: some Scene {
        WindowGroup {
            RootView(di: di)
        }
    }
}
