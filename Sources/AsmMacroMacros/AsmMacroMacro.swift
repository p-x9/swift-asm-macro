import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum AsmMacroError: Error, CustomStringConvertible {
    case missingSource
    case nonLiteralSource

    var description: String {
        switch self {
        case .missingSource:
            return "@Asm requires one static string literal argument"
        case .nonLiteralSource:
            return "@Asm currently supports only string literals without interpolation"
        }
    }
}

struct AsmBodyBuilder {
    let source: String

    func build() throws -> [CodeBlockItemSyntax] {
        let bodyItems: CodeBlockItemListSyntax = "\(raw: source)"
        return Array(bodyItems)
    }
}

public struct AsmMacro: BodyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        let source = try sourceString(from: node)
        return try AsmBodyBuilder(source: source).build()
    }

    private static func sourceString(from node: AttributeSyntax) throws -> String {
        guard
            let arguments = node.arguments?.as(LabeledExprListSyntax.self),
            let expression = arguments.first?.expression
        else {
            throw AsmMacroError.missingSource
        }

        guard let literal = expression.as(StringLiteralExprSyntax.self) else {
            throw AsmMacroError.nonLiteralSource
        }

        var source = ""
        for segment in literal.segments {
            guard case .stringSegment(let stringSegment) = segment else {
                throw AsmMacroError.nonLiteralSource
            }
            source += stringSegment.content.text
        }
        return source.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@main
struct AsmMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AsmMacro.self,
    ]
}
