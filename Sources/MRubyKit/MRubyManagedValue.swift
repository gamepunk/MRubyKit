import Foundation

// MARK: - MRubyRelationCondition

/// managed reference 的条件，控制关联值的 GC 保护策略。
///
/// 对应 JavaScriptCore 的 `JSRelationCondition`。
/// 当通过 `MRubyManagedValue` 或 `MRubyVM` 的 managed reference 方法管理
/// Ruby 值的生命周期时，此枚举决定该值在何种条件下被 GC 保护。
public enum MRubyRelationCondition: Sendable {
    /// 未指定条件，使用默认行为（等价于 `objectRequired`）。
    case undefined
    /// 要求对象存活——只要 owner 存活，值就不会被 GC 回收。
    /// 对应 `mrb_gc_register`。
    case objectRequired
    /// 不要求对象存活——值不注册到 GC 根集合，由正常的 GC mark 机制管理。
    /// 仅当值可从其他 GC root 到达时才存活。
    case objectNotRequired
}

// MARK: - MRubyManagedValue

/// 管理 mruby 值的生命周期，对应 JavaScriptCore 的 `JSManagedValue`。
///
/// 当 Swift 对象需要长期持有 `MRubyValue` 时，使用 `MRubyManagedValue`
/// 可以自动管理 GC 注册/注销，防止 mruby GC 回收正在被 Swift 引用的值。
///
/// ### 基本用法
/// ```swift
/// class MyModel {
///     private var cachedResult: MRubyManagedValue?
///
///     func compute(in ctx: MRubyContext) -> MRubyValue {
///         if let cached = cachedResult { return cached.rubyValue }
///         let val = try! ctx.eval("heavy_computation()")
///         cachedResult = MRubyManagedValue(value: val, owner: self)
///         return val
///     }
/// }
/// ```
///
/// 对应 JavaScriptCore:
/// - `JSManagedValue(value:)` → 无 owner，值在 VM 层面被保护
/// - `JSManagedValue(value:owner:)` → 值与 owner 生命周期绑定
public final class MRubyManagedValue: @unchecked Sendable {

    /// 被管理的 Ruby 值。
    public let rubyValue: MRubyValue

    /// 所属虚拟机。
    public let virtualMachine: MRubyVM

    /// owner 对象（若有）。当 owner 被释放时，关联的 `MRubyValue` 也会被释放。
    private weak var owner: AnyObject?

    /// 保护条件。
    private let condition: MRubyRelationCondition

    /// 是否通过 `mrb_gc_register` 保护了该值。
    private var isProtected: Bool = false

    // MARK: - 创建

    /// 创建一个托管值，归入指定 VM 的保护（无 owner）。
    ///
    /// 默认条件为 `objectRequired`——值会被 `mrb_gc_register` 保护，
    /// 直到 `MRubyManagedValue` 本身被释放。
    /// - Parameter value: 需要托管的 Ruby 值。
    public convenience init(value: MRubyValue) {
        self.init(value: value, owner: nil, condition: .objectRequired)
    }

    /// 创建一个与 owner 生命周期绑定的托管值。
    ///
    /// 当 owner 被 Swift ARC 释放时，该值会自动从 mruby GC 保护中移除，
    /// 使其可被 mruby GC 正常回收。
    /// - Parameters:
    ///   - value: 需要托管的 Ruby 值。
    ///   - owner: 拥有该值的 Swift 对象。使用 `weak` 引用，不会延长其生命周期。
    public convenience init(value: MRubyValue, owner: AnyObject) {
        self.init(value: value, owner: owner, condition: .objectRequired)
    }

    /// 创建托管值，并指定保护条件。
    ///
    /// - Parameters:
    ///   - value: 需要托管的 Ruby 值。
    ///   - owner: 拥有该值的 Swift 对象（可为 `nil`）。
    ///   - condition: 保护条件，默认 `.objectRequired`。
    public init(value: MRubyValue, owner: AnyObject?, condition: MRubyRelationCondition) {
        self.rubyValue = value
        self.virtualMachine = value.context.virtualMachine
        self.owner = owner
        self.condition = condition

        // 仅当 objectRequired 时注册到 GC 根集合
        if condition == .objectRequired || condition == .undefined {
            virtualMachine.retain(value)
            isProtected = true
        }
    }

    deinit {
        // 仅在尚未释放时注销
        if isProtected {
            virtualMachine.release(rubyValue)
            isProtected = false
        }
    }

    // MARK: - 手动管理

    /// 手动解除 GC 保护（提前释放值，不再防止回收）。
    ///
    /// 调用后，若该值没有其他引用，mruby GC 可在下次回收时将其释放。
    /// 对应 JSManagedValue 没有直接等价 API，但可在 owner 提前释放时使用。
    public func dispose() {
        guard isProtected else { return }
        virtualMachine.release(rubyValue)
        isProtected = false
    }
}
