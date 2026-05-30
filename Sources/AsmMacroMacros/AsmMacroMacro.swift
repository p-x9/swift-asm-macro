//
//  AsmMacroMacro.swift
//
//
//  Created by Codex on 2026/05/31.
//
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct AsmMacro {}

struct AsmArguments {
    let source: String
    let architecture: AsmArchitecture

    static func arguments(
        of node: AttributeSyntax,
        context: some MacroExpansionContext,
        diagnose: Bool
    ) -> AsmArguments? {
        guard case let .argumentList(arguments) = node.arguments,
              let sourceArgument = arguments.first?.expression
        else {
            if diagnose {
                context.diagnose(AsmMacroDiagnostic.missingSource.diagnose(at: node))
            }
            return nil
        }

        guard let stringLiteral = sourceArgument.as(StringLiteralExprSyntax.self),
              let source = stringLiteral.representedLiteralValue
        else {
            if diagnose {
                context.diagnose(AsmMacroDiagnostic.sourceIsNotStatic.diagnose(at: sourceArgument))
            }
            return nil
        }

        var architecture: AsmArchitecture = .arm64
        if let archExpression = arguments.first(where: {
            $0.label?.trimmed.text == "arch"
        })?.expression {
            guard let memberAccess = archExpression.as(MemberAccessExprSyntax.self),
                  let parsedArchitecture = AsmArchitecture(
                    rawValue: memberAccess.declName.baseName.trimmed.text
                  )
            else {
                if diagnose {
                    context.diagnose(AsmMacroDiagnostic.invalidArchitecture.diagnose(at: archExpression))
                }
                return nil
            }
            architecture = parsedArchitecture
        }

        return .init(
            source: source.trimmingCharacters(in: .whitespacesAndNewlines),
            architecture: architecture
        )
    }
}

struct AsmParameter {
    let name: String
    let type: String
}

struct AsmStorageName {
    static func make(functionName: String) -> String {
        return "__asm_\(functionName)"
    }
}

struct AsmFunction {
    let declaration: FunctionDeclSyntax
    let parameters: [AsmParameter]
    let returnType: String
    let storageName: String

    var returnsVoid: Bool {
        ["Void", "()"].contains(returnType)
    }

    var functionType: String {
        let parameterTypes = parameters.map(\.type).joined(separator: ", ")
        return "(\(parameterTypes)) -> \(returnType)"
    }

    var callArguments: String {
        parameters.map(\.name).joined(separator: ", ")
    }

    static func function(
        of declaration: some DeclSyntaxProtocol,
        arguments: AsmArguments,
        context: some MacroExpansionContext,
        diagnose: Bool
    ) -> AsmFunction? {
        guard let functionDecl = declaration.as(FunctionDeclSyntax.self) else {
            if diagnose {
                context.diagnose(AsmMacroDiagnostic.requiresFunctionDeclaration.diagnose(at: declaration))
            }
            return nil
        }

        guard isTopLevel(context: context) else {
            if diagnose {
                context.diagnose(AsmMacroDiagnostic.requiresTopLevelFunction.diagnose(at: declaration))
            }
            return nil
        }

        guard functionDecl.body == nil else {
            if diagnose {
                context.diagnose(AsmMacroDiagnostic.functionBodyIsNotSupported.diagnose(at: declaration))
            }
            return nil
        }

        if functionDecl.signature.effectSpecifiers?.asyncSpecifier != nil {
            if diagnose {
                context.diagnose(AsmMacroDiagnostic.asyncFunctionIsNotSupported.diagnose(at: declaration))
            }
            return nil
        }

        if functionDecl.signature.effectSpecifiers?.throwsClause != nil {
            if diagnose {
                context.diagnose(AsmMacroDiagnostic.throwingFunctionIsNotSupported.diagnose(at: declaration))
            }
            return nil
        }

        if functionDecl.genericParameterClause != nil || functionDecl.genericWhereClause != nil {
            if diagnose {
                context.diagnose(AsmMacroDiagnostic.genericFunctionIsNotSupported.diagnose(at: declaration))
            }
            return nil
        }

        var parameters: [AsmParameter] = []
        for parameter in functionDecl.signature.parameterClause.parameters {
            let type = parameter.type.trimmed.description
            guard isSupportedCABIType(parameter.type) else {
                if diagnose {
                    context.diagnose(
                        AsmMacroDiagnostic
                            .unsupportedParameter(type)
                            .diagnose(at: parameter.type)
                    )
                }
                return nil
            }

            guard let name = localName(of: parameter) else {
                if diagnose {
                    context.diagnose(
                        AsmMacroDiagnostic
                            .unnamedParameterIsNotSupported
                            .diagnose(at: parameter)
                    )
                }
                return nil
            }

            parameters.append(.init(name: name, type: type))
        }

        let returnType = functionDecl.signature.returnClause?.type.trimmed.description ?? "Void"
        guard isSupportedCABIType(functionDecl.signature.returnClause?.type) else {
            if diagnose {
                if let type = functionDecl.signature.returnClause?.type {
                    context.diagnose(
                        AsmMacroDiagnostic
                            .unsupportedReturnType(returnType)
                            .diagnose(at: type)
                    )
                } else {
                    context.diagnose(
                        AsmMacroDiagnostic
                            .unsupportedReturnType(returnType)
                            .diagnose(at: functionDecl.signature)
                    )
                }
            }
            return nil
        }

        return .init(
            declaration: functionDecl,
            parameters: parameters,
            returnType: returnType,
            storageName: storageName(for: functionDecl)
        )
    }

    private static func isTopLevel(context: some MacroExpansionContext) -> Bool {
        !context.lexicalContext.dropFirst().contains {
            $0.is(ActorDeclSyntax.self)
                || $0.is(ClassDeclSyntax.self)
                || $0.is(EnumDeclSyntax.self)
                || $0.is(ExtensionDeclSyntax.self)
                || $0.is(ProtocolDeclSyntax.self)
                || $0.is(StructDeclSyntax.self)
        }
    }

    private static func localName(of parameter: FunctionParameterSyntax) -> String? {
        if let secondName = parameter.secondName,
           secondName.text != "_" {
            return secondName.text
        }

        if parameter.firstName.text != "_" {
            return parameter.firstName.text
        }

        return nil
    }

    private static func isSupportedCABIType(_ type: TypeSyntax?) -> Bool {
        guard let type else {
            return true
        }

        let trimmed = type.trimmed.description
        if trimmed == "Void" || trimmed == "()" {
            return true
        }

        guard let identifierType = type.as(IdentifierTypeSyntax.self) else {
            return false
        }

        let name = identifierType.name.trimmed.text
        if ["UnsafePointer", "UnsafeMutablePointer"].contains(name) {
            return identifierType.genericArgumentClause != nil
        }

        if ["UnsafeRawPointer", "UnsafeMutableRawPointer", "OpaquePointer"].contains(name) {
            return identifierType.genericArgumentClause == nil
        }

        return [
            "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Float", "Double"
        ].contains(name) && identifierType.genericArgumentClause == nil
    }

    private static func storageName(for functionDecl: FunctionDeclSyntax) -> String {
        AsmStorageName.make(functionName: functionDecl.name.trimmed.text)
    }
}

extension AsmMacro: BodyMacro {
    public static func expansion<Declaration: DeclSyntaxProtocol & WithOptionalCodeBlockSyntax, Context: MacroExpansionContext>(
        of node: AttributeSyntax,
        providingBodyFor declaration: Declaration,
        in context: Context
    ) throws -> [CodeBlockItemSyntax] {
        guard let arguments = AsmArguments.arguments(of: node, context: context, diagnose: true),
              let function = AsmFunction.function(
                of: declaration,
                arguments: arguments,
                context: context,
                diagnose: true
              )
        else {
            return []
        }

        let invocation = "f(\(function.callArguments))"
        let body = """
        #if \(arguments.architecture.condition)
        typealias __AsmFn = @convention(c) \(function.functionType)
        let f = withUnsafePointer(to: &\(function.storageName)) {
            unsafeBitCast($0, to: __AsmFn.self)
        }
        \(function.returnsVoid ? invocation : "return \(invocation)")
        #else
        #error("@Asm function \(function.declaration.name.trimmed.text) was generated for \(arguments.architecture.rawValue).")
        #endif
        """

        let bodyItems: CodeBlockItemListSyntax = "\(raw: body)"
        return Array(bodyItems)
    }
}

extension AsmMacro: PeerMacro {
    public static func expansion<Declaration: DeclSyntaxProtocol, Context: MacroExpansionContext>(
        of node: AttributeSyntax,
        providingPeersOf declaration: Declaration,
        in context: Context
    ) throws -> [DeclSyntax] {
        guard let arguments = AsmArguments.arguments(of: node, context: context, diagnose: false),
              let function = AsmFunction.function(
                of: declaration,
                arguments: arguments,
                context: context,
                diagnose: false
              )
        else {
            return []
        }

        let machineCode: AsmMachineCode
        do {
            machineCode = try AsmAssembler().assemble(
                arguments.source,
                architecture: arguments.architecture
            )
        } catch let diagnostic as AsmMacroDiagnostic {
            context.diagnose(diagnostic.diagnose(at: node))
            return []
        }

        return [
            """
            #if \(raw: arguments.architecture.condition)
            @used
            @section("__TEXT,__text")
            nonisolated(unsafe) var \(raw: function.storageName): \(raw: machineCode.storageType) = \(raw: machineCode.storageValue)
            #else
            #error("@Asm storage \(raw: function.storageName) was generated for \(raw: arguments.architecture.rawValue).")
            #endif
            """
        ]
    }
}

@main
struct AsmMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AsmMacro.self,
    ]
}
