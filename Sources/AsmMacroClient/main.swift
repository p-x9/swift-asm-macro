import Foundation
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


// MARK: - max using conditional select

@Asm(
    "cmp x0, x1",
    "csel x0, x0, x1, ge",
    "ret",
    arch: .arm64
)
func asm_max(_ lhs: Int64, _ rhs: Int64) -> Int64
print("max(120, -42) = \(asm_max(120, -42))")


// MARK: - bit rotation

//@Asm(
//    """
//    ror x0, x0, x1
//    ret
//    """,
//    arch: .arm64
//)
//func asm_rotateRight(_ value: UInt64, _ shift: UInt64) -> UInt64
//print(String(format: "rotateRight(0x%016llx, 8) = 0x%016llx", 0x0123456789abcdef, asm_rotateRight(0x0123456789abcdef, 8)))


// MARK: - count set bits

@Asm(
    """
    fmov d0, x0
    cnt v0.8b, v0.8b
    addv b0, v0.8b
    fmov x0, d0
    and x0, x0, #0xff
    ret
    """,
    arch: .arm64
)
@inline(always)
func asm_popcount(_ value: UInt64) -> UInt64

let value: UInt64 = 0xf0f0_1234_ffff_0001
print(
    String(
        format: "popcount(0x%016llx) = %llu",
        value,
        asm_popcount(value)
    ),
    String(value, radix: 2)
)


// MARK: - sum Int64 buffer

@Asm(
    """
    mov x2, #0
    cbz x1, done
    loop:
      ldr x3, [x0], #8
      add x2, x2, x3
      subs x1, x1, #1
      b.ne loop
    done:
    mov x0, x2
    ret
    """,
    arch: .arm64
)
func asm_sum(_ pointer: UnsafePointer<Int64>, _ count: UInt64) -> Int64

let numbers: [Int64] = [3, 5, 8, 13, 21, 34]
let total = numbers.withUnsafeBufferPointer { buffer in
    asm_sum(buffer.baseAddress!, UInt64(buffer.count))
}
print("sum(\(numbers)) = \(total)")


// MARK: - callback twice

@Asm(
    """
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    
    mov x19, x0
    mov x20, x1
    
    mov x0, x19
    blr x20
    
    mov x0, x19
    blr x20
    
    ldp x29, x30, [sp], #16
    ret
    """,
    arch: .arm64
)
func asm_callTwice(value: UInt64, callback: UnsafeRawPointer)

let callback: @convention(c) (UInt64) -> Void = { value in
    print("callback from asm: \(value)")
}
asm_callTwice(value: 777, callback: unsafeBitCast(callback, to: UnsafeRawPointer.self))

#else
print("AsmMacroClient requires Swift 6.3 or newer.")
#endif
