import Foundation
import CMRuby

// MARK: - MRubyType

/// mruby 值的运行时类型分类。
///
/// 对应 JavaScriptCore 的 `JSType` 枚举。
public enum MRubyType: UInt32, Sendable, CaseIterable {
    case undefined = 0
    case nilValue  = 1
    case bool      = 2
    case integer   = 3
    case float     = 4
    case string    = 5
    case symbol    = 6
    case object    = 7
    case array     = 8
    case hash      = 9
    case range     = 10
    case klass     = 11
    case module    = 12
    case proc      = 13
    case exception = 14
    case data      = 15
    case fiber     = 16
    case complex   = 17
    case rational  = 18
    case bigint    = 19
    case istruct   = 20

    /// 从 mruby `mrb_vtype` 创建。
    init(mrbTypeValue: mrb_value) {
        let tt = mrb_type(mrbTypeValue)
        switch tt {
        case MRB_TT_SYMBOL:   self = .symbol
        case MRB_TT_FLOAT:    self = .float
        case MRB_TT_INTEGER:  self = .integer
        case MRB_TT_OBJECT:   self = .object
        case MRB_TT_CLASS:    self = .klass
        case MRB_TT_MODULE:   self = .module
        case MRB_TT_HASH:     self = .hash
        case MRB_TT_CDATA:    self = .data
        case MRB_TT_EXCEPTION:self = .exception
        case MRB_TT_PROC:     self = .proc
        case MRB_TT_ARRAY:    self = .array
        case MRB_TT_STRING:   self = .string
        case MRB_TT_RANGE:    self = .range
        case MRB_TT_FIBER:    self = .fiber
        case MRB_TT_STRUCT:   self = .array
        case MRB_TT_ISTRUCT:  self = .istruct
        case MRB_TT_COMPLEX:  self = .complex
        case MRB_TT_RATIONAL: self = .rational
        case MRB_TT_BIGINT:   self = .bigint
        default:              self = .undefined
        }
    }
}

// MARK: - MRubyRelationCondition

/// 两个 mruby 值之间的比较关系。
///
/// 对应 JavaScriptCore 的 `JSRelationCondition`。
/// 通过 Ruby 的 `<=>`（spaceship）运算符实现三路比较。
///
/// ```swift
/// let rel = value1.relation(to: value2)
/// switch rel {
/// case .equal:        // value1 == value2
/// case .greaterThan:  // value1 > value2
/// case .lessThan:     // value1 < value2
/// case .undefined:    // 不可比较（类型不同等）
/// }
/// ```
public enum MRubyRelationCondition: UInt32, Sendable {
    /// 两个值相等（Ruby `<=>` 返回 0）。
    case equal       = 0
    /// 左值大于右值（Ruby `<=>` 返回 1）。
    case greaterThan = 1
    /// 左值小于右值（Ruby `<=>` 返回 -1）。
    case lessThan    = 2
    /// 无法比较（Ruby `<=>` 返回 `nil`，例如不同类型）。
    case undefined   = 3

    /// 从 Ruby `<=>` 的返回值创建。
    /// - Parameter spaceshipResult: Ruby `<=>` 的返回值（Integer 或 nil）。
    init(spaceshipValue: MRubyValue) {
        if spaceshipValue.isNil {
            self = .undefined
        } else {
            let val = spaceshipValue.toInt()
            if val < 0 { self = .lessThan }
            else if val > 0 { self = .greaterThan }
            else { self = .equal }
        }
    }
}

/// 对 mruby 值的引用。
///
/// 对应 JavaScriptCore 的 `JSValue`。
/// 每个 `MRubyValue` 都来自特定的 `MRubyContext`，不能跨上下文传递。
public struct MRubyValue: @unchecked Sendable {

    let raw: mrb_value

    /// 产生本值的上下文。
    public let context: MRubyContext

    private var mrb: UnsafeMutablePointer<mrb_state> { context.mrb }

    init(raw: mrb_value, context: MRubyContext) {
        self.raw = raw
        self.context = context
    }

    // MARK: - 类型判断

    public var isNil:       Bool { mrb_bridge_nil_p(raw) }
    public var isTrue:      Bool { mrb_bridge_true_p(raw) }
    public var isFalse:     Bool { mrb_bridge_false_p(raw) }
    public var isBool:      Bool { mrb_bridge_bool_p(raw) }
    public var isInt:       Bool { mrb_bridge_integer_p(raw) }
    public var isFloat:     Bool { mrb_bridge_float_p(raw) }
    public var isString:    Bool { mrb_bridge_string_p(raw) }
    public var isArray:     Bool { mrb_bridge_array_p(raw) }
    public var isHash:      Bool { mrb_bridge_hash_p(raw) }
    public var isSymbol:    Bool { mrb_bridge_symbol_p(raw) }
    public var isObject:    Bool { mrb_bridge_object_p(raw) }
    public var isException: Bool { mrb_bridge_exception_p(raw) }
    public var isRange:     Bool { mrb_bridge_range_p(raw) }
    public var isProc:      Bool { mrb_bridge_proc_p(raw) }
    public var isClass:     Bool { mrb_bridge_class_p(raw) }
    public var isModule:    Bool { mrb_bridge_module_p(raw) }
    public var isData:      Bool { mrb_bridge_data_p(raw) }
    public var isFiber:     Bool { mrb_bridge_fiber_p(raw) }
    public var isUndefined: Bool { mrb_bridge_undef_p(raw) }

    /// 值是否为数值（Integer 或 Float）。
    /// 对应 JSValue 的 `isNumber`。
    public var isNumber: Bool { isInt || isFloat }

    /// 值是否为非基本类型的 Ruby 对象（Object 实例）。
    /// 对于 nil、true、false、Integer、Float、Symbol 等立即值返回 `false`。
    /// 对应 JSValue 的 `isObject`。
    public var isRubyObject: Bool {
        !isNil && !isTrue && !isFalse && !isBool && !isInt && !isFloat && !isSymbol && !isUndefined
    }

    /// 值的运行时类型分类。
    /// 对应 JSValue 无直接属性，但 C API 中有 `JSValueGetType`。
    public var mrubyType: MRubyType {
        if isNil       { return .nilValue }
        if isFalse     { return .bool }
        if isTrue      { return .bool }
        if isUndefined { return .undefined }
        return MRubyType(mrbTypeValue: raw)
    }

    /// 值是否为 Ruby `Time` 对象（若 mruby-time gem 已加载）。
    /// 对应 JSValue 的 `isDate`。
    public var isDate: Bool {
        guard isObject else { return false }
        // 检查 class.name 是否为 "Time"
        let classVal = call(method: "class")
        let nameVal = classVal.call(method: "name")
        return nameVal.toString() == "Time"
    }

    // MARK: - 类型转换（对应 JSValue 的 to* 方法）

    /// 转为 Swift `String`（调用 Ruby `#to_s`）。
    /// 对于非 String 类型，通过 `mrb_funcall` 调用 Ruby 层 `to_s`。
    public func toString() -> String {
        if isString {
            var v = raw
            guard let cstr = mrb_string_value_cstr(mrb, &v) else { return "" }
            return String(cString: cstr)
        }
        // 非 String 类型：调用 Ruby #to_s
        let sym = "to_s".withCString { mrb_intern_cstr(mrb, $0) }
        let strVal = mrb_funcall_argv(mrb, raw, sym, 0, nil)
        guard let cstr = mrb_str_to_cstr(mrb, strVal) else { return "" }
        return String(cString: cstr)
    }

    /// 转为 Swift `Int`。
    public func toInt() -> Int {
        Int(mrb_bridge_integer(raw))
    }

    /// 转为 Swift `Double`。
    public func toDouble() -> Double {
        if isFloat { return Double(mrb_bridge_float(raw)) }
        if isInt   { return Double(mrb_bridge_integer(raw)) }
        return Double.nan
    }

    /// 转为 Swift `Bool`（Ruby 的真值规则：只有 `false` 和 `nil` 为假）。
    public func toBool() -> Bool {
        mrb_bridge_test(raw)
    }

    /// 转为 Swift `[MRubyValue]`（仅当值为 Ruby Array 时有意义）。
    public func toArray() -> [MRubyValue] {
        guard isArray else { return [] }
        let len = Int(mrb_bridge_ary_len(raw))
        return (0 ..< len).map { i in
            MRubyValue(raw: mrb_ary_entry(raw, mrb_int(i)), context: context)
        }
    }

    /// 转为 Swift `[MRubyValue: MRubyValue]`（仅当值为 Ruby Hash 时有意义）。
    ///
    /// key 的 `Hashable` 实现以 `inspect()` 字符串为依据，参见下方 `Hashable` 扩展。
    public func toDictionary() -> [MRubyValue: MRubyValue] {
        guard isHash else { return [:] }
        let keysVal = MRubyValue(raw: mrb_hash_keys(mrb, raw), context: context)
        let keys = keysVal.toArray()
        var dict: [MRubyValue: MRubyValue] = Dictionary(minimumCapacity: keys.count)
        for key in keys {
            let val = MRubyValue(raw: mrb_hash_get(mrb, raw, key.raw), context: context)
            dict[key] = val
        }
        return dict
    }

    /// 将 Ruby Symbol 转换为名称字符串。非 Symbol 类型返回 `nil`。
    public func toSymbol() -> String? {
        guard isSymbol else { return nil }
        // mrb_symbol(v) 是函数式宏，无法直接调用；
        // 通过 #to_s 让 Ruby 返回 Symbol 名称（不含冒号前缀），
        // 或者调用 #name / #id2name（mruby Symbol 支持 to_s）。
        let sym = "to_s".withCString { mrb_intern_cstr(mrb, $0) }
        let strVal = mrb_funcall_argv(mrb, raw, sym, 0, nil)
        guard let cstr = mrb_str_to_cstr(mrb, strVal) else { return nil }
        return String(cString: cstr)
    }

    /// Ruby `#inspect` 字符串，便于调试。
    public func inspect() -> String {
        guard let cstr = mrb_str_to_cstr(mrb, mrb_inspect(mrb, raw)) else { return "?" }
        return String(cString: cstr)
    }

    /// 转为 Swift `Double`（数值类型通用转换）。
    /// 对应 JSValue 的 `toNumber()`。
    /// 对于 Int 和 Float 均有效；非数值类型返回 `Double.nan`。
    public func toNumber() -> Double {
        if isFloat { return Double(mrb_bridge_float(raw)) }
        if isInt   { return Double(mrb_bridge_integer(raw)) }
        return Double.nan
    }

    /// 若值为 Ruby `Time` 对象，转为 Swift `Date`。
    /// 对应 JSValue 的 `toDate()`。
    /// 通过调用 `#to_i`（秒）和 `#usec`（微秒）构造 `Date`。
    /// - Returns: 若值为 Time 对象返回 `Date`；否则返回 `nil`。
    public func toDate() -> Date? {
        guard isDate else { return nil }
        let sec  = call(method: "to_i").toInt()
        let usec = call(method: "usec").toInt()
        let interval = TimeInterval(sec) + TimeInterval(usec) / 1_000_000.0
        return Date(timeIntervalSince1970: interval)
    }

    // MARK: - 实例检查与响应（对应 JSValue 的 isInstanceOf / 以及 Ruby 的 respond_to?）

    /// 检查值是否为指定类/模块的实例（Ruby `is_a?`）。
    ///
    /// 对应 JSValue 的 `isInstance(of:)`。
    /// ```swift
    /// let isStr = value.isInstance(of: MRubyValue.from(String.self, in: ctx))
    /// ```
    /// - Parameter classValue: 代表类或模块的 `MRubyValue`。
    /// - Returns: 若接收者是该类/模块的实例返回 `true`。
    public func isInstance(of classValue: MRubyValue) -> Bool {
        guard mrb_bridge_class_p(classValue.raw) || mrb_bridge_module_p(classValue.raw) else {
            return false
        }
        guard let rclass = mrb_bridge_class_ptr(classValue.raw) else { return false }
        return mrb_bridge_obj_is_kind_of(mrb, raw, rclass)
    }

    /// 检查对象是否响应指定的方法（Ruby `respond_to?`）。
    ///
    /// 对应 JSValue 的 `hasProperty(_:)`。
    /// - Parameter selector: 方法名。
    /// - Returns: 若对象响应该方法返回 `true`。
    public func responds(to selector: String) -> Bool {
        let sym = selector.withCString { mrb_intern_cstr(mrb, $0) }
        return mrb_bridge_respond_to(mrb, raw, sym)
    }

    /// 检查属性或方法是否存在。
    /// 对应 JSValue 的 `hasProperty(_:)`。
    /// - Parameter name: 属性名或方法名。
    /// - Returns: 是否存在。
    public func hasProperty(_ name: String) -> Bool {
        responds(to: name)
    }

    /// 删除指定的属性或方法。
    /// 对应 JSValue 的 `deleteProperty(_:)`。
    /// 在 Ruby 中通过 `remove_method` 实现（仅对类/模块有效）。
    /// - Parameter name: 要删除的方法名。
    /// - Returns: 是否成功删除。
    @discardableResult
    public func deleteProperty(_ name: String) -> Bool {
        guard isClass || isModule else { return false }
        // 获取 singleton class（用于类方法）
        let singletonClass = mrb_singleton_class_ptr(mrb, raw)
        if let singletonClass {
            name.withCString { cName in
                mrb_undef_method(mrb, singletonClass, cName)
            }
        }
        // 同时在类本身上 undef（用于实例方法）
        let rclass = mrb_bridge_class_ptr(raw)
        if let rclass {
            name.withCString { cName in
                mrb_undef_method(mrb, rclass, cName)
            }
        }
        return mrb.pointee.exc == nil
    }

    /// 检查两个值是否严格相等（Ruby `equal?`，即对象身份）。
    ///
    /// 对应 JSValue 的 `isEqual(to:)` 的行为差异：
    /// - `==` / `isEqual(to:)` 检查值相等（Ruby `==`）
    /// - `isIdentical(to:)` 检查对象身份（Ruby `equal?`）
    ///
    /// 对应 JavaScriptCore 的 `JSValueIsStrictEqual`。
    /// - Parameter other: 要比较的值。
    /// - Returns: 是否为同一个对象。
    public func isIdentical(to other: MRubyValue) -> Bool {
        let sym = "equal?".withCString { mrb_intern_cstr(mrb, $0) }
        var argv = [other.raw]
        let result = argv.withUnsafeMutableBufferPointer { buf in
            mrb_funcall_argv(mrb, raw, sym, mrb_int(buf.count), buf.baseAddress)
        }
        if mrb.pointee.exc != nil {
            mrb.pointee.exc = nil
            return false
        }
        return MRubyValue(raw: result, context: context).toBool()
    }

    /// 宽松比较（Ruby `==` 允许类型转换）。
    ///
    /// 对应 JSValue 的 `isEqualWithTypeCoercion(to:)`。
    /// 当前 `==` 运算符已使用 `inspect()` 字符串比较，
    /// 此方法提供真正的 Ruby `==` 语义。
    /// - Parameter other: 要比较的值。
    /// - Returns: 是否相等。
    public func isEqualWithTypeCoercion(to other: MRubyValue) -> Bool {
        let sym = "==".withCString { mrb_intern_cstr(mrb, $0) }
        var argv = [other.raw]
        let result = argv.withUnsafeMutableBufferPointer { buf in
            mrb_funcall_argv(mrb, raw, sym, mrb_int(buf.count), buf.baseAddress)
        }
        if mrb.pointee.exc != nil {
            mrb.pointee.exc = nil
            return false
        }
        return MRubyValue(raw: result, context: context).toBool()
    }

    /// 比较当前值与另一个值的关系（Ruby `<=>` 运算符）。
    ///
    /// 对应 JavaScriptCore 中 `JSValue` 的比较方法，返回 `MRubyRelationCondition`。
    ///
    /// ```swift
    /// let a = MRubyValue.from(42, in: ctx)
    /// let b = MRubyValue.from(100, in: ctx)
    /// a.relation(to: b)  // .lessThan
    /// b.relation(to: a)  // .greaterThan
    /// a.relation(to: a)  // .equal
    /// ```
    /// - Parameter other: 要比较的另一个值。
    /// - Returns: 比较结果。若值不可比较（例如不同类型），返回 `.undefined`。
    public func relation(to other: MRubyValue) -> MRubyRelationCondition {
        let spaceship = "<=>".withCString { mrb_intern_cstr(mrb, $0) }
        var argv = [other.raw]
        let result = argv.withUnsafeMutableBufferPointer { buf in
            mrb_funcall_argv(mrb, raw, spaceship, mrb_int(buf.count), buf.baseAddress)
        }
        if mrb.pointee.exc != nil {
            mrb.pointee.exc = nil
            return .undefined
        }
        let resultVal = MRubyValue(raw: result, context: context)
        return MRubyRelationCondition(spaceshipValue: resultVal)
    }

    /// 直接与 Swift `Double` 比较。
    /// 对应 JSValue 的 `compare(_:)` 的 Double 重载。
    public func compare(_ other: Double) -> MRubyRelationCondition {
        let otherVal = MRubyValue.from(other, in: context)
        return relation(to: otherVal)
    }

    /// 直接与 Swift `Int64` 比较。
    /// 对应 JSValue 的 `compare(_:)` 的 Int64 重载。
    public func compare(_ other: Int64) -> MRubyRelationCondition {
        let otherVal = MRubyValue.from(Int(other), in: context)
        return relation(to: otherVal)
    }

    /// 直接与 Swift `UInt64` 比较。
    /// 对应 JSValue 的 `compare(_:)` 的 UInt64 重载。
    public func compare(_ other: UInt64) -> MRubyRelationCondition {
        let otherVal = MRubyValue.from(Int(other), in: context)
        return relation(to: otherVal)
    }

    // MARK: - 构造调用（对应 JSValue 的 constructWithArguments:）

    /// 将当前值作为构造函数调用（Ruby `Class.new`）。
    ///
    /// 对应 JSValue 的 `construct(withArguments:)`。
    /// 适用于 `MRubyValue` 代表一个类的情况。
    /// - Parameter arguments: 传入构造函数的参数。
    /// - Returns: 新创建的对象实例。
    @discardableResult
    public func construct(with arguments: [MRubyValue] = []) -> MRubyValue {
        guard mrb_bridge_class_p(raw), let rclass = mrb_bridge_class_ptr(raw) else {
            return MRubyValue(raw: mrb_nil_value(), context: context)
        }
        var argv = arguments.map(\.raw)
        let result: mrb_value
        if argv.isEmpty {
            result = mrb_obj_new(mrb, rclass, 0, nil)
        } else {
            result = argv.withUnsafeMutableBufferPointer { buf in
                mrb_obj_new(mrb, rclass, mrb_int(buf.count), buf.baseAddress)
            }
        }
        if mrb.pointee.exc != nil {
            mrb.pointee.exc = nil
            return MRubyValue(raw: mrb_nil_value(), context: context)
        }
        return MRubyValue(raw: result, context: context)
    }

    // MARK: - 属性访问（对应 JSValue 的 forProperty: / setValue:forProperty:）

    /// 通过方法名读写属性（调用 Ruby getter/setter）。
    ///
    /// 对应 JSValue 的 `forProperty:` / `setValue:forProperty:`。
    ///
    /// ```swift
    /// let name = obj["name"]               // 等价于 obj.call(method: "name")
    /// obj["name"] = .from("world", in: ctx) // 等价于 obj.call(method: "name=", arguments: [.from("world", in: ctx)])
    /// ```
    public subscript(property: String) -> MRubyValue {
        get { call(method: property) }
        set {
            let setterName = "\(property)="
            _ = call(method: setterName, arguments: [newValue])
        }
    }

    // MARK: - 属性定义

    /// 属性描述符的键，用于 `defineProperty(_:descriptor:)`。
    ///
    /// 对应 JSValue 的 Property Descriptor Keys 常量。
    public struct MRubyPropertyDescriptor: Sendable {
        /// getter 方法名（若为 nil 则使用属性名）。
        public var getter: String?
        /// setter 方法名（若为 nil 则生成 `属性名=`）。
        public var setter: String?
        /// 是否为只读（不生成 setter）。
        public var readonly: Bool

        public init(getter: String? = nil, setter: String? = nil, readonly: Bool = false) {
            self.getter = getter
            self.setter = setter
            self.readonly = readonly
        }
    }

    /// 在 JavaScript 对象上定义或修改属性。
    ///
    /// 对应 JSValue 的 `defineProperty(_:descriptor:)`。
    /// 在 mruby 中通过 Ruby 的 `attr_accessor` / `attr_reader` 实现。
    /// - Parameters:
    ///   - name: 属性名。
    ///   - descriptor: 属性描述符。
    public func defineProperty(_ name: String, descriptor: MRubyPropertyDescriptor) {
        guard isClass || isModule else { return }

        // 通过 class_eval 在类上下文中调用 attr_reader/attr_accessor
        // （attr_accessor 是私有方法，不能直接通过 call 调用）
        let methodName = descriptor.readonly ? "attr_reader" : "attr_accessor"
        let code = "\(methodName) :\(name)"
        _ = call(method: "class_eval", arguments: [MRubyValue.from(code, in: context)])
        mrb.pointee.exc = nil
    }

    /// 通过整数索引访问数组元素。
    ///
    /// ```swift
    /// let first = arr[0]           // 等价于 arr.call(method: "[]", arguments: [.from(0, in: ctx)])
    /// arr[0] = .from(42, in: ctx)  // 等价于 arr.call(method: "[]=", arguments: [.from(0, in: ctx), .from(42, in: ctx)])
    /// ```
    public subscript(index: Int) -> MRubyValue {
        get {
            let idxVal = MRubyValue.from(index, in: context)
            return call(method: "[]", arguments: [idxVal])
        }
        set {
            let idxVal = MRubyValue.from(index, in: context)
            _ = call(method: "[]=", arguments: [idxVal, newValue])
        }
    }

    /// 通过 `mrb_value` 类型的键访问 Hash/Array 元素。
    ///
    /// ```swift
    /// let val = dict[key]                    // 等价于 obj.call(method: "[]", arguments: [key])
    /// dict[key] = .from(42, in: ctx)         // 等价于 obj.call(method: "[]=", arguments: [key, .from(42, in: ctx)])
    /// ```
    public subscript(key: MRubyValue) -> MRubyValue {
        get { call(method: "[]", arguments: [key]) }
        set { _ = call(method: "[]=", arguments: [key, newValue]) }
    }

    // MARK: - 方法调用别名

    /// 调用 Ruby 方法的别名，更接近 JSValue 的 `invokeMethod(_:withArguments:)`。
    ///
    /// 等价于 `call(method:withArguments:)`。
    @discardableResult
    public func invokeMethod(_ method: String, with arguments: [MRubyValue] = []) -> MRubyValue {
        call(method: method, arguments: arguments)
    }

    // MARK: - 静态构造方法（对应 JSValue.value(with:in:)）

    /// 从 Swift `String` 构造 mruby String 值。
    public static func from(_ string: String, in context: MRubyContext) -> MRubyValue {
        let raw = string.withCString { mrb_str_new_cstr(context.mrb, $0) }
        return MRubyValue(raw: raw, context: context)
    }

    /// 从 Swift `Int` 构造 mruby Integer 值。
    public static func from(_ int: Int, in context: MRubyContext) -> MRubyValue {
        let raw = mrb_int_value(context.mrb, mrb_int(int))
        return MRubyValue(raw: raw, context: context)
    }

    /// 从 Swift `Double` 构造 mruby Float 值。
    public static func from(_ double: Double, in context: MRubyContext) -> MRubyValue {
        let raw = mrb_float_value(context.mrb, mrb_float(double))
        return MRubyValue(raw: raw, context: context)
    }

    /// 从 Swift `Bool` 构造 mruby true/false 值。
    public static func from(_ bool: Bool, in context: MRubyContext) -> MRubyValue {
        let raw = mrb_bool_value(bool)
        return MRubyValue(raw: raw, context: context)
    }

    /// 从 Swift `[MRubyValue]` 构造 mruby Array 值。
    public static func from(_ array: [MRubyValue], in context: MRubyContext) -> MRubyValue {
        let ary = mrb_ary_new(context.mrb)
        let pushSym = "push".withCString { mrb_intern_cstr(context.mrb, $0) }
        for element in array {
            var arg = element.raw
            withUnsafeMutablePointer(to: &arg) { ptr in
                _ = mrb_funcall_argv(context.mrb, ary, pushSym, 1, ptr)
            }
        }
        return MRubyValue(raw: ary, context: context)
    }

    /// 构造 mruby `nil` 值。
    /// 对应 JavaScript 的 `null`。
    public static func `nil`(in context: MRubyContext) -> MRubyValue {
        MRubyValue(raw: mrb_nil_value(), context: context)
    }

    /// 构造 mruby undefined 值（`MRB_TT_UNDEF`）。
    ///
    /// 对应 JavaScript 的 `undefined`（而 `nil` 对应 `null`）。
    /// 在 Ruby 层面通常不直接使用，但可通过 C API 创建和传递。
    /// 可用 `isUndefined` 检查。
    public static func `undefined`(in context: MRubyContext) -> MRubyValue {
        MRubyValue(raw: mrb_bridge_undef_value(), context: context)
    }

    /// 从名称字符串构造 mruby Symbol 值。
    public static func symbol(_ name: String, in context: MRubyContext) -> MRubyValue {
        let sym = name.withCString { mrb_intern_cstr(context.mrb, $0) }
        return MRubyValue(raw: mrb_symbol_value(sym), context: context)
    }

    /// 从 Swift `UInt32` 构造 mruby Integer 值。
    /// 对应 JSValue 的 `init(uint32:in:)`。
    public static func from(_ uint32: UInt32, in context: MRubyContext) -> MRubyValue {
        let raw = mrb_int_value(context.mrb, mrb_int(uint32))
        return MRubyValue(raw: raw, context: context)
    }

    /// 从 Swift `Int64` 构造 mruby Integer 值。
    /// 对应 JSValue 的 `init(int64:in:)` 的 C API 等价。
    public static func from(_ int64: Int64, in context: MRubyContext) -> MRubyValue {
        let raw = mrb_int_value(context.mrb, mrb_int(int64))
        return MRubyValue(raw: raw, context: context)
    }

    /// 从 Swift `UInt64` 构造 mruby Integer 值。
    /// 对应 JSValue 的 `init(uint64:in:)` 的 C API 等价。
    public static func from(_ uint64: UInt64, in context: MRubyContext) -> MRubyValue {
        let raw = mrb_int_value(context.mrb, mrb_int(uint64))
        return MRubyValue(raw: raw, context: context)
    }

    /// 从错误消息构造 mruby RuntimeError 值。
    /// 对应 JSValue 的 `init(newErrorFromMessage:in:)`。
    /// - Parameters:
    ///   - message: 错误消息。
    ///   - context: 执行上下文。
    /// - Returns: 代表 `RuntimeError` 的 `MRubyValue`。
    public static func error(_ message: String, in context: MRubyContext) -> MRubyValue {
        let msgVal = message.withCString { mrb_str_new_cstr(context.mrb, $0) }
        let exc = mrb_exc_new_str(context.mrb, context.mrb.pointee.eStandardError_class, msgVal)
        return MRubyValue(raw: exc, context: context)
    }

    /// 从模式和标志构造 mruby Regexp 值。
    /// 对应 JSValue 的 `init(newRegularExpressionFromPattern:flags:in:)`。
    /// - Parameters:
    ///   - pattern: 正则表达式模式字符串。
    ///   - flags: 标志字符串（如 "i" 表示忽略大小写）。
    ///   - context: 执行上下文。
    /// - Returns: 代表 `Regexp` 的 `MRubyValue`。
    public static func regex(_ pattern: String, flags: String = "", in context: MRubyContext) -> MRubyValue? {
        // Regexp 可能未加载（取决于 mruby gem 配置）
        guard mrb_class_defined(context.mrb, "Regexp") else { return nil }
        let options = flags.contains("i") ? 1 : 0  // Regexp::IGNORECASE
        let raw = pattern.withCString { cPattern in
            let regexpClass = mrb_class_get(context.mrb, "Regexp")
            let args = [
                mrb_str_new_cstr(context.mrb, cPattern),
                mrb_int_value(context.mrb, mrb_int(options)),
            ]
            return args.withUnsafeBufferPointer { buf in
                mrb_obj_new(context.mrb, regexpClass, mrb_int(buf.count), buf.baseAddress)
            }
        }
        return MRubyValue(raw: raw, context: context)
    }

    /// 从任意 Swift 对象自动推断并构造 mruby 值。
    /// 对应 JSValue 的 `init(object:in:)`。
    /// 支持类型：String、Int、Double、Bool、[MRubyValue]、[String: MRubyValue]、nil。
    public static func from(_ object: Any?, in context: MRubyContext) -> MRubyValue {
        switch object {
        case let str as String:
            return .from(str, in: context)
        case let int as Int:
            return .from(int, in: context)
        case let double as Double:
            return .from(double, in: context)
        case let bool as Bool:
            return .from(bool, in: context)
        case let uint32 as UInt32:
            return .from(uint32, in: context)
        case let int64 as Int64:
            return .from(int64, in: context)
        case let uint64 as UInt64:
            return .from(uint64, in: context)
        case let array as [MRubyValue]:
            return .from(array, in: context)
        case let dict as [String: MRubyValue]:
            let hash = mrb_hash_new(context.mrb)
            for (k, v) in dict {
                let keyRaw = k.withCString { mrb_str_new_cstr(context.mrb, $0) }
                mrb_hash_set(context.mrb, hash, keyRaw, v.raw)
            }
            return MRubyValue(raw: hash, context: context)
        case let val as MRubyValue:
            return val
        case .none:
            return .nil(in: context)
        default:
            return .nil(in: context)
        }
    }

    // MARK: - 转换为 Swift 对象

    /// 将 mruby 值转换为 Swift `Any` 对象。
    /// 对应 JSValue 的 `toObject()`。
    public func toObject() -> Any {
        if isNil { return NSNull() }
        if isBool { return toBool() }
        if isInt { return toInt() }
        if isFloat { return toDouble() }
        if isString { return toString() }
        if isSymbol { return toSymbol() as Any }
        if isArray { return toArray() }
        if isHash { return toDictionary() }
        return inspect()
    }

    /// 将 mruby 值转换为指定 Swift 类型的对象。
    /// 对应 JSValue 的 `toObjectOf(_:)`。
    /// - Parameter type: 期望的 Swift 类型。
    /// - Returns: 转换后的对象，若无法转换则返回 `nil`。
    public func toObject<T>(of type: T.Type) -> T? {
        switch type {
        case is String.Type:
            return toString() as? T
        case is Int.Type:
            return toInt() as? T
        case is Double.Type:
            return toDouble() as? T
        case is Bool.Type:
            return toBool() as? T
        case is [MRubyValue].Type:
            return toArray() as? T
        case is [MRubyValue: MRubyValue].Type:
            return toDictionary() as? T
        default:
            return nil
        }
    }

    // MARK: - 方法调用（对应 JSValue.call / invokeMethod）

    /// 调用 Ruby 方法，返回结果值。
    ///
    /// 若调用过程中抛出 Ruby 异常，异常会被清除并返回 `nil` 值。
    /// - Parameters:
    ///   - method: 方法名称。
    ///   - arguments: 传入的参数列表（默认为空）。
    /// - Returns: 方法返回值；发生异常时返回 `nil` 值。
    @discardableResult
    public func call(method: String, arguments: [MRubyValue] = []) -> MRubyValue {
        let sym = method.withCString { mrb_intern_cstr(mrb, $0) }
        var argv = arguments.map(\.raw)
        let result: mrb_value
        if argv.isEmpty {
            result = mrb_funcall_argv(mrb, raw, sym, 0, nil)
        } else {
            result = argv.withUnsafeMutableBufferPointer { buf in
                mrb_funcall_argv(mrb, raw, sym, mrb_int(buf.count), buf.baseAddress)
            }
        }
        // 检查并清除异常，失败时返回 nil value
        if mrb.pointee.exc != nil {
            mrb.pointee.exc = nil
            return MRubyValue(raw: mrb_nil_value(), context: context)
        }
        return MRubyValue(raw: result, context: context)
    }

}

// MARK: - CustomStringConvertible

extension MRubyValue: CustomStringConvertible {
    public var description: String { inspect() }
}

// MARK: - Equatable & Hashable
//
// `toDictionary()` 要求 key 实现 Hashable。
// 以 inspect() 字符串作为等价和哈希的依据——这对大多数调试和容器用途已经足够。
// 若需要严格的 Ruby `==` 语义，可改为调用 mrb_funcall(mrb, raw, "==", 1, other.raw)。

extension MRubyValue: Equatable {
    public static func == (lhs: MRubyValue, rhs: MRubyValue) -> Bool {
        lhs.inspect() == rhs.inspect()
    }
}

extension MRubyValue: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(inspect())
    }
}
