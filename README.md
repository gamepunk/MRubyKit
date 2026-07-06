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

## 使用第三方 mrbgems

[mruby.org/libraries/](https://mruby.org/libraries/) 上有大量社区开发的 mrbgems。

### 原理

mrbgems 是**编译时静态链接**的，与 Ruby 的 `gem install` 不同。需要在编译 `libmruby.a` 时将 gem 加入构建配置。

### Gem 引用方式

| 方式 | 语法 | 说明 |
|------|------|------|
| mgem 列表（推荐） | `conf.gem :mgem => 'mruby-json'` | 从 [mgem-list](https://github.com/mruby/mgem-list) 官方注册表引用，`mruby-` 前缀可省略 |
| GitHub | `conf.gem :github => 'author/repo'` | 直接克隆 GitHub 仓库 |
| Git URL | `conf.gem :git => 'https://...', :branch => 'master'` | 任意 Git 仓库，可指定分支/提交 |
| 本地路径 | `conf.gem '/path/to/gem'` | 已下载到本地的 gem |

### 步骤

#### 方式 A：使用 `build.sh`（快捷方式）

```bash
# 编译所有可用平台（自动检测 SDK）
./scripts/build.sh /path/to/mruby-4.0.0

# 指定输出目录
./scripts/build.sh /path/to/mruby-4.0.0 ./build

# 添加第三方 mgem
GEMS=mruby-json,mruby-yaml ./scripts/build.sh /path/to/mruby-4.0.0
```

#### 方式 B：使用 `Rakefile`（推荐——更强大）

```bash
# 编译并打包 XCFramework
rake -f scripts/Rakefile MRUBY_SRC=/path/to/mruby-4.0.0

# 添加第三方 mgem
rake -f scripts/Rakefile MRUBY_SRC=/path/to/mruby-4.0.0 GEMS=mruby-json,mruby-yaml

# 仅编译不打包
rake -f scripts/Rakefile MRUBY_SRC=/path/to/mruby-4.0.0 compile

# 清理
rake -f scripts/Rakefile MRUBY_SRC=/path/to/mruby-4.0.0 clean
```

#### 方式 C：直接编辑配置（最灵活）

直接编辑 `scripts/Rakefile` 中的 `PLATFORMS` 和 gem 配置：

```ruby
# 添加 gem（Rakefile 第 85 行附近）
GEMS_EXTRA = %w[mruby-json mruby-yaml]
```

3. **（可选）暴露 C API 给 Swift**——如需在 Swift 中直接调用 gem 的 C 函数，在 `Sources/CMRuby/include/shim.h` 中添加 `#include`：

   ```c
   #include <mruby/json.h>
   ```

### 常用 mrbgems

| Gem | mgem 引用 | 功能 |
|-----|-----------|------|
| mruby-json | `conf.gem :mgem => 'mruby-json'` | JSON 解析 |
| mruby-digest | `conf.gem :mgem => 'mruby-digest'` | SHA/MD5 哈希 |
| mruby-uri | `conf.gem :mgem => 'mruby-uri'` | URI 解析 |
| mruby-yaml | `conf.gem :mgem => 'mruby-yaml'` | YAML 解析 |
| mruby-pcre-regexp | `conf.gem :mgem => 'mruby-pcre-regexp'` | PCRE 正则 |

### 在 Ruby 代码中使用

添加 gem 并重新编译后，直接通过 `eval` 使用：

```swift
try ctx.eval("require 'json'")
let parsed = try ctx.eval("JSON.parse('{\"key\": \"value\"}')")
```

## 系统要求

- Swift 6.0+
- Xcode 16.0+
- macOS 12.0+ (开发)
- 部署目标：iOS 12.0+ / macOS 12.0+ / tvOS 12.0+ / watchOS 4.0+ / visionOS 1.0+

## 许可证

MIT
