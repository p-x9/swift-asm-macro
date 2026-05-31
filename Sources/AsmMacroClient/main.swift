import AsmMacro

#if compiler(>=6.3)

// MARK: - add
@Asm(
    """
    add x0, x0, x1
    ret
    """,
    arch: .arm64
)
func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64
print("The generated answer is \(add(13, 32))")


// MARK: - function call

@Asm(
    """
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    blr x1
    ldp x29, x30, [sp], #16
    ret
    """
)
func asm_functionCall(string: UnsafePointer<CChar>, print: UnsafeRawPointer)

var myPrint: (@convention(c) (UnsafePointer<CChar>) -> Void) = { ptr in
    print(String(cString: ptr))
}

"hello".withCString { char in
    let raw = unsafeBitCast(myPrint, to: UnsafeRawPointer.self)
    asm_functionCall(string: char, print: raw)
}

#else
print("AsmMacroClient requires Swift 6.3 or newer.")
#endif
