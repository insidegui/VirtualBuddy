//
//  RandomNameGenerator.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 19/07/22.
//

import Foundation

public final class RandomNameGenerator {

    public static let shared = RandomNameGenerator()

    private var adjectives = [String]()
    private var animals = [String]()

    private init() {
        guard let animalsData = NSDataAsset(name: "Animals", bundle: .virtualCore)?.data,
              let adjectivesData = NSDataAsset(name: "Adjectives", bundle: .virtualCore)?.data
        else {
            assertionFailure("Couldn't load random name generator asssets")
            return
        }

        adjectives = String(decoding: adjectivesData, as: UTF8.self).components(separatedBy: .newlines)
        animals = String(decoding: animalsData, as: UTF8.self).components(separatedBy: .newlines)
    }

    public func newName() -> String {
        guard !adjectives.isEmpty, !animals.isEmpty else {
            return UUID().uuidString
        }

        let adjective = adjectives.shuffled()[0]
        let animal = animals.shuffled()[0]

        return adjective + " " + animal
    }

}
