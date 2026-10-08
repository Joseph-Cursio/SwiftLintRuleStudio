//
//  YAMLScalarTagTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  How a scalar's YAML tag and style decide its parsed type. An explicit core
//  tag decides. Without one, only a plain scalar is resolved implicitly, and a
//  quoted scalar is a string.
//
//  The value used to override the YAML in three ways:
//  - `!hint "5"` was read as the number 5, because the tag checks were
//    `tag.contains("int") || …` and matched any local tag containing the word;
//  - a quoted `"true"` was read as a Bool, because the bool check fell back to
//    the value whatever the tag;
//  - `!!str 5` was read as the number 5, because the plain-scalar fallback
//    ignored the explicit tag.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing
import Yams

struct YAMLScalarTagTests {

    private static func parsed(_ yaml: String) throws -> [String: Any] {
        let node = try Yams.compose(yaml: yaml)
        return try YAMLConfigurationEngine.nodeToDictionary(try #require(node))
    }

    @Test("an explicit core tag decides the type, whatever the style")
    func coreTagsDecide() throws {
        let values = try Self.parsed("""
            counted: !!int "5"
            scaled: !!float "2.5"
            flag: !!bool "true"
            named: !!str 5
            word: !!str true
            """)
        #expect(values["counted"] as? Int == 5)
        #expect(values["scaled"] as? Double == 2.5)
        #expect(values["flag"] as? Bool == true)
        #expect(values["named"] as? String == "5")
        #expect(values["word"] as? String == "true")
    }

    @Test("a quoted scalar is a string, however it reads")
    func quotedIsString() throws {
        let values = try Self.parsed("""
            double: "true"
            single: 'false'
            number: "120"
            ratio: '0.5'
            """)
        #expect(values["double"] as? String == "true")
        #expect(values["single"] as? String == "false")
        #expect(values["number"] as? String == "120")
        #expect(values["ratio"] as? String == "0.5")
    }

    @Test("a local tag decides nothing: plain resolves implicitly, quoted stays a string")
    func localTags() throws {
        let values = try Self.parsed("""
            plain: !hint 5
            quoted: !hint "5"
            word: !point x
            """)
        #expect(values["plain"] as? Int == 5)
        #expect(values["quoted"] as? String == "5")
        #expect(values["word"] as? String == "x")
    }

    @Test("a plain untagged scalar resolves implicitly: bool, then integer, then float")
    func plainScalars() throws {
        let values = try Self.parsed("""
            limit: 120
            ratio: 0.5
            on: true
            off: false
            name: xcode
            """)
        #expect(values["limit"] as? Int == 120)
        #expect(values["ratio"] as? Double == 0.5)
        #expect(values["on"] as? Bool == true)
        #expect(values["off"] as? Bool == false)
        #expect(values["name"] as? String == "xcode")
    }

    /// A string that reads like a bool or a number must come back a string. The serializer quotes
    /// it, and that holds only if the parser honours the quotes.
    @Test("parsing, saving and parsing again keeps each value's type")
    @MainActor
    func roundTripKeepsTypes() throws {
        let yaml = """
            line_length:
              ignores_comments: "true"
              label: !!str 5
              plain_flag: true
              warning: 120
            """
        let once = try YAMLConfigurationEngine.parse(yaml)
        let twice = try YAMLConfigurationEngine.parse(try YAMLConfigurationEngine.serialize(once))
        let parameters = try #require(twice.rules["line_length"]?.parameters)
        #expect(parameters["ignores_comments"]?.value as? String == "true")
        #expect(parameters["label"]?.value as? String == "5")
        #expect(parameters["plain_flag"]?.value as? Bool == true)
        #expect(parameters["warning"]?.value as? Int == 120)
    }
}
