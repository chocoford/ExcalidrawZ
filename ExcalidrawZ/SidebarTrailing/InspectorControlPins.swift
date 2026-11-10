import Foundation

struct InspectorControlPins: Equatable {
    enum Control: String, CaseIterable, Identifiable {
        case preference
        case search
        case library
        case history
        case presentation
        case aiChat

        var id: String { rawValue }
    }

    static let storageKey = "inspectorUnpinnedControlsData"
    static let expandedStorageKey = "inspectorUnpinnedControlsExpanded"

    private var unpinned: Set<Control>

    init(storedData: Data = Data()) {
        let ids = (try? JSONDecoder().decode([String].self, from: storedData)) ?? []
        unpinned = Set(ids.compactMap(Control.init(rawValue:)))
    }

    var storedData: Data {
        (try? JSONEncoder().encode(unpinned.map(\.rawValue).sorted())) ?? Data()
    }

    var pinnedControls: [Control] {
        Control.allCases.filter { isPinned($0) }
    }

    var unpinnedControls: [Control] {
        Control.allCases.filter { !isPinned($0) }
    }

    func visibleControls(isExpanded: Bool, presentedControls: Set<Control>) -> [Control] {
        pinnedControls + unpinnedControls.filter {
            isExpanded || presentedControls.contains($0)
        }
    }

    func isPinned(_ control: Control) -> Bool {
        !unpinned.contains(control)
    }

    mutating func setPinned(_ isPinned: Bool, for control: Control) {
        if isPinned {
            unpinned.remove(control)
        } else {
            unpinned.insert(control)
        }
    }

    mutating func setAllPinned(_ isPinned: Bool) {
        unpinned = isPinned ? [] : Set(Control.allCases)
    }
}
