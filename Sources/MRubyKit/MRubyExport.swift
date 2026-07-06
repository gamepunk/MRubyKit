import Foundation
import CMRuby

// MARK: - MRubyMethod

/// 描述一个暴露给 Ruby 的方法。
///
/// 包含方法名和对应的 Swift 闭包。闭包接收 `(context, selfValue, arguments)`，
/// 其中 `selfValue` 是 Ruby 侧调用该方法的 receiver。
public struct MRubyMethod: @unchecked Sendable {

    /// Ruby 中的方法名。
    public let name: String

    /// 方法体闭包。
    ///
    /// - Parameters:
    ///   - context: 当前执行上下文。
    ///   - selfValue: Ruby 调用中的 `self`（receiver）。
    ///   - arguments: Ruby 传入的参数列表。
    /// - Returns: 方法返回值。
    public let body: (MRubyContext, MRubyValue, [MRubyValue]) -> MRubyValue

    /// 创建一个暴露给 Ruby 的方法定义。
    /// - Parameters:
    ///   - name: Ruby 方法名。
    ///   - body: 方法体。
    public init(name: String, body: @escaping (MRubyContext, MRubyValue, [MRubyValue]) -> MRubyValue) {
        self.name = name
        self.body = body
    }
}

// MARK: - MRubyExport

/// 对应 JavaScriptCore 的 `JSExport` 协议。
///
/// 实现此协议的 Swift 类可以将其方法暴露给 Ruby 运行时，Swift 实例方法可以
/// 被 Ruby 代码直接调用。
///
/// ### 使用步骤
///
/// 1. 让 Swift 类实现 `MRubyExport` 协议：
///
/// ```swift
/// class CalcBridge: MRubyExport {
///     static let rubyClassName = "Calc"
///     static let rubyMethods: [MRubyMethod] = [
///         MRubyMethod(name: "add") { ctx, selfVal, args in
///             let a = args.count > 0 ? args[0].toInt() : 0
///             let b = args.count > 1 ? args[1].toInt() : 0
///             return .from(a + b, in: ctx)
///         },
///         MRubyMethod(name: "greet") { ctx, selfVal, args in
///             let name = args.first?.toString() ?? "world"
///             return .from("Hello, \(name)!", in: ctx)
///         },
///     ]
/// }
/// ```
///
/// 2. 在 Ruby 上下文中注册该类：
///
/// ```swift
/// let ctx = try MRubyVM().makeContext()
/// try CalcBridge.register(in: ctx)
/// let result = try ctx.eval("Calc.new.add(3, 4)") // => 7
/// ```
public protocol MRubyExport: AnyObject {

    /// 在 Ruby 中的类名（首字母大写的常量名）。
    static var rubyClassName: String { get }

    /// 需要暴露给 Ruby 的方法列表。
    static var rubyMethods: [MRubyMethod] { get }
}

// MARK: - 注册

extension MRubyExport {

    /// 在指定上下文中注册该类，使其在 Ruby 中可用。
    ///
    /// 此方法会：
    /// 1. 在 Ruby 全局作用域中创建一个以 `rubyClassName` 命名的新类
    /// 2. 为 `rubyMethods` 中的每个方法注册一个 C 蹦床函数
    /// 3. 每个方法在被 Ruby 调用时，会通过 trampoline 派发到对应的 Swift 闭包
    ///
    /// - Parameter context: 注册到的 Ruby 执行上下文。
    /// - Throws: `MRubyError` 若类名冲突或注册失败。
    public static func register(in context: MRubyContext) throws {
        let mrb = context.mrb

        // 在 Ruby 中定义类
        let cls = context.mrb.pointee.object_class
        let rClass: UnsafeMutablePointer<RClass>?
        if mrb_bridge_class_defined_p(mrb, rubyClassName) {
            rClass = mrb_bridge_class_get(mrb, rubyClassName)
        } else {
            rClass = rubyClassName.withCString { cName in
                mrb_define_class(mrb, cName, cls)
            }
        }

        guard let rClass else {
            throw MRubyError.internalError("Failed to create Ruby class '\(rubyClassName)'")
        }

        // 为每个方法注册蹦床（body 已包含 self，可直接存入 nativeFunctions）
        let aspec: mrb_aspec = 0x1000  // MRB_ARGS_ANY()

        for method in rubyMethods {
            // body 签名已是 (context, selfValue, arguments) -> result
            context.nativeFunctions[method.name] = method.body

            method.name.withCString { cName in
                mrb_define_method(mrb, rClass, cName, mrubyNativeTrampoline, aspec)
            }
        }
    }
}

// MARK: - C 桥接

/// 检查 Ruby 类是否已定义。
/// 包装 `mrb_class_defined` 宏（若其是函数则直接使用；若是宏则需要桥接）。
/// 从 `mruby.h` 中，`mrb_class_defined` 是 MRB_API 函数，可直接调用。
private func mrb_bridge_class_defined_p(_ mrb: UnsafeMutablePointer<mrb_state>?, _ name: String) -> Bool {
    name.withCString { cName in
        mrb_class_defined(mrb, cName)
    }
}

/// 获取已定义的 Ruby 类。
private func mrb_bridge_class_get(_ mrb: UnsafeMutablePointer<mrb_state>?, _ name: String) -> UnsafeMutablePointer<RClass>? {
    name.withCString { cName in
        mrb_class_get(mrb, cName)
    }
}
