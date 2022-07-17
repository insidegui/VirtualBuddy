//
//  SliderConversion.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 17/07/22.
//

import SwiftUI

extension Binding where Value: BinaryInteger {
    var sliderValue: Binding<Double> {
        .init {
            Double(wrappedValue)
        } set: { wrappedValue = Value($0) }
    }
}

extension ClosedRange where Bound: BinaryInteger {
    var sliderRange: ClosedRange<Double> {
        Double(lowerBound)...Double(upperBound)
    }
}

extension Binding where Value == UInt64 {
    var gbValue: Binding<Int> {
        .init {
            Int(wrappedValue / 1024 / 1024 / 1024)
        } set: { wrappedValue = Value($0 * 1024 * 1024 * 1024) }
    }
}
