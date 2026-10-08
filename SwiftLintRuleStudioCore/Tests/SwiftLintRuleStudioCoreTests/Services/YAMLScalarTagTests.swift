//
//  YAMLScalarTagTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  How a scalar's YAML tag decides its parsed type. The checks used to be
//  `tag.contains("int") || tag.contains("tag:yaml.org,2002:int")`. The second
//  test implied the first, which SwiftProjectLint's Subsumed Condition reported,
//  and the first matched any local tag containing the word, so `!hint "5"` was
//  read as the number 5. They now compare the whole tag.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing
import Yams

struct YAMLScalarTagTests {

    @Test("a core tag is recognised whole, and a local tag that merely contains its name is not", arguments: [
        ("tag:yaml.org,2002:int", true, false, false),
        ("tag:yaml.org,2002:float", false, true, false),
        ("tag:yaml.org,2002:bool", false, false, true),
        ("!hint", false, false, false),
        ("!point", false, false, false),
        ("!floaty", false, false, false),
        ("!boolean", false, false, false),
        ("", false, false, false)
    ])
    func tagChecks(tag: String, isInt: Bool, isFloat: Bool, isBool: Bool) {
        #expect(YAMLConfigurationEngine.isIntScalar(tagDescription: tag) == isInt)
        #expect(YAMLConfigurationEngine.isFloatScalar(tagDescription: tag) == isFloat)
        #expect(YAMLConfigurationEngine.isBoolScalar(tagDescription: tag, stringValue: "x") == isBool)
    }

    @Test("an explicit core tag converts a quoted scalar; a local tag leaves it a string")
    func taggedQuotedScalars() throws {
        let yaml = """
            counted: !!int "5"
            scaled: !!float "2.5"
            local: !hint "5"
            """
        let node = try Yams.compose(yaml: yaml)
        let dictionary = try YAMLConfigurationEngine.nodeToDictionary(try #require(node))
        #expect(dictionary["counted"] as? Int == 5)
        #expect(dictionary["scaled"] as? Double == 2.5)
        #expect(dictionary["local"] as? String == "5")
    }

    @Test("a plain untagged scalar still resolves implicitly")
    func plainScalars() throws {
        let yaml = """
            limit: 120
            ratio: 0.5
            on: true
            """
        let node = try Yams.compose(yaml: yaml)
        let dictionary = try YAMLConfigurationEngine.nodeToDictionary(try #require(node))
        #expect(dictionary["limit"] as? Int == 120)
        #expect(dictionary["ratio"] as? Double == 0.5)
        #expect(dictionary["on"] as? Bool == true)
    }
}
