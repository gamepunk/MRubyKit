/// MRubyKit 错误类型。
///
/// 对应 JavaScriptCore 没有直接等价类型，但提供清晰的错误分类。
public enum MRubyError: Error, CustomStringConvertible {
    /// `mrb_open()` 初始化失败。
    case openFailed
    /// Ruby 代码执行时抛出了异常，附带异常的 inspect 字符串。
    case exception(String)
    /// 类型错误（例如向期望类的地方传入了非类值）。
    case typeError(String)
    /// 语法错误。
    case syntaxError(String)
    /// 内部错误（不可预期的运行时问题）。
    case internalError(String)

    public var description: String {
        switch self {
        case .openFailed:
            return "Failed to initialize mruby VM"
        case .exception(let msg):
            return "mruby exception: \(msg)"
        case .typeError(let msg):
            return "mruby type error: \(msg)"
        case .syntaxError(let msg):
            return "mruby syntax error: \(msg)"
        case .internalError(let msg):
            return "mruby internal error: \(msg)"
        }
    }
}
