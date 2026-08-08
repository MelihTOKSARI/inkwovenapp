import SwiftUI

@main
struct InkwovenApp: App {
    @State private var di: AppDI
    @State private var model: AppModel

    init() {
        // ONE composition, ONE model (audit L-17). Built here rather than in
        // RootView.init: SwiftUI re-inits a view struct freely, and every
        // spare AppModel armed commerce streams that outlived it.
        let di = AppDI.live()
        let model = AppModel(
            walletReader: di.wallet, ritual: di.ritual, ritualDiary: di.archive
        )
        // A tapped ritual night now has somewhere to walk (audit L-18).
        di.routeRitualTaps(to: model)
        _di = State(initialValue: di)
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView(di: di, model: model)
        }
    }
}
