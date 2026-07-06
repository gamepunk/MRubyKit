import Testing
@testable import MRubyKit

// 测试用的导出类
final class TestBridge: MRubyExport, @unchecked Sendable {
    nonisolated(unsafe) static let rubyClassName = "SwiftBridge"
    nonisolated(unsafe) static let rubyMethods: [MRubyMethod] = [
        MRubyMethod(name: "hello") { ctx, selfVal, args in
            .from("Hello from Swift!", in: ctx)
        },
        MRubyMethod(name: "double") { ctx, selfVal, args in
            let n = args.first?.toInt() ?? 0
            return .from(n * 2, in: ctx)
        },
        MRubyMethod(name: "greet") { ctx, selfVal, args in
            let name = args.first?.toString() ?? "world"
            return .from("Hi, \(name)!", in: ctx)
        },
    ]
    nonisolated(unsafe) static let rubyClassMethods: [MRubyMethod] = [
        MRubyMethod(name: "info") { ctx, selfVal, args in
            .from("SwiftBridge class", in: ctx)
        },
    ]
    nonisolated(unsafe) static let rubyProperties: [MRubyProperty] = [
        MRubyProperty(name: "version") { ctx, selfVal in
            .from(42, in: ctx)
        },
        MRubyProperty(name: "label",
            getter: { ctx, selfVal in .from("default", in: ctx) },
            setter: { ctx, selfVal, newValue in }
        ),
    ]
}

// MARK: - 注册

@Test func testMRubyExportRegistration() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    try TestBridge.register(in: ctx)
    #expect(try ctx.eval("SwiftBridge").isClass)
}

@Test func testMRubyExportMethodCall() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    try TestBridge.register(in: ctx)
    #expect(try ctx.eval("SwiftBridge.new.hello").toString() == "Hello from Swift!")
}

@Test func testMRubyExportWithArgs() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    try TestBridge.register(in: ctx)
    #expect(try ctx.eval("SwiftBridge.new.double(21)").toInt() == 42)
}

@Test func testMRubyExportMultipleArgs() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    try TestBridge.register(in: ctx)
    #expect(try ctx.eval("SwiftBridge.new.greet(\"MRubyKit\")").toString() == "Hi, MRubyKit!")
}

// MARK: - 类方法导出

@Test func testMRubyExportClassMethod() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    try TestBridge.register(in: ctx)
    #expect(try ctx.eval("SwiftBridge.info").toString() == "SwiftBridge class")
}

// MARK: - 属性导出

@Test func testMRubyExportPropertyGetter() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    try TestBridge.register(in: ctx)
    #expect(try ctx.eval("SwiftBridge.new.version").toInt() == 42)
}

@Test func testMRubyExportReadWriteProperty() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    try TestBridge.register(in: ctx)
    #expect(try ctx.eval("SwiftBridge.new.label").toString() == "default")
    try ctx.eval("SwiftBridge.new.label = 'new-value'")
    #expect(Bool(true))
}
