import Foundation

extension Array where Element: Identifiable {
    func next(from selection: Element?) -> Element? {
        guard let index = self.lastIndex(where: { $0.id == selection?.id }) else {
            return nil
        }
        let nextIndex = index + 1
        guard nextIndex < count else { return nil }
        return self[nextIndex]
    }

    func previous(from selection: Element?) -> Element? {
        guard let index = self.firstIndex(where: { $0.id == selection?.id }) else {
            return nil
        }
        let previousIndex = index - 1
        guard previousIndex >= 0 else { return nil }
        return self[previousIndex]
    }
}
