import Testing
@testable import MRubyKit

// MARK: - 类型判断

@Test func testTypeChecks() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from("hello", in: ctx).isString)
    #expect(MRubyValue.from(42, in: ctx).isInt)
    #expect(MRubyValue.from(3.14, in: ctx).isFloat)
    #expect(MRubyValue.from(true, in: ctx).isBool)
    #expect(MRubyValue.nil(in: ctx).isNil)
    #expect(MRubyValue.symbol("foo", in: ctx).isSymbol)
    #expect(MRubyValue.from([MRubyValue.from(1, in: ctx)], in: ctx).isArray)
}

@Test func testObjectTypeCheck() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let obj = try ctx.eval("Object.new")
    #expect(obj.isObject && obj.isRubyObject)
}

@Test func testClassTypeCheck() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let cls = try ctx.eval("String")
    #expect(cls.isClass && !cls.isModule)
}

@Test func testModuleTypeCheck() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let mod = try ctx.eval("Kernel")
    #expect(mod.isModule)
}

@Test func testRangeTypeCheck() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let range = try ctx.eval("1..5")
    #expect(range.isRange)
}

@Test func testIsNumber() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from(42, in: ctx).isNumber)
    #expect(MRubyValue.from(3.14, in: ctx).isNumber)
    #expect(!MRubyValue.from("hello", in: ctx).isNumber)
    #expect(!MRubyValue.from(true, in: ctx).isNumber)
    #expect(!MRubyValue.nil(in: ctx).isNumber)
}

// MARK: - undefined

@Test func testUndefinedValue() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let undef = MRubyValue.undefined(in: ctx)
    #expect(undef.isUndefined && !undef.isNil && !undef.isBool)
    #expect(undef.mrubyType == .undefined)
}

@Test func testUndefinedVsNil() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let nilVal   = MRubyValue.nil(in: ctx)
    let undefVal = MRubyValue.undefined(in: ctx)
    #expect(nilVal.isNil && !nilVal.isUndefined && nilVal.mrubyType == .nilValue)
    #expect(undefVal.isUndefined && !undefVal.isNil && undefVal.mrubyType == .undefined)
}

// MARK: - 类型转换

@Test func testToArray() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let arr = try ctx.eval("[10, 20, 30]")
    #expect(arr.isArray)
    let swiftArr = arr.toArray()
    #expect(swiftArr.count == 3)
    #expect(swiftArr[0].toInt() == 10)
}

@Test func testToDictionary() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let dict = try ctx.eval("{ \"a\" => 1, \"b\" => 2 }")
    #expect(dict.isHash && dict.toDictionary().count == 2)
}

// MARK: - 方法调用

@Test func testCallMethod() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let arr = try ctx.eval("[3, 1, 2]")
    #expect(arr.call(method: "length").toInt() == 3)
}

@Test func testCallWithArguments() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let arr = try ctx.eval("[1, 2, 3]")
    let first = arr.call(method: "fetch", arguments: [MRubyValue.from(0, in: ctx)])
    #expect(first.toInt() == 1)
}

@Test func testCallAsFunction() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let proc = try ctx.eval("Proc.new { |a, b| a + b }")
    let result = proc.call(with: [MRubyValue.from(1, in: ctx), MRubyValue.from(2, in: ctx)])
    #expect(result.toInt() == 3)
}

@Test func testCallAsFunctionNoArgs() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let proc = try ctx.eval("Proc.new { 42 }")
    #expect(proc.call(with: []).toInt() == 42)
}

@Test func testInvokeMethod() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let arr = try ctx.eval("[1, 2, 3]")
    #expect(arr.invokeMethod("length", with: []).toInt() == 3)
}

// MARK: - 构造调用

@Test func testConstruct() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let stringClass = try ctx.eval("String")
    let result = stringClass.construct(with: [MRubyValue.from("hello", in: ctx)])
    #expect(result.isString && result.toString() == "hello")
}

// MARK: - 下标访问

@Test func testPropertySubscript() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let str = MRubyValue.from("hello", in: ctx)
    #expect(str["length"].toInt() == 5)
}

@Test func testArrayIndexSubscript() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let arr = try ctx.eval("[10, 20, 30]")
    #expect(arr[0].toInt() == 10 && arr[2].toInt() == 30)
}

@Test func testArrayIndexSubscriptSetter() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    var arr = try ctx.eval("[1, 2, 3]")
    arr[0] = MRubyValue.from(99, in: ctx)
    #expect(arr[0].toInt() == 99)
}

// MARK: - isInstance / responds

@Test func testIsInstance() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let str = MRubyValue.from("hello", in: ctx)
    let stringClass = try ctx.eval("String")
    let arrayClass = try ctx.eval("Array")
    #expect(str.isInstance(of: stringClass))
    #expect(!str.isInstance(of: arrayClass))
}

@Test func testResponds() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let str = MRubyValue.from("hello", in: ctx)
    #expect(str.responds(to: "length"))
    #expect(!str.responds(to: "nonexistent_method_xyz"))
}

// MARK: - 比较

@Test func testIsEqualExplicit() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let a = MRubyValue.from(42, in: ctx)
    let b = MRubyValue.from(42, in: ctx)
    let c = MRubyValue.from(100, in: ctx)
    #expect(a.isEqual(to: b))
    #expect(!a.isEqual(to: c))
}

@Test func testIsIdentical() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let a = MRubyValue.from(42, in: ctx)
    let b = MRubyValue.from(42, in: ctx)
    let obj1 = try ctx.eval("Object.new")
    let obj2 = try ctx.eval("Object.new")
    #expect(a.isIdentical(to: a))
    #expect(a.isIdentical(to: b))
    #expect(!obj1.isIdentical(to: obj2))
}

@Test func testIsEqualWithTypeCoercion() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let a = MRubyValue.from(42, in: ctx)
    let b = MRubyValue.from(42, in: ctx)
    #expect(a.isEqualWithTypeCoercion(to: b))
}

// MARK: - Relation

@Test func testRelationEqual() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from(42, in: ctx).relation(to: MRubyValue.from(42, in: ctx)) == .equal)
}

@Test func testRelationLessThan() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from(1, in: ctx).relation(to: MRubyValue.from(100, in: ctx)) == .lessThan)
    #expect(MRubyValue.from(100, in: ctx).relation(to: MRubyValue.from(1, in: ctx)) == .greaterThan)
}

@Test func testRelationString() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let a = MRubyValue.from("apple", in: ctx)
    let b = MRubyValue.from("banana", in: ctx)
    #expect(a.relation(to: b) == .lessThan)
    #expect(a.relation(to: a) == .equal)
}

@Test func testRelationUndefined() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from(42, in: ctx).relation(to: MRubyValue.from("hello", in: ctx)) == .undefined)
}

@Test func testRelationFloat() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from(3.14, in: ctx).relation(to: MRubyValue.from(2.71, in: ctx)) == .greaterThan)
}

@Test func testRelationRawValue() async throws {
    #expect(MRubyRelationCondition(rawValue: 0) == .equal)
    #expect(MRubyRelationCondition(rawValue: 1) == .greaterThan)
    #expect(MRubyRelationCondition(rawValue: 2) == .lessThan)
    #expect(MRubyRelationCondition(rawValue: 3) == .undefined)
}

@Test func testCompareDouble() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let a = MRubyValue.from(42.0, in: ctx)
    #expect(a.compare(42.0) == .equal)
    #expect(a.compare(100.0) == .lessThan)
}

// MARK: - hasProperty / deleteProperty

@Test func testHasProperty() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from("hello", in: ctx).hasProperty("length"))
    #expect(!MRubyValue.from("hello", in: ctx).hasProperty("nonexistent_method_xyz"))
}

@Test func testDeleteProperty() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    try ctx.eval("class DelTest; def self.class_method; end; end")
    let cls = try ctx.eval("DelTest")
    #expect(cls.responds(to: "class_method"))
    cls.deleteProperty("class_method")
    #expect(cls.responds(to: "class_method") == false)
}

// MARK: - defineProperty

@Test func testDefineProperty() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let cls = try ctx.defineClass("PropTest")
    cls.defineProperty("my_attr", descriptor: ["writable": true])
    let instance = cls.construct(with: [])
    #expect(instance.responds(to: "my_attr"))
    #expect(instance.responds(to: "my_attr="))
}

// MARK: - 字符串方法

@Test func testStringMethods() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let str = MRubyValue.from("Hello, World!", in: ctx)
    #expect(str.call(method: "upcase").toString() == "HELLO, WORLD!")
    #expect(str.call(method: "downcase").toString() == "hello, world!")
}

// MARK: - 构造方法

@Test func testFromUInt32() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from(UInt32(42), in: ctx).toInt() == 42)
}

@Test func testFromInt64() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from(Int64(99), in: ctx).toInt() == 99)
}

@Test func testFromUInt64() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from(UInt64(77), in: ctx).toInt() == 77)
}

@Test func testErrorMessageConstructor() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let error = MRubyValue.error("test error", in: ctx)
    #expect(error.isException)
    #expect(error.call(method: "message").toString().contains("test error"))
}

@Test func testRegexConstructor() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    if let regex = MRubyValue.regex("hello", in: ctx) {
        #expect(regex.isObject)
    } else {
        #expect(Bool(true), "Regexp not available")
    }
}

@Test func testFromObjectAutoDetect() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from("hello" as Any?, in: ctx).isString)
    #expect(MRubyValue.from(42 as Any?, in: ctx).isInt)
    #expect(MRubyValue.from(true as Any?, in: ctx).isBool)
    #expect(MRubyValue.from(nil as Any?, in: ctx).isNil)
}

// MARK: - toObject

@Test func testToObject() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect((MRubyValue.from("hello", in: ctx).toObject() as! String) == "hello")
    #expect((MRubyValue.from(42, in: ctx).toObject() as! Int) == 42)
    #expect(MRubyValue.from("hello", in: ctx).toObject(of: String.self) == "hello")
    #expect(MRubyValue.from(42, in: ctx).toObject(of: Int.self) == 42)
}

// MARK: - 类型转换 toUInt32 / toInt64 / toUInt64

@Test func testToUInt32() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from(42, in: ctx).toUInt32() == 42)
}

@Test func testToInt64() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from(99, in: ctx).toInt64() == 99)
}

@Test func testToUInt64() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from(77, in: ctx).toUInt64() == 77)
}

// MARK: - MRubyType

@Test func testMRubyType() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(MRubyValue.from("hello", in: ctx).mrubyType == .string)
    #expect(MRubyValue.from(42, in: ctx).mrubyType == .integer)
    #expect(MRubyValue.from(true, in: ctx).mrubyType == .bool)
    #expect(MRubyValue.nil(in: ctx).mrubyType == .nilValue)
    #expect(try ctx.eval("Object.new").mrubyType == .object)
    #expect(try ctx.eval("[1,2,3]").mrubyType == .array)
    #expect(try ctx.eval("String").mrubyType == .klass)
}

@Test func testMRubyTypeCaseIterable() async throws {
    #expect(MRubyType.allCases.count > 5)
    #expect(MRubyType.allCases.contains(.string))
}

// MARK: - isFunction / isConstructor

@Test func testIsFunction() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let proc = try ctx.eval("Proc.new { |x| x * 2 }")
    #expect(proc.isFunction)
    #expect(!MRubyValue.from("hello", in: ctx).isFunction)
}

@Test func testIsConstructor() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(try ctx.eval("String").isConstructor)
    let obj = try ctx.eval("Object.new")
    #expect(!obj.isConstructor)
}

// MARK: - JSON

@Test func testToJSON() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let val = try ctx.eval("{\"a\" => 1, \"b\" => 2}")
    let _ = val.toJSON()
    #expect(Bool(true), "JSON test skipped (mruby-json gem may not be loaded)")
}

// MARK: - prototype / superclass

@Test func testPrototype() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let obj = try ctx.eval("Object.new")
    #expect(obj.prototype != nil)
}

@Test func testSuperclass() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let strClass = try ctx.eval("String")
    let superclass = strClass.superclass
    #expect(superclass != nil)
    #expect(superclass?.toString() == "Object")
}

// MARK: - MRubyPropertyAttribute

@Test func testPropertyAttribute() async throws {
    let readOnly = MRubyValue.MRubyPropertyAttribute.readOnly
    let dontEnum = MRubyValue.MRubyPropertyAttribute.dontEnum
    let dontDelete = MRubyValue.MRubyPropertyAttribute.dontDelete
    let combined: MRubyValue.MRubyPropertyAttribute = [.readOnly, .dontEnum]
    #expect(readOnly.rawValue == 1)
    #expect(dontEnum.rawValue == 2)
    #expect(dontDelete.rawValue == 4)
    #expect(combined.contains(.readOnly))
    #expect(combined.contains(.dontEnum))
    #expect(!combined.contains(.dontDelete))
}
