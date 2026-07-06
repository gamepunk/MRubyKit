import Testing
@testable import MRubyKit

// MARK: - 基础执行

@Test func testEvalInteger() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let val = try ctx.eval("1 + 2")
    #expect(val.isInt)
    #expect(val.toInt() == 3)
}

@Test func testEvalString() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let val = try ctx.eval("\"hello\"")
    #expect(val.isString)
    #expect(val.toString() == "hello")
}

@Test func testEvalFloat() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let val = try ctx.eval("3.14")
    #expect(val.isFloat)
    #expect(val.toDouble() == 3.14)
}

@Test func testEvalBool() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let t = try ctx.eval("true")
    let f = try ctx.eval("false")
    #expect(t.isBool && t.isTrue && !t.isFalse)
    #expect(f.isBool && f.isFalse && !f.isTrue)
}

@Test func testEvalNil() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let val = try ctx.eval("nil")
    #expect(val.isNil)
}

// MARK: - 异常处理

@Test func testEvalException() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    do {
        _ = try ctx.eval("raise 'test error'")
        #expect(Bool(false), "Should have thrown")
    } catch let error as MRubyError {
        if case .exception(let msg) = error {
            #expect(msg.contains("test error"))
        } else {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    } catch {
        #expect(Bool(false), "Wrong error type: \(error)")
    }
}

@Test func testExceptionHandler() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    var handled = false
    ctx.exceptionHandler = { _, _ in handled = true }
    let result = try ctx.eval("raise 'error'")
    #expect(handled)
    #expect(result.isNil)
}

@Test func testExceptionProperty() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(ctx.exception == nil)
    ctx.exceptionHandler = { _, _ in }
    _ = try ctx.eval("raise 'test error'")
    // 手动设置后再清除
    let exc = try! ctx.eval("RuntimeError.new('manual')")
    ctx.exception = exc
    ctx.exception = nil
    #expect(ctx.exception == nil)
}

// MARK: - globalObject

@Test func testGlobalObject() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let global = ctx.globalObject
    #expect(global.responds(to: "to_s"))
    #expect(global.responds(to: "inspect"))
    #expect(!global.isNil)
}

// MARK: - 全局变量

@Test func testGlobalVariable() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    ctx["$answer"] = MRubyValue.from(42, in: ctx)
    let val = try ctx.eval("$answer")
    #expect(val.toInt() == 42)
}

@Test func testGlobalVariableBareName() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    ctx["answer"] = MRubyValue.from(100, in: ctx)
    let val = ctx["answer"]
    #expect(val.toInt() == 100)
}

// MARK: - 自定义函数

@Test func testDefineGlobalFunction() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    ctx.defineGlobalFunction(name: "double") { ctx, args in
        let n = args.first?.toInt() ?? 0
        return MRubyValue.from(n * 2, in: ctx)
    }
    let result = try ctx.eval("double(21)")
    #expect(result.toInt() == 42)
}

@Test func testDefineGlobalFunctionWithMultipleArgs() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    ctx.defineGlobalFunction(name: "add") { ctx, args in
        let a = args.count > 0 ? args[0].toInt() : 0
        let b = args.count > 1 ? args[1].toInt() : 0
        return MRubyValue.from(a + b, in: ctx)
    }
    let result = try ctx.eval("add(10, 20)")
    #expect(result.toInt() == 30)
}

// MARK: - 类/模块定义

@Test func testDefineClass() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let cls = try ctx.defineClass("TestClass")
    #expect(cls.isClass)
    let instance = try ctx.eval("TestClass.new")
    #expect(!instance.isNil)
    #expect(instance.isInstance(of: cls))
}

@Test func testDefineModule() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let mod = try ctx.defineModule("TestModule")
    #expect(mod.isModule)
    let result = try ctx.eval("TestModule")
    #expect(result.isModule)
}

// MARK: - 语法检查

@Test func testCheckScriptSyntax() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(ctx.checkScriptSyntax("1 + 2"))
    #expect(ctx.checkScriptSyntax("def foo; end"))
    #expect(!ctx.checkScriptSyntax("def foo;"))
}

// MARK: - eval with this

@Test func testEvalWithThis() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let obj = try ctx.eval("Object.new")
    let result = try ctx.eval("self.to_s", this: obj)
    #expect(result.isString)
}

// MARK: - isInspectable

@Test func testIsInspectable() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    #expect(ctx.isInspectable == false)
}
