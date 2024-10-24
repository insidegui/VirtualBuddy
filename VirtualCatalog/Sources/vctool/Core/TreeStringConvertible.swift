import Foundation

protocol TreeStringConvertible: CustomStringConvertible {
    func description(level: Int) -> String
}

extension TreeStringConvertible {
    func indentation(for level: Int) -> String { String(repeating: " ", count: level * 2) }

    func description(level: Int) -> String {
        let prefix = indentation(for: level)

        let mirror = Mirror(reflecting: self)

        var output = [String]()

        for child in mirror.children {
            let name = "- " + (child.label ?? "???")
            let item: String

            if let convertibleChild = child.value as? TreeStringConvertible {
                let childDescription = convertibleChild.description(level: level + 1)

                if childDescription.contains("\n") {
                    output.append(prefix + name)
                    item = childDescription
                } else {
                    item = prefix + "\(name) = \(childDescription)"
                }
            } else {
                let value = String(describing: child.value)
                item = prefix + "\(name) = \(value)"
            }

            output.append(item)
        }

        return output.joined(separator: "\n")
    }

    var description: String { description(level: 0) }
}

extension Array: TreeStringConvertible {
    func description(level: Int) -> String {
        let prefix = indentation(for: level)
        return enumerated().map {
            let elementPrefix = prefix + "- [\($0.offset)] "

            if let convertibleElement = $0.element as? TreeStringConvertible {
                return elementPrefix + "\n" + convertibleElement.description(level: level + 1)
            } else {
                return elementPrefix + String(describing: $0.element)
            }
        }.joined(separator: "\n")
    }
}

extension Optional: @retroactive CustomStringConvertible {}

extension Optional: TreeStringConvertible {
    func description(level: Int) -> String {
        switch self {
        case .none:
            return "<nil>"
        case .some(let value):
            if let convertibleValue = value as? TreeStringConvertible {
                return convertibleValue.description(level: level + 1)
            } else {
                return String(describing: value)
            }
        }
    }

    public var description: String { description(level: 0) }
}
