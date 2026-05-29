import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(AsmMacroMacros)
import AsmMacroMacros

let testMacros: [String: Macro.Type] = [
    "Asm": AsmMacro.self,
]
#endif

final class AsmMacroTests: XCTestCase {
    func testAsmMacroAddsFunctionBody() throws {
        #if canImport(AsmMacroMacros)
        assertMacroExpansion(
            """
            @Asm("return 42")
            func answer() -> Int
            """,
            expandedSource: """

              func answer() -> Int {
                return 42
              }
              """,
            macros: testMacros,
            indentationWidth: .spaces(2)
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testAsmMacroAddsMultilineFunctionBody() throws {
        #if canImport(AsmMacroMacros)
        assertMacroExpansion(
            #"""
            @Asm("""
            let value = 40 + 2
            return value
            """)
            func answer() -> Int
            """#,
            expandedSource: """

              func answer() -> Int {
                let value = 40 + 2
                return value
              }
              """,
            macros: testMacros,
            indentationWidth: .spaces(2)
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testAsmMacroAddsMethodBody() throws {
        #if canImport(AsmMacroMacros)
        assertMacroExpansion(
            """
            struct ALU {
                @Asm("return lhs + rhs")
                func add(_ lhs: Int, _ rhs: Int) -> Int
            }
            """,
            expandedSource: """
            struct ALU {
                func add(_ lhs: Int, _ rhs: Int) -> Int {
                  return lhs + rhs
                }
            }
            """,
            macros: testMacros,
            indentationWidth: .spaces(2)
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
