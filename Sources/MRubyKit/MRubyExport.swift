import Foundation
import CMRuby

// MARK: - MRubyMethod

/// 描述一个暴露给 Ruby 的实例方法。
///
/// 对应 JSExport 协议中声明的方法。
/// 闭包接收 `(context, selfValue, arguments)`，其中 `selfValue` 是 Ruby 侧调用该方法的 receiver。
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

    /// 创建一个暴露给 Ruby 的实例方法定义。
    /// - Parameters:
    ///   - name: Ruby 方法名。
    ///   - body: 方法体。
    public init(name: String, body: @escaping (MRubyContext, MRubyValue, [MRubyValue]) -> MRubyValue) {
        self.name = name
        self.body = body
    }

    /// 创建带有重命名支持的方法定义。
    ///
    /// 对应 JSExport 的 `JSExportAs` 宏——允许为 Ruby 方法指定不同的名称。
    /// - Parameters:
    ///   - rubyName: Ruby 中暴露的方法名。
    ///   - body: 方法体。
    public init(rubyName: String, body: @escaping (MRubyContext, MRubyValue, [MRubyValue]) -> MRubyValue) {
        self.name = rubyName
        self.body = body
    }
}

// MARK: - MRubyProperty

/// 描述一个暴露给 Ruby 的属性。
///
/// 对应 JSExport 协议中的 `@property` 声明。
/// 在 Ruby 中自动生成 getter 和可选的 setter 方法。
public struct MRubyProperty: @unchecked Sendable {

    /// 属性名。
    public let name: String

    /// 是否只读（不生成 setter）。
    public let readonly: Bool

    /// getter 闭包。
    public let getter: (MRubyContext, MRubyValue) -> MRubyValue

    /// setter 闭包（只读属性时为 nil）。
    public let setter: ((MRubyContext, MRubyValue, MRubyValue) -> Void)?

    /// 定义可读写属性（对应 JSC `readwrite`）。
    public init(name: String,
                getter: @escaping (MRubyContext, MRubyValue) -> MRubyValue,
                setter: @escaping (MRubyContext, MRubyValue, MRubyValue) -> Void) {
        self.name = name
        self.readonly = false
        self.getter = getter
        self.setter = setter
    }

    /// 定义只读属性（对应 JSC `readonly`）。
    public init(name: String,
                getter: @escaping (MRubyContext, MRubyValue) -> MRubyValue) {
        self.name = name
        self.readonly = true
        self.getter = getter
        self.setter = nil
    }
}

// MARK: - MRubyExport

/// 对应 JavaScriptCore 的 `JSExport` 协议。
///
/// 实现此协议的 Swift 类可以将其方法和属性暴露给 Ruby 运行时。
///
/// ### JSC 对照
///
/// | JSExport | MRubyExport |
/// |----------|-------------|
/// | 协议中声明的实例方法 | `rubyMethods` |
/// | 协议中声明的类方法 | `rubyClassMethods` |
/// | `@property` 声明 | `rubyProperties` |
/// | `JSExportAs` 宏 | `MRubyMethod(rubyName:)` |
/// | `MyClass.new(args)` | `MyClass.new(args)` (Ruby 原生支持) |
/// | `MyClass.classMethod(args)` | `MyClass.classMethod(args)` |
///
/// ### 使用示例
///
/// ```swift
/// class MyBridge: MRubyExport {
///     static let rubyClassName = "MyBridge"
///
///     // 实例方法
///     static let rubyMethods: [MRubyMethod] = [
///         MRubyMethod(name: "add") { ctx, selfVal, args in
///             let a = args.first?.toInt() ?? 0
///             let b = args.count > 1 ? args[1].toInt() ?? 0 : 0
///             return .from(a + b, in: ctx)
///         },
///     ]
///
///     // 类方法（对应 JSExport 类方法在构造函数上）
///     static let rubyClassMethods: [MRubyMethod] = [
///         MRubyMethod(name: "create") { ctx, selfVal, args in
///             return try! ctx.eval("MyBridge.new")
///         },
///     ]
///
///     // 属性（自动生成 getter/setter）
///     static let rubyProperties: [MRubyProperty] = [
///         MRubyProperty(name: "version") { ctx, selfVal in
///             .from(1, in: ctx)
///         },
///     ]
/// }
/// ```
public protocol MRubyExport: AnyObject {

    /// 在 Ruby 中的类名（首字母大写的常量名）。
    static var rubyClassName: String { get }

    /// 需要暴露给 Ruby 的实例方法列表。
    static var rubyMethods: [MRubyMethod] { get }

    /// 需要暴露给 Ruby 的类方法列表（定义在类的 singleton 上）。
    ///
    /// 对应 JSExport 协议中的类方法（`+` 方法），JavaScript 中可通过构造函数调用。
    static var rubyClassMethods: [MRubyMethod] { get }

    /// 需要暴露给 Ruby 的属性列表（自动生成 getter/setter）。
    ///
    /// 对应 JSExport 协议中的 `@property` 声明。
    static var rubyProperties: [MRubyProperty] { get }
}

// MARK: - 默认实现

extension MRubyExport {
    public static var rubyClassMethods: [MRubyMethod] { [] }
    public static var rubyProperties: [MRubyProperty] { [] }
}

// MARK: - 注册

extension MRubyExport {

    /// 在指定上下文中注册该类，使其在 Ruby 中可用。
    ///
    /// 此方法会：
    /// 1. 在 Ruby 全局作用域中创建一个以 `rubyClassName` 命名的新类
    /// 2. 为 `rubyMethods` 中的每个实例方法注册 C 蹦床
    /// 3. 为 `rubyClassMethods` 中的每个类方法注册到 singleton 类
    /// 4. 为 `rubyProperties` 中的每个属性注册 getter/setter
    /// 5. 每个方法在被 Ruby 调用时通过 trampoline 派发到对应的 Swift 闭包
    ///
    /// - Parameter context: 注册到的 Ruby 执行上下文。
    /// - Throws: `MRubyError` 若类名冲突或注册失败。
    public static func register(in context: MRubyContext) throws {
        let mrb = context.mrb

        // 1. 在 Ruby 中定义类
        let superClass = context.mrb.pointee.object_class
        let rClass: UnsafeMutablePointer<RClass>?
        if mrb_bridge_class_defined_p(mrb, rubyClassName) {
            rClass = mrb_bridge_class_get(mrb, rubyClassName)
        } else {
            rClass = rubyClassName.withCString { cName in
                mrb_define_class(mrb, cName, superClass)
            }
        }
        guard let rClass else {
            throw MRubyError.internalError("Failed to create Ruby class '\(rubyClassName)'")
        }

        let aspec: mrb_aspec = 0x1000  // MRB_ARGS_ANY()

        // 2. 注册实例方法
        for method in rubyMethods {
            context.nativeFunctions[method.name] = method.body
            method.name.withCString { cName in
                mrb_define_method(mrb, rClass, cName, mrubyNativeTrampoline, aspec)
            }
        }

        // 3. 注册类方法（在 singleton 类上，对应 JSC 类方法）
        let singletonClass = mrb_singleton_class_ptr(mrb, mrb_obj_value(rClass))
        if let singletonClass {
            for method in rubyClassMethods {
                context.nativeFunctions[method.name] = method.body
                method.name.withCString { cName in
                    mrb_define_method(mrb, singletonClass, cName, mrubyNativeTrampoline, aspec)
                }
            }
        }

        // 4. 注册属性（getter + 可选的 setter）
        for prop in rubyProperties {
            // getter
            let getterBody: (MRubyContext, MRubyValue, [MRubyValue]) -> MRubyValue = { ctx, selfVal, _ in
                prop.getter(ctx, selfVal)
            }
            context.nativeFunctions[prop.name] = getterBody
            prop.name.withCString { cName in
                mrb_define_method(mrb, rClass, cName, mrubyNativeTrampoline, aspec)
            }

            // setter（仅 readwrite）
            if !prop.readonly, let setter = prop.setter {
                let setterName = "\(prop.name)="
                let setterBody: (MRubyContext, MRubyValue, [MRubyValue]) -> MRubyValue = { ctx, selfVal, args in
                    let newValue = args.first ?? .nil(in: ctx)
                    setter(ctx, selfVal, newValue)
                    return newValue
                }
                context.nativeFunctions[setterName] = setterBody
                setterName.withCString { cName in
                    mrb_define_method(mrb, rClass, cName, mrubyNativeTrampoline, aspec)
                }
            }
        }
    }
}

// MARK: - C 桥接

private func mrb_bridge_class_defined_p(_ mrb: UnsafeMutablePointer<mrb_state>?, _ name: String) -> Bool {
    name.withCString { cName in
        mrb_class_defined(mrb, cName)
    }
}

private func mrb_bridge_class_get(_ mrb: UnsafeMutablePointer<mrb_state>?, _ name: String) -> UnsafeMutablePointer<RClass>? {
    name.withCString { cName in
        mrb_class_get(mrb, cName)
    }
}
