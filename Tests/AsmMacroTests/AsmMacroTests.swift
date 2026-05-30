import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(AsmMacroMacros)
@testable import AsmMacroMacros

let testMacros: [String: Macro.Type] = [
    "Asm": AsmMacro.self,
]
#endif

final class AsmMacroTests: XCTestCase {
    func testAsmMacroExpandsArm64Function() throws {
        #if canImport(AsmMacroMacros)
        let storageName = AsmStorageName.make(
            functionName: "add"
        )

        assertMacroExpansion(
            """
            @Asm(
                \"\"\"
                add x0, x0, x1
                ret
                \"\"\",
                arch: .arm64
            )
            func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64
            """,
            expandedSource: """
              func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
                #if arch(arm64)
                typealias __AsmFn = @convention(c) (UInt64, UInt64) -> UInt64
                let f = withUnsafePointer(to: &\(storageName)) {
                    unsafeBitCast($0, to: __AsmFn.self)
                }
                return f(lhs, rhs)
                #else
                #error("@Asm function add was generated for arm64.")
                #endif
              }

              #if arch(arm64)
              @used
              @section("__TEXT,__text")
              nonisolated(unsafe) var \(storageName): (UInt32, UInt32) = (
                  0x8b010000,
                  0xd65f03c0
              )
              #else
              #error("@Asm storage \(storageName) was generated for arm64.")
              #endif
              """,
            macros: testMacros,
            indentationWidth: .spaces(2)
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testAsmMacroDefaultsToArm64() throws {
        #if canImport(AsmMacroMacros)
        let storageName = AsmStorageName.make(
            functionName: "noop"
        )

        assertMacroExpansion(
            """
            @Asm("ret")
            func noop()
            """,
            expandedSource: """
              func noop() {
                #if arch(arm64)
                typealias __AsmFn = @convention(c) () -> Void
                let f = withUnsafePointer(to: &\(storageName)) {
                    unsafeBitCast($0, to: __AsmFn.self)
                }
                f()
                #else
                #error("@Asm function noop was generated for arm64.")
                #endif
              }

              #if arch(arm64)
              @used
              @section("__TEXT,__text")
              nonisolated(unsafe) var \(storageName): UInt32 = 0xd65f03c0
              #else
              #error("@Asm storage \(storageName) was generated for arm64.")
              #endif
              """,
            macros: testMacros,
            indentationWidth: .spaces(2)
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testAsmMacroRejectsX86_64Function() throws {
        #if canImport(AsmMacroMacros)
        assertMacroExpansion(
            """
            @Asm(
                \"\"\"
                movq %rdi, %rax
                addq %rsi, %rax
                retq
                \"\"\",
                arch: .x86_64
            )
            func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64
            """,
            expandedSource: """
              func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64
              """,
            diagnostics: [
                DiagnosticSpec(
                    message: "`@Asm` does not currently support x86_64 assembly.",
                    line: 1,
                    column: 1,
                    severity: .error
                )
            ],
            macros: testMacros,
            indentationWidth: .spaces(2)
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testAssemblerUsesSwiftAssemblerBackend() throws {
        #if canImport(AsmMacroMacros)
        let code = try AsmAssembler().assemble(
            """
            add x0, x0, x1
            ret
            """,
            architecture: .arm64
        )

        XCTAssertEqual(code.bytes, [
            0x00, 0x00, 0x01, 0x8b,
            0xc0, 0x03, 0x5f, 0xd6
        ])
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testMakeArm64Word() throws {
        #if canImport(AsmMacroMacros)
        XCTAssertEqual(
            AsmMachineCode.makeWord([0x00, 0x00, 0x01, 0x8b]),
            0x8b010000
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testAsmMacroRejectsInvalidArchitecture() throws {
        #if canImport(AsmMacroMacros)
        assertMacroExpansion(
            """
            @Asm("ret", arch: .riscv64)
            func noop()
            """,
            expandedSource: """
              func noop()
              """,
            diagnostics: [
                DiagnosticSpec(
                    message: "`@Asm` supports only `arch: .arm64` and `arch: .x86_64`.",
                    line: 1,
                    column: 19,
                    severity: .error
                )
            ],
            macros: testMacros,
            indentationWidth: .spaces(2)
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testAsmMacroRejectsUnsupportedParameterType() throws {
        #if canImport(AsmMacroMacros)
        assertMacroExpansion(
            """
            @Asm("ret")
            func bad(_ value: String)
            """,
            expandedSource: """
              func bad(_ value: String)
              """,
            diagnostics: [
                DiagnosticSpec(
                    message: "`@Asm` parameter type `String` is not supported by v1 C ABI lowering.",
                    line: 2,
                    column: 19,
                    severity: .error
                )
            ],
            macros: testMacros,
            indentationWidth: .spaces(2)
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
