//
//  RuleParameterValuesTests.swift
//  SwiftLintRuleStudioCoreTests
//
//  Tests for the typed parameter value resolver. Each test asserts a single
//  branch of the fallback chain (stored → default → zero) so any regression
//  in the resolver produces a focused failure.
//

import Foundation
@testable import SwiftLintRuleStudioCore
import Testing

@Suite("RuleParameterValues")
struct RuleParameterValuesTests {

    // MARK: - intValue

    @Test("intValue returns stored Int when present and correctly typed")
    func intValueReturnsStored() {
        let param = RuleParameter(name: "max", type: .integer, defaultValue: AnyCodable(80))
        let resolver = RuleParameterValues(values: ["max": AnyCodable(120)])
        #expect(resolver.intValue(for: param) == 120)
    }

    @Test("intValue falls back to default when stored value is wrong type")
    func intValueFallsBackOnWrongStoredType() {
        let param = RuleParameter(name: "max", type: .integer, defaultValue: AnyCodable(80))
        let resolver = RuleParameterValues(values: ["max": AnyCodable("not an int")])
        #expect(resolver.intValue(for: param) == 80)
    }

    @Test("intValue falls back to default when value is absent")
    func intValueFallsBackOnAbsent() {
        let param = RuleParameter(name: "max", type: .integer, defaultValue: AnyCodable(80))
        let resolver = RuleParameterValues()
        #expect(resolver.intValue(for: param) == 80)
    }

    @Test("intValue returns 0 when default is wrong type and value is absent")
    func intValueReturnsZeroWhenDefaultWrongType() {
        let param = RuleParameter(name: "max", type: .integer, defaultValue: AnyCodable("not an int"))
        let resolver = RuleParameterValues()
        #expect(resolver.intValue(for: param) == 0)
    }

    // MARK: - boolValue

    @Test("boolValue returns stored Bool when present and correctly typed")
    func boolValueReturnsStored() {
        let param = RuleParameter(name: "strict", type: .boolean, defaultValue: AnyCodable(false))
        let resolver = RuleParameterValues(values: ["strict": AnyCodable(true)])
        #expect(resolver.boolValue(for: param) == true)
    }

    @Test("boolValue falls back to default when stored value is wrong type")
    func boolValueFallsBackOnWrongStoredType() {
        let param = RuleParameter(name: "strict", type: .boolean, defaultValue: AnyCodable(true))
        let resolver = RuleParameterValues(values: ["strict": AnyCodable("yes")])
        #expect(resolver.boolValue(for: param) == true)
    }

    @Test("boolValue falls back to default when value is absent")
    func boolValueFallsBackOnAbsent() {
        let param = RuleParameter(name: "strict", type: .boolean, defaultValue: AnyCodable(true))
        let resolver = RuleParameterValues()
        #expect(resolver.boolValue(for: param) == true)
    }

    @Test("boolValue returns false when default is wrong type and value is absent")
    func boolValueReturnsFalseWhenDefaultWrongType() {
        let param = RuleParameter(name: "strict", type: .boolean, defaultValue: AnyCodable(1))
        let resolver = RuleParameterValues()
        #expect(resolver.boolValue(for: param) == false)
    }

    // MARK: - stringValue

    @Test("stringValue returns stored String when present and correctly typed")
    func stringValueReturnsStored() {
        let param = RuleParameter(name: "label", type: .string, defaultValue: AnyCodable("default"))
        let resolver = RuleParameterValues(values: ["label": AnyCodable("custom")])
        #expect(resolver.stringValue(for: param) == "custom")
    }

    @Test("stringValue falls back to default when stored value is wrong type")
    func stringValueFallsBackOnWrongStoredType() {
        let param = RuleParameter(name: "label", type: .string, defaultValue: AnyCodable("default"))
        let resolver = RuleParameterValues(values: ["label": AnyCodable(42)])
        #expect(resolver.stringValue(for: param) == "default")
    }

    @Test("stringValue falls back to default when value is absent")
    func stringValueFallsBackOnAbsent() {
        let param = RuleParameter(name: "label", type: .string, defaultValue: AnyCodable("default"))
        let resolver = RuleParameterValues()
        #expect(resolver.stringValue(for: param) == "default")
    }

    @Test("stringValue returns empty when default is wrong type and value is absent")
    func stringValueReturnsEmptyWhenDefaultWrongType() {
        let param = RuleParameter(name: "label", type: .string, defaultValue: AnyCodable(42))
        let resolver = RuleParameterValues()
        #expect(resolver.stringValue(for: param).isEmpty)
    }

    // MARK: - arrayValue

    @Test("arrayValue returns stored [String] when present")
    func arrayValueReturnsStoredStringArray() {
        let param = RuleParameter(name: "items", type: .array, defaultValue: AnyCodable([String]()))
        let resolver = RuleParameterValues(values: ["items": AnyCodable(["alpha", "beta"])])
        #expect(resolver.arrayValue(for: param) == ["alpha", "beta"])
    }

    @Test("arrayValue converts heterogeneous stored array via String(describing:)")
    func arrayValueConvertsMixedStored() {
        let mixed: [Any] = ["one", 2, true]
        let param = RuleParameter(name: "items", type: .array, defaultValue: AnyCodable([String]()))
        let resolver = RuleParameterValues(values: ["items": AnyCodable(mixed)])
        #expect(resolver.arrayValue(for: param) == ["one", "2", "true"])
    }

    @Test("arrayValue falls back to default array when value is absent")
    func arrayValueFallsBackToDefault() {
        let param = RuleParameter(name: "items", type: .array, defaultValue: AnyCodable(["only"]))
        let resolver = RuleParameterValues()
        #expect(resolver.arrayValue(for: param) == ["only"])
    }

    @Test("arrayValue converts non-String default elements via String(describing:)")
    func arrayValueConvertsNonStringDefault() {
        // Defaults declared as [Int] surface through AnyCodable as [Any]; the
        // resolver must stringify them for the editor's text-based array UI.
        let intDefault: [Any] = [1, 2, 3]
        let param = RuleParameter(name: "items", type: .array, defaultValue: AnyCodable(intDefault))
        let resolver = RuleParameterValues()
        #expect(resolver.arrayValue(for: param) == ["1", "2", "3"])
    }

    @Test("arrayValue returns empty when neither stored nor default is an array")
    func arrayValueReturnsEmptyWhenNoArray() {
        let param = RuleParameter(name: "items", type: .array, defaultValue: AnyCodable("not an array"))
        let resolver = RuleParameterValues()
        #expect(resolver.arrayValue(for: param).isEmpty)
    }

    @Test("arrayValue prefers stored value over default when both are present")
    func arrayValuePrefersStoredOverDefault() {
        let param = RuleParameter(name: "items", type: .array, defaultValue: AnyCodable(["default"]))
        let resolver = RuleParameterValues(values: ["items": AnyCodable(["stored"])])
        #expect(resolver.arrayValue(for: param) == ["stored"])
    }

    // MARK: - setValue

    @Test("setValue stores Int and is observable via subsequent intValue read")
    func setValueRoundTripsInt() {
        let param = RuleParameter(name: "max", type: .integer, defaultValue: AnyCodable(0))
        var resolver = RuleParameterValues()
        resolver.setValue(99, for: param)
        #expect(resolver.intValue(for: param) == 99)
        #expect(resolver.values["max"]?.value as? Int == 99)
    }

    @Test("setValue stores Bool and is observable via subsequent boolValue read")
    func setValueRoundTripsBool() {
        let param = RuleParameter(name: "strict", type: .boolean, defaultValue: AnyCodable(false))
        var resolver = RuleParameterValues()
        resolver.setValue(true, for: param)
        #expect(resolver.boolValue(for: param) == true)
    }

    @Test("setValue stores String and is observable via subsequent stringValue read")
    func setValueRoundTripsString() {
        let param = RuleParameter(name: "label", type: .string, defaultValue: AnyCodable(""))
        var resolver = RuleParameterValues()
        resolver.setValue("hello", for: param)
        #expect(resolver.stringValue(for: param) == "hello")
    }

    @Test("setValue stores [String] and is observable via subsequent arrayValue read")
    func setValueRoundTripsArray() {
        let param = RuleParameter(name: "items", type: .array, defaultValue: AnyCodable([String]()))
        var resolver = RuleParameterValues()
        resolver.setValue(["a", "b"], for: param)
        #expect(resolver.arrayValue(for: param) == ["a", "b"])
    }

    @Test("setValue overwrites prior value at the same key")
    func setValueOverwritesPrior() {
        let param = RuleParameter(name: "max", type: .integer, defaultValue: AnyCodable(0))
        var resolver = RuleParameterValues(values: ["max": AnyCodable(10)])
        resolver.setValue(20, for: param)
        #expect(resolver.intValue(for: param) == 20)
    }

    // MARK: - sanitizedArrayItem

    @Test("sanitizedArrayItem returns nil for empty string")
    func sanitizedArrayItemRejectsEmpty() {
        #expect(RuleParameterValues.sanitizedArrayItem("") == nil)
    }

    @Test("sanitizedArrayItem returns nil for whitespace-only string")
    func sanitizedArrayItemRejectsWhitespaceOnly() {
        #expect(RuleParameterValues.sanitizedArrayItem("   ") == nil)
        #expect(RuleParameterValues.sanitizedArrayItem("\t \t") == nil)
    }

    @Test("sanitizedArrayItem trims leading and trailing whitespace")
    func sanitizedArrayItemTrimsSurroundingWhitespace() {
        #expect(RuleParameterValues.sanitizedArrayItem("  hello  ") == "hello")
        #expect(RuleParameterValues.sanitizedArrayItem("\tfoo") == "foo")
        #expect(RuleParameterValues.sanitizedArrayItem("bar\t") == "bar")
    }

    @Test("sanitizedArrayItem passes already-clean strings through unchanged")
    func sanitizedArrayItemPassesCleanStringsThrough() {
        #expect(RuleParameterValues.sanitizedArrayItem("clean") == "clean")
        #expect(RuleParameterValues.sanitizedArrayItem("with spaces inside") == "with spaces inside")
    }
}
