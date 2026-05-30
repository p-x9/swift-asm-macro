import AsmMacro

#if compiler(>=6.3)
@Asm(
    """
    add x0, x0, x1
    ret
    """,
    arch: .arm64
)
func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64

print("The generated answer is \(add(10, 32))")
#else
print("AsmMacroClient requires Swift 6.3 or newer.")
#endif
