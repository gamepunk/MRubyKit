# MRubyKit

**Swift 封装 mruby —— 在 Apple 全平台嵌入轻量级 Ruby 运行时**

MRubyKit 提供了一套类似 JavaScriptCore 风格的 Swift API 来操作 mruby 虚拟机，支持 iOS / macOS / tvOS / watchOS / visionOS。

## 特性

- 🚀 **全平台支持** — 基于预编译的 XCFramework，覆盖 Apple 所有平台
- 🧩 **JSC 风格 API** — `MRubyVM` / `MRubyContext` / `MRubyValue` 对应 `JSVirtualMachine` / `JSContext` / `JSValue`
- 🔗 **原生函数桥接** — 通过 trampoline 机制将 Swift 闭包注册为 Ruby 全局方法
- 📦 **Swift 类导出** — 通过 `MRubyExport` 协议将 Swift 类的方法暴露给 Ruby
- 🗑️ **GC 管理** — 支持手动 GC、增量 GC、对象 retain/release
- ✅ **完整测试** — 43 个测试用例覆盖全部 API

## 快速开始

### 作为 SPM 依赖

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/gamepunk/MRubyKit.git", branch: "main"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: ["MRubyKit"]
    ),
]
```

### 基础用法

```swift
import MRubyKit

let vm = try MRubyVM()
let ctx = vm.makeContext()

// 执行 Ruby 代码
let sum = try ctx.eval("1 + 2")
print(sum.toInt())  // 3

// 注册原生函数
ctx.defineGlobalFunction(name: "double") { ctx, args in
    let n = args.first?.toInt() ?? 0
    return .from(n * 2, in: ctx)
}
print(try ctx.eval("double(21)").toInt())  // 42

// 导出 Swift 类
class Calc: MRubyExport {
    static let rubyClassName = "Calc"
    static let rubyMethods: [MRubyMethod] = [
        MRubyMethod(name: "add") { ctx, selfVal, args in
            let a = args.first?.toInt() ?? 0
            let b = args.count > 1 ? args[1].toInt() ?? 0 : 0
            return .from(a + b, in: ctx)
        }
    ]
}
try Calc.register(in: ctx)
print(try ctx.eval("Calc.new.add(40, 2)").toInt())  // 42
```

## 项目结构

```
Sources/
├── CMRuby/              # C 桥接层 (shim.h)
│   ├── empty.c
│   └── include/
│       ├── module.modulemap
│       └── shim.h
└── MRubyKit/            # Swift 封装层
    ├── MRubyVM.swift
    ├── MRubyContext.swift
    ├── MRubyValue.swift
    ├── MRubyError.swift
    ├── MRubyManagedValue.swift
    └── MRubyExport.swift
```

## 构建

### 重新编译 mruby XCFramework

需要先下载 [mruby 4.0.0](https://github.com/mruby/mruby/releases) 源码：

```bash
./scripts/build.sh /path/to/mruby-4.0.0
```

## 系统要求

- Swift 6.0+
- Xcode 16.0+
- macOS 12.0+ (开发)
- 部署目标：iOS 12.0+ / macOS 12.0+ / tvOS 12.0+ / watchOS 4.0+ / visionOS 1.0+

## 许可证

MIT
