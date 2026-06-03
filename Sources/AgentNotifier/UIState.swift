import Foundation
import Combine

/// Small persisted UI state shared between the panel view and its controller.
final class UIState: ObservableObject {
    @Published var collapsed: Bool {
        didSet { UserDefaults.standard.set(collapsed, forKey: Self.key) }
    }

    private static let key = "panelCollapsed"

    init() {
        collapsed = UserDefaults.standard.bool(forKey: Self.key)
    }

    func toggle() { collapsed.toggle() }
}
