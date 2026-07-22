import SweepCore
import SwiftUI
import WidgetKit

@main
struct SweepWidgetBundle: WidgetBundle {
    init() {
        // Widgets render in their own process — adopt the chosen theme.
        Tokens.loadTheme(from: PersistenceStore.appGroup())
    }

    var body: some Widget {
        SweepWidget()
        SweepLiveActivity()
    }
}
