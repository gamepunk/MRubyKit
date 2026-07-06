import Foundation
import CMRuby

// MARK: - Trampoline

/// 全局 C 蹦床函数，作为所有通过 `defineGlobalFunction` 和 `MRubyExport`
/// 注册的原生方法的统一入口。
///
/// mruby 调用此函数时，通过 `mrb->ud`（`Unmanaged<MRubyContext>` 指针）找回对应的
/// Swift `MRubyContext` 实例，再从 `nativeFunctions` 字典中按当前方法名取出闭包执行。
///
/// - `selfVal` 是 Ruby 调用中的 receiver（对于全局函数是 `main`）。
/// - 位置参数从 `mrb_get_argc` / `mrb_get_argv` 取得。
/// - 返回值直接返回给 mruby 运行时。
func mrubyNativeTrampoline(
    _ mrb: UnsafeMutablePointer<mrb_state>?,
    _ selfVal: mrb_value
) -> mrb_value {
    guard let mrb else { return mrb_nil_value() }

    // 通过 mrb->ud 取回 MRubyContext（retain 过的 Unmanaged）
    guard let ud = mrb.pointee.ud else { return mrb_nil_value() }
    let ctx = Unmanaged<MRubyContext>.fromOpaque(ud).takeUnretainedValue()

    // 取当前调用的方法名（mrb_sym -> String）
    let midSym  = mrb_get_mid(mrb)
    let nameCStr = mrb_sym_name(mrb, midSym)
    guard let nameCStr, let body = ctx.nativeFunctions[String(cString: nameCStr)] else {
        return mrb_nil_value()
    }

    // 取参数列表（不含 self，mrb_get_argv 只返回位置参数）
    let argc = Int(mrb_get_argc(mrb))
    var args: [MRubyValue] = []
    if argc > 0, let argv = mrb_get_argv(mrb) {
        args.reserveCapacity(argc)
        for i in 0 ..< argc {
            args.append(MRubyValue(raw: argv[i], context: ctx))
        }
    }

    // 调用 body 前设置当前上下文线程存储
    let selfMRubyVal = MRubyValue(raw: selfVal, context: ctx)
    let td = Thread.current.threadDictionary
    let oldCtx = td[currentContextKey]
    let oldCallee = td[currentCalleeKey]
    let oldThis = td[currentThisKey]
    let oldArgs = td[currentArgsKey]
    td[currentContextKey] = ctx
    td[currentCalleeKey]  = MRubyValue(raw: mrb_obj_value(mrb.pointee.top_self), context: ctx)
    td[currentThisKey]    = selfMRubyVal
    td[currentArgsKey]    = args
    defer {
        td[currentContextKey] = oldCtx
        td[currentCalleeKey]  = oldCallee
        td[currentThisKey]    = oldThis
        td[currentArgsKey]    = oldArgs
    }

    return body(ctx, selfMRubyVal, args).raw
}

// MARK: - 当前上下文线程存储

private let currentContextKey = "com.mrubykit.currentContext"
private let currentCalleeKey  = "com.mrubykit.currentCallee"
private let currentThisKey    = "com.mrubykit.currentThis"
private let currentArgsKey    = "com.mrubykit.currentArguments"

// MARK: - MRubyContext

/// mruby 代码执行上下文。
///
/// 对应 JavaScriptCore 的 `JSContext`。
/// 每个上下文共享所属 `MRubyVM` 的全局状态（global object、已定义的类和方法等）。
public final class MRubyContext: @unchecked Sendable {

    // MARK: - 当前上下文类方法

    /// 当前正在执行 Ruby 代码的上下文。
    ///
    /// 对应 JSContext 的 `current()` 类方法。
    /// 在原生函数（通过 `defineGlobalFunction` 或 `MRubyExport` 注册）的
    /// 调用过程中，此属性返回正确的上下文；在外部调用时返回 `nil`。
    public static var current: MRubyContext? {
        Thread.current.threadDictionary[currentContextKey] as? MRubyContext
    }

    /// 当前正在执行的 Ruby 函数。
    /// 对应 JSContext 的 `currentCallee()` 类方法。
    public static var currentCallee: MRubyValue? {
        Thread.current.threadDictionary[currentCalleeKey] as? MRubyValue
    }

    /// 当前正在执行的 Ruby 函数中的 `self` 值。
    /// 对应 JSContext 的 `currentThis()` 类方法。
    public static var currentThis: MRubyValue? {
        Thread.current.threadDictionary[currentThisKey] as? MRubyValue
    }

    /// 当前正在执行的 Ruby 函数接收的参数。
    /// 对应 JSContext 的 `currentArguments()` 类方法。
    public static var currentArguments: [MRubyValue]? {
        Thread.current.threadDictionary[currentArgsKey] as? [MRubyValue]
    }

    // MARK: - 公开属性

    /// 所属虚拟机。
    public let virtualMachine: MRubyVM

    /// 发生异常时调用的处理闭包。
    ///
    /// - 若设置了此闭包，`eval` 遇到异常后会调用它并返回 `nil` 值，不再抛出。
    /// - 若为 `nil`，异常通过 `eval` 的 `throws` 机制传递。
    public var exceptionHandler: ((MRubyContext, MRubyValue) -> Void)?

    /// 上下文名称，仅用于调试标识，对应 `JSContext.name`。
    public var name: String = ""

    // MARK: - 内部属性

    var mrb: UnsafeMutablePointer<mrb_state> { virtualMachine.mrb }

    /// 已注册的原生函数字典（函数名 -> Swift 闭包）。
    ///
    /// 闭包签名：`(context, selfValue, arguments) -> result`
    /// - `context`: 当前执行上下文。
    /// - `selfValue`: Ruby 调用中的 receiver（对于全局函数是 `main` 对象）。
    /// - `arguments`: Ruby 传入的位置参数数组。
    /// - Returns: 方法返回值。
    ///
    /// 由全局蹦床函数 `mrubyNativeTrampoline` 在调用时查询。
    var nativeFunctions: [String: (MRubyContext, MRubyValue, [MRubyValue]) -> MRubyValue] = [:]

    // MARK: - 初始化

    init(vm: MRubyVM) {
        self.virtualMachine = vm
        // 将自身作为 userdata 挂载到 mrb->ud，供 trampoline 反向索引。
        // 使用 passUnretained：MRubyContext 的生命周期由调用方（MRubyVM）管理，
        // 此处仅借用指针，不影响引用计数。
        vm.mrb.pointee.ud = Unmanaged.passUnretained(self).toOpaque()
    }

    // MARK: - 执行脚本

    /// 执行一段 Ruby 代码，返回最后一个表达式的值。
    ///
    /// 对应 `JSContext.evaluateScript(_:)`。
    /// - Parameter code: Ruby 源代码字符串。
    /// - Returns: 执行结果封装为 `MRubyValue`。
    /// - Throws: `MRubyError.exception` 若未设置 `exceptionHandler` 且执行产生异常。
    @discardableResult
    public func eval(_ code: String) throws -> MRubyValue {
        let raw = code.withCString { mrb_load_string(mrb, $0) }

        if let excValue = checkException() {
            if let handler = exceptionHandler {
                handler(self, excValue)
                return MRubyValue(raw: mrb_nil_value(), context: self)
            }
            let msg = mrb_str_to_cstr(mrb, mrb_inspect(mrb, excValue.raw))
                .map { String(cString: $0) } ?? "<unknown error>"
            throw MRubyError.exception(msg)
        }

        return MRubyValue(raw: raw, context: self)
    }

    // MARK: - 全局变量下标访问

    /// 读写全局变量，对应 `JSContext["key"]`。
    ///
    /// mruby 全局变量名必须以 `$` 开头。若传入的 `key` 不以 `$` 开头，getter 和
    /// setter 都会自动补全前缀，以兼容裸名称写法。
    ///
    /// ```swift
    /// ctx["$answer"] = .from(42, in: ctx)
    /// ctx["answer"]  = .from(42, in: ctx)   // 等价
    /// let v = ctx["$answer"]
    /// ```
    public subscript(key: String) -> MRubyValue {
        get {
            let gvName = key.hasPrefix("$") ? key : "$\(key)"
            let sym = gvName.withCString { mrb_intern_cstr(mrb, $0) }
            return MRubyValue(raw: mrb_gv_get(mrb, sym), context: self)
        }
        set {
            let gvName = key.hasPrefix("$") ? key : "$\(key)"
            let sym = gvName.withCString { mrb_intern_cstr(mrb, $0) }
            mrb_gv_set(mrb, sym, newValue.raw)
        }
    }

    // MARK: - 定义全局函数

    /// 在全局作用域（`Object` 类）上注册一个可从 Ruby 调用的原生函数。
    ///
    /// 对应 JSContext 的 `context["funcName"] = { ... }` 写法。
    ///
    /// 由于 mruby 的 `mrb_func_t` 是 C 函数指针，Swift 闭包无法直接传入。
    /// 实现采用单一全局蹦床函数 `mrubyNativeTrampoline`：
    /// - `mrb->ud` 指向当前 `MRubyContext`（`Unmanaged` 借用引用）。
    /// - `nativeFunctions` 字典以函数名为键存储 Swift 闭包。
    /// - 蹦床在被 mruby 调用时，通过 `mrb_get_mid` 还原方法名，查表取出闭包执行。
    ///
    /// - Parameters:
    ///   - name: 函数名称（对应 Ruby 方法名）。
    ///   - body: Swift 闭包，接收当前 context 和参数数组，返回结果值。
    ///
    /// ### 示例
    /// ```swift
    /// ctx.defineGlobalFunction(name: "add") { ctx, args in
    ///     let a = args.count > 0 ? args[0].toInt() : 0
    ///     let b = args.count > 1 ? args[1].toInt() : 0
    ///     return .from(a + b, in: ctx)
    /// }
    /// try ctx.eval("puts add(1, 2)")   // => 3
    /// ```
    public func defineGlobalFunction(
        name: String,
        body: @escaping (MRubyContext, [MRubyValue]) -> MRubyValue
    ) {
        // 包装为用户提供的签名（忽略 self）
        nativeFunctions[name] = { ctx, _, args in
            body(ctx, args)
        }

        // MRB_ARGS_ANY() = MRB_ARGS_REST() = (mrb_aspec)(1 << 12) = 0x1000
        // 接受任意数量的位置参数（含 *splat）。
        let aspec: mrb_aspec = 0x1000

        // 注册在 Object 类上，使其成为全局可调用的内核方法（所有对象均可调用）。
        let objectClass = mrb.pointee.object_class
        name.withCString { cName in
            mrb_define_method(mrb, objectClass, cName, mrubyNativeTrampoline, aspec)
        }
    }

        // MARK: - 异常

    /// 当前挂起的 Ruby 异常。
    ///
    /// 对应 JSContext 的 `exception` 属性。
    /// - getter: 返回当前 `mrb->exc` 封装为 `MRubyValue`，若无异常返回 `nil`。
    /// - setter: 若设为 `nil` 则清除异常；若设为非 `nil` 值，会将其设置为 mruby 的当前异常。
    public var exception: MRubyValue? {
        get {
            guard let exc = mrb.pointee.exc else { return nil }
            return MRubyValue(raw: mrb_obj_value(exc), context: self)
        }
        set {
            if let value = newValue {
                let excPtr = mrb_bridge_exc_ptr(value.raw)!
                mrb.pointee.exc = UnsafeMutableRawPointer(excPtr).assumingMemoryBound(to: RObject.self)
            } else {
                mrb.pointee.exc = nil
            }
        }
    }

    /// 全局对象（`main` 对象）。
    ///
    /// 对应 JSContext 的 `globalObject` 属性。
    /// 在 mruby 中，全局作用域的 `self` 是 `main` 对象（`top_self`）。
    public var globalObject: MRubyValue {
        MRubyValue(raw: mrb_obj_value(mrb.pointee.top_self), context: self)
    }

    // MARK: - 带 receiver 的执行

    /// 在指定对象上执行 Ruby 代码（该对象成为代码中的 `self`）。
    ///
    /// 对应 JSContext 的 `evaluateScript(_:)` 但绑定 `this`，
    /// 类似于 Ruby 的 `instance_eval`。
    /// - Parameters:
    ///   - code: Ruby 源代码字符串。
    ///   - this: 执行时的 `self` 对象。
    /// - Returns: 执行结果封装为 `MRubyValue`。
    /// - Throws: `MRubyError.exception` 若执行产生异常。
    @discardableResult
    public func eval(_ code: String, this: MRubyValue) throws -> MRubyValue {
        // 通过 instance_eval 在指定 receiver 上执行代码
        let result = this.call(method: "instance_eval", arguments: [MRubyValue.from(code, in: self)])

        // 检查异常
        if let excValue = checkException() {
            if let handler = exceptionHandler {
                handler(self, excValue)
                return MRubyValue(raw: mrb_nil_value(), context: self)
            }
            let msg = mrb_str_to_cstr(mrb, mrb_inspect(mrb, excValue.raw))
                .map { String(cString: $0) } ?? "<unknown error>"
            throw MRubyError.exception(msg)
        }

        return result
    }

    // MARK: - 带源码 URL 的执行

    /// 执行一段 Ruby 代码，并指定源码文件名（用于错误回溯）。
    ///
    /// 对应 JSContext 的 `evaluateScript(_:withSourceURL:)`。
    /// - Parameters:
    ///   - code: Ruby 源代码字符串。
    ///   - sourceURL: 源码文件名/路径，将出现在异常回溯中。
    /// - Returns: 执行结果封装为 `MRubyValue`。
    /// - Throws: `MRubyError.exception` 若未设置 `exceptionHandler` 且执行产生异常。
    @discardableResult
    public func eval(_ code: String, sourceURL: String) throws -> MRubyValue {
        let cctx = mrb_ccontext_new(mrb)!
        defer { mrb_ccontext_free(mrb, cctx) }

        // 设置文件名
        _ = mrb_ccontext_filename(mrb, cctx, sourceURL)

        let raw = code.withCString { cCode in
            mrb_load_string_cxt(mrb, cCode, cctx)
        }

        if let excValue = checkException() {
            if let handler = exceptionHandler {
                handler(self, excValue)
                return MRubyValue(raw: mrb_nil_value(), context: self)
            }
            let msg = mrb_str_to_cstr(mrb, mrb_inspect(mrb, excValue.raw))
                .map { String(cString: $0) } ?? "<unknown error>"
            throw MRubyError.exception(msg)
        }

        return MRubyValue(raw: raw, context: self)
    }

    // MARK: - 语法检查

    /// 检查 Ruby 代码语法是否正确，不执行代码。
    ///
    /// 对应 JSContext 的 `checkScriptSyntax(_:)`。
    /// - Parameter code: Ruby 源代码字符串。
    /// - Returns: 语法正确返回 `true`；否则返回 `false`。
    public func checkScriptSyntax(_ code: String) -> Bool {
        let cctx = mrb_ccontext_new(mrb)!
        defer { mrb_ccontext_free(mrb, cctx) }

        let parser = code.withCString { cCode in
            mrb_parse_string(mrb, cCode, cctx)
        }
        guard let parser else { return false }
        defer { mrb_parser_free(parser) }

        return parser.pointee.nerr == 0
    }

    // MARK: - 定义类与模块

    /// 在全局作用域定义一个新类。
    ///
    /// 对应 Ruby 的 `class Name < SuperClass`。
    /// - Parameters:
    ///   - name: 类名（首字母大写的常量名）。
    ///   - superclass: 父类值。若为 `nil`，默认继承 `Object`。
    /// - Returns: 代表新类的 `MRubyValue`。
    /// - Throws: `MRubyError.exception` 若该类名已被占用或无效。
    @discardableResult
    public func defineClass(_ name: String, superclass: MRubyValue? = nil) throws -> MRubyValue {
        let superRClass: UnsafeMutablePointer<RClass>?
        if let superVal = superclass {
            guard mrb_bridge_class_p(superVal.raw) else {
                throw MRubyError.typeError("superclass must be a class")
            }
            superRClass = mrb_bridge_class_ptr(superVal.raw)
        } else {
            superRClass = mrb.pointee.object_class
        }

        let newClass = name.withCString { cName in
            mrb_define_class(mrb, cName, superRClass)
        }

        // 检查是否发生异常（类名冲突等）
        if let excValue = checkException() {
            let msg = mrb_str_to_cstr(mrb, mrb_inspect(mrb, excValue.raw))
                .map { String(cString: $0) } ?? "<unknown error>"
            throw MRubyError.exception(msg)
        }

        return MRubyValue(raw: mrb_obj_value(newClass), context: self)
    }

    /// 在全局作用域定义一个新模块。
    ///
    /// 对应 Ruby 的 `module Name`。
    /// - Parameter name: 模块名（首字母大写的常量名）。
    /// - Returns: 代表新模块的 `MRubyValue`。
    /// - Throws: `MRubyError.exception` 若该模块名已被占用或无效。
    @discardableResult
    public func defineModule(_ name: String) throws -> MRubyValue {
        let newModule = name.withCString { cName in
            mrb_define_module(mrb, cName)
        }

        if let excValue = checkException() {
            let msg = mrb_str_to_cstr(mrb, mrb_inspect(mrb, excValue.raw))
                .map { String(cString: $0) } ?? "<unknown error>"
            throw MRubyError.exception(msg)
        }

        return MRubyValue(raw: mrb_obj_value(newModule), context: self)
    }

    // MARK: - 异常检查（私有）

    /// 检查并清除 `mrb->exc`。
    ///
    /// - Returns: 若存在挂起的异常，返回封装好的 `MRubyValue`；否则返回 `nil`。
    @discardableResult
    private func checkException() -> MRubyValue? {
        guard let exc = mrb.pointee.exc else { return nil }
        mrb.pointee.exc = nil
        return MRubyValue(raw: mrb_obj_value(exc), context: self)
    }
}
