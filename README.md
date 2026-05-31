# swift-asm-macro

A Swift macro that lets you write inline assembly and attach the assembled machine code directly to a Swift function.

The assembly is assembled **at compile time** and embedded into the binary's `__TEXT,__text` section, so calling the function jumps straight into your hand-written instructions — no runtime assembler, no JIT.

<!-- # Badges -->

[![Github issues](https://img.shields.io/github/issues/p-x9/swift-asm-macro)](https://github.com/p-x9/swift-asm-macro/issues)
[![Github forks](https://img.shields.io/github/forks/p-x9/swift-asm-macro)](https://github.com/p-x9/swift-asm-macro/network/members)
[![Github stars](https://img.shields.io/github/stars/p-x9/swift-asm-macro)](https://github.com/p-x9/swift-asm-macro/stargazers)
[![Github top language](https://img.shields.io/github/languages/top/p-x9/swift-asm-macro)](https://github.com/p-x9/swift-asm-macro/)

## Features

- Write raw assembly inline as a Swift string literal
- Assemble to machine code at compile time via [swift-assembler](https://github.com/swiftbin/swift-assembler)
- Embed the bytes into `__TEXT,__text` and call them through the C calling convention
- Compile-time diagnostics for unsupported functions, types, and architectures
- Currently targets `arm64`

## Usage

Attach `@Asm` to a **bodyless**, top-level function. Pass the assembly source as a static string literal and (optionally) the target architecture.

```swift
import AsmMacro

@Asm(
    """
    add x0, x0, x1
    ret
    """,
    arch: .arm64
)
func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64

print(add(10, 32)) // 42
```

The `arch` argument defaults to `.arm64`, so it can be omitted:

```swift
@Asm("ret")
func noop()
```

## How it works

`@Asm` is a combined [peer](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) and [body](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0415-function-body-macros.md) macro. For a single declaration it generates two things:

1. **A peer storage variable** holding the assembled bytes.
   The source is assembled at compile time, packed into a tuple of words, and placed in the executable's code section:

   ```swift
   @used
   @section("__TEXT,__text")
   nonisolated(unsafe) var __asm_add: (UInt32, UInt32) = (
       0x8b010000,
       0xd65f03c0
   )
   ```

2. **A function body** that reinterprets the address of that storage as a C function pointer and calls it:

   ```swift
   func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
       typealias __AsmFn = @convention(c) (UInt64, UInt64) -> UInt64
       let f = withUnsafePointer(to: &__asm_add) {
           unsafeBitCast($0, to: __AsmFn.self)
       }
       return f(lhs, rhs)
   }
   ```

Because the bytes live in `__TEXT,__text`, the pointer is executable and arguments are passed according to the platform C ABI. On `arm64` the macro also verifies that the assembler emitted a whole number of 4-byte instruction words.

### Why `@section` / `@used`

The storage placement relies on [SE-0492 "Section Placement Control"](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0492-section-control.md) (Swift 6.3):

- `@section("__TEXT,__text")` emits the machine-code bytes into the executable code section, statically initialized at compile time.
- `@used` disables dead-code elimination so the symbol survives even though nothing in Swift references its value directly.

Because the code is baked into the binary at build time, this is **not JIT**. There is no runtime code generation and no need to allocate executable memory at runtime, so it works under the same constraints as any normally-compiled function — including environments where dynamically allocating or marking memory as executable is forbidden (e.g. the App Store sandbox / W^X). The instructions ship as part of the signed binary, just like the rest of your code.

## Supported signatures

Parameters and return types are lowered through a v1 C ABI mapping. The following types are supported:

- Integers: `Int`, `Int8`, `Int16`, `Int32`, `Int64`, `UInt`, `UInt8`, `UInt16`, `UInt32`, `UInt64`
- Floating point: `Float`, `Double`
- Pointers: `UnsafePointer<T>`, `UnsafeMutablePointer<T>`, `UnsafeRawPointer`, `UnsafeMutableRawPointer`, `OpaquePointer`
- `Void` return

## Limitations

`@Asm` reports a compile-time error for declarations it cannot handle:

- Must be attached to a **function** declaration
- The function must be **top-level** (not nested in a type or extension)
- The function must **not** declare its own body
- `async`, `throws`, and generic functions are not supported
- Unnamed parameters are not supported
- The assembly source must be a **static** string literal
- Only `arm64` is currently assembled (`x86_64` is accepted by the parser but not yet implemented)

## Requirements

- Swift 6.3 or newer (function body macros)
- Apple platforms (macOS 13+, iOS 16+, tvOS 16+, watchOS 9+, macCatalyst 16+)

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/p-x9/swift-asm-macro.git", branch: "main"),
```

and add `AsmMacro` to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "AsmMacro", package: "swift-asm-macro"),
    ]
),
```

## Related Projects

- [swift-assembler](https://github.com/swiftbin/swift-assembler) — the assembler backend used to turn assembly source into machine code

## License

swift-asm-macro is released under the MIT License. See [LICENSE](./LICENSE)
