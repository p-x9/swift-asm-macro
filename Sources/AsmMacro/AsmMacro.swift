/// Attaches a generated body to a function.
///
/// The current foundation treats the string as Swift statements that should
/// become the function body. The translation point is intentionally isolated in
/// the macro implementation so an asm-like DSL parser can replace it later.
///
///     @Asm("return 42")
///     func answer() -> Int
@attached(body)
public macro Asm(_ source: String) = #externalMacro(module: "AsmMacroMacros", type: "AsmMacro")
