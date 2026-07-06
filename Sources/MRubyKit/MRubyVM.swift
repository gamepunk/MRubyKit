import CMRuby

/// mruby 虚拟机实例。
///
/// 对应 JavaScriptCore 的 `JSVirtualMachine`。
/// 每个 `MRubyVM` 持有一个独立的 `mrb_state`，内部不是线程安全的——
/// 若需多线程并发执行 Ruby 代码，请为每个线程创建独立的 `MRubyVM`。
public final class MRubyVM: @unchecked Sendable {

    let mrb: UnsafeMutablePointer<mrb_state>

    /// 创建一个新的 mruby 虚拟机。
    /// - Throws: `MRubyError.openFailed` 若底层 `mrb_open()` 失败。
    public init() throws {
        // MRB_OPEN_FAILURE 是函数式宏，Swift 不支持，手动展开：!(mrb) || (mrb)->exc
        guard let ptr = mrb_open(), ptr.pointee.exc == nil else {
            throw MRubyError.openFailed
        }
        mrb = ptr
    }

    deinit {
        mrb_close(mrb)
    }

    /// 创建一个属于本虚拟机的新执行上下文。
    public func makeContext() -> MRubyContext {
        MRubyContext(vm: self)
    }

    // MARK: - GC 控制

    /// 触发完整 GC（mark & sweep）。
    ///
    /// 对应 JSVirtualMachine 无直接 API，但概念上类似主动触发内存回收。
    public func performGC() {
        mrb_full_gc(mrb)
    }

    /// 触发增量式 GC 的一步。
    public func performIncrementalGC() {
        mrb_incremental_gc(mrb)
    }

    /// GC 是否启用。
    public var isGCEnabled: Bool {
        !mrb.pointee.gc.disabled
    }

    /// 当前存活对象数量（近似值）。
    public var liveObjectCount: Int {
        Int(mrb.pointee.gc.live)
    }

    /// GC 阈值：存活对象数超过此值时触发 GC。
    public var gcThreshold: Int {
        get { Int(mrb.pointee.gc.threshold) }
        set { mrb.pointee.gc.threshold = size_t(newValue) }
    }

    /// GC 间隔比率（默认 200），用于调整增量式 GC 的频率。
    public var gcIntervalRatio: Int {
        get { Int(mrb.pointee.gc.interval_ratio) }
        set { mrb.pointee.gc.interval_ratio = Int32(newValue) }
    }

    /// GC 步进比率（默认 200），用于调整增量式 GC 每步回收量。
    public var gcStepRatio: Int {
        get { Int(mrb.pointee.gc.step_ratio) }
        set { mrb.pointee.gc.step_ratio = Int32(newValue) }
    }

    // MARK: - 对象生命周期管理

    /// 将对象注册到 GC 根集合，防止被回收。
    ///
    /// 对应 JSVirtualMachine 的 `addManagedReference(_:withOwner:)`。
    /// 当需要跨作用域保持一个 mruby 值的存活时使用。
    /// - Parameter value: 需要保护的值。
    public func retain(_ value: MRubyValue) {
        mrb_gc_register(mrb, value.raw)
    }

    /// 按指定条件保护 Ruby 值。
    ///
    /// 对应 JSVirtualMachine 的 `addManagedReference(_:withOwner:condition:)`。
    /// - Parameters:
    ///   - value: 需要管理的 Ruby 值。
    ///   - condition: 保护条件。
    public func retain(_ value: MRubyValue, condition: MRubyRelationCondition) {
        switch condition {
        case .objectRequired, .undefined:
            mrb_gc_register(mrb, value.raw)
        case .objectNotRequired:
            // 不注册到 GC 根集合，让正常 mark 机制管理
            break
        }
    }

    /// 从 GC 根集合中移除对象。
    ///
    /// 对应 JSVirtualMachine 的 `removeManagedReference(_:withOwner:)`。
    /// - Parameter value: 不再需要保护的值。
    public func release(_ value: MRubyValue) {
        mrb_gc_unregister(mrb, value.raw)
    }

    /// 按指定条件解除 Ruby 值的保护。
    ///
    /// 对应 JSVirtualMachine 的 `removeManagedReference(_:withOwner:condition:)`。
    /// - Parameters:
    ///   - value: 需要解除管理的 Ruby 值。
    ///   - condition: 之前使用的保护条件。
    public func release(_ value: MRubyValue, condition: MRubyRelationCondition) {
        switch condition {
        case .objectRequired, .undefined:
            mrb_gc_unregister(mrb, value.raw)
        case .objectNotRequired:
            break
        }
    }
}

// MARK: - MRubyRelationCondition 导入

/// 使 `MRubyVM` 的方法能使用 `MRubyRelationCondition`，无需在 `MRubyVM.swift` 中重复定义。
/// 该类型定义在 `MRubyManagedValue.swift` 中。
extension MRubyVM {
    /// 受条件管理的引用——当前仅用于标记重载方法的区分度，无额外作用。
}
