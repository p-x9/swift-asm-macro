public enum AsmArchitecture {
    case arm64
    case x86_64
}

/// Attaches machine code assembled from inline assembly to a C ABI-compatible function.
///
///     @Asm(
///         """
///         add x0, x0, x1
///         ret
///         """,
///         arch: .arm64
///     )
///     func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64
@attached(body)
@attached(peer, names: prefixed(__asm_))
public macro Asm(
    _ source: String,
    arch: AsmArchitecture = .arm64
) = #externalMacro(module: "AsmMacroMacros", type: "AsmMacro")
