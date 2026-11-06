/// Window selection rules are independent of Accessibility so they can be tested
/// against the multi-window layout captured in diagnostic logs.
enum FilePickerResolver {
    static func choose<Element>(
        candidates: [(window: Element, picker: Element)],
        focusedWindow: Element?, same: (Element, Element) -> Bool
    ) -> (window: Element, picker: Element)? {
        if let focusedWindow,
           let focused = candidates.first(where: { same($0.window, focusedWindow) }) {
            return focused
        }
        // A focused web window must not outrank the actual file picker.
        guard candidates.count == 1 else { return nil }
        return candidates[0]
    }

    static func contains<Element>(_ node: Element, root: Element,
                                  parent: (Element) -> Element?, same: (Element, Element) -> Bool) -> Bool {
        var current: Element? = node
        for _ in 0..<30 {
            guard let element = current else { return false }
            if same(element, root) { return true }
            current = parent(element)
        }
        return false
    }
}
