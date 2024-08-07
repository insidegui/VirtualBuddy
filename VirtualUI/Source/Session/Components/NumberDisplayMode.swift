import SwiftUI

enum NumberDisplayMode: Int, CaseIterable {
    case hex
    case decimal

    var title: String {
        switch self {
        case .hex:
            return "Hex"
        case .decimal:
            return "Decimal"
        }
    }
}

extension EnvironmentValues {
    @Entry var numberDisplayMode: NumberDisplayMode = .decimal
}

protocol FormattableNumber: CVarArg, FixedWidthInteger {
    func formatted(mode: NumberDisplayMode) -> String
}

extension FormattableNumber where Self: SignedInteger {
    func formatted(mode: NumberDisplayMode) -> String {
        switch mode {
        case .hex:
            return String(format: "0x%02llX", Int64(self))
        case .decimal:
            return String(format: "%lld", Int64(self))
        }
    }
}

extension FormattableNumber where Self: UnsignedInteger {
    func formatted(mode: NumberDisplayMode) -> String {
        switch mode {
        case .hex:
            return String(format: "0x%02llX", UInt64(self))
        case .decimal:
            return String(format: "%llu", UInt64(self))
        }
    }
}

extension Int64: FormattableNumber { }
extension UInt64: FormattableNumber { }
extension Int32: FormattableNumber { }
extension UInt32: FormattableNumber { }
extension Int16: FormattableNumber { }
extension UInt16: FormattableNumber { }
extension Int8: FormattableNumber { }
extension UInt8: FormattableNumber { }
