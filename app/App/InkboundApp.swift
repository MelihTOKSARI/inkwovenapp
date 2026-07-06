import SwiftUI

@main
struct InkboundApp: App {
    @State private var di = AppDI.live()

    var body: some Scene {
        WindowGroup {
            // Placeholder shell: proves the write → rest → absorb → answer
            // loop end-to-end on device. The Claude Design screens replace
            // this view tree; they bind to the same DI container.
            PageHarnessView(di: di)
        }
    }
}
