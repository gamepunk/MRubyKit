import Foundation

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

    /// 被管理的 Ruby 值（对应 JSManagedValue 的 `value` 属性）。
    public let rubyValue: MRubyValue

    /// 被管理的 Ruby 值（JSManagedValue 兼容别名）。
    public var value: MRubyValue { rubyValue }

    /// 所属虚拟机。
    public let virtualMachine: MRubyVM

    /// owner 对象（若有）。当 owner 被释放时，关联的 `MRubyValue` 也会被释放。
    private weak var owner: AnyObject?

    /// 是否通过 `mrb_gc_register` 保护了该值。
    private var isProtected: Bool = true

    // MARK: - 创建

    /// 创建一个托管值，归入指定 VM 的保护（无 owner）。
    ///
    /// 值会被 `mrb_gc_register` 保护，直到 `MRubyManagedValue` 被释放。
    /// - Parameter value: 需要托管的 Ruby 值。
    public init(value: MRubyValue) {
        self.rubyValue = value
        self.virtualMachine = value.context.virtualMachine
        self.owner = nil
        virtualMachine.retain(value)
    }

    /// 创建一个与 owner 生命周期绑定的托管值。
    ///
    /// 对应 JSManagedValue 的 `init(value:andOwner:)`。
    /// 内部调用 `addManagedReference(_:withOwner:)` 告知 VM 该对象关系，
    /// 当 owner 被 Swift ARC 释放时，该值会自动从 mruby GC 保护中移除。
    /// - Parameters:
    ///   - value: 需要托管的 Ruby 值。
    ///   - owner: 拥有该值的 Swift 对象。使用 `weak` 引用，不会延长其生命周期。
    public init(value: MRubyValue, owner: AnyObject) {
        self.rubyValue = value
        self.virtualMachine = value.context.virtualMachine
        self.owner = owner
        // 使用 addManagedReference 注册 owner 关系（匹配 JSC 行为）
        virtualMachine.addManagedReference(value, withOwner: owner)
    }

    deinit {
        // 仅在尚未释放时注销
        if isProtected {
            if let owner = owner {
                virtualMachine.removeManagedReference(rubyValue, withOwner: owner)
            } else {
                virtualMachine.release(rubyValue)
            }
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
        if let owner = owner {
            virtualMachine.removeManagedReference(rubyValue, withOwner: owner)
        } else {
            virtualMachine.release(rubyValue)
        }
        isProtected = false
    }
}
