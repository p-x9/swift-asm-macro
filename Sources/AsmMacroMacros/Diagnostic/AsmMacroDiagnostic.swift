//
//  AsmMacroDiagnostic.swift
//
//
//  Created by Codex on 2026/05/31.
//
//

import SwiftDiagnostics
import SwiftSyntax

enum AsmMacroDiagnostic: Error {
    case missingSource
    case sourceIsNotStatic
    case invalidArchitecture
    case requiresFunctionDeclaration
    case requiresTopLevelFunction
    case functionBodyIsNotSupported
    case asyncFunctionIsNotSupported
    case throwingFunctionIsNotSupported
    case genericFunctionIsNotSupported
    case unsupportedParameter(String)
    case unsupportedReturnType(String)
    case unnamedParameterIsNotSupported
    case unsupportedArchitecture(String)
    case assemblerFailed(AsmAssemblyFailure)
    case invalidAssemblerOutput(String)
}

extension AsmMacroDiagnostic: DiagnosticMessage {
    func diagnose(at node: some SyntaxProtocol, position: AbsolutePosition? = nil) -> Diagnostic {
        Diagnostic(node: Syntax(node), position: position, message: self)
    }

    var message: String {
        switch self {
        case .missingSource:
            return "`@Asm` requires one or more static string literal arguments."
        case .sourceIsNotStatic:
            return "The provided asm source must be static."
        case .invalidArchitecture:
            return "`@Asm` supports only `arch: .arm64` and `arch: .x86_64`."
        case .requiresFunctionDeclaration:
            return "`@Asm` must be attached to a function declaration."
        case .requiresTopLevelFunction:
            return "`@Asm` currently supports only top-level functions."
        case .functionBodyIsNotSupported:
            return "`@Asm` functions must not declare their own body."
        case .asyncFunctionIsNotSupported:
            return "`@Asm` does not support async functions."
        case .throwingFunctionIsNotSupported:
            return "`@Asm` does not support throwing functions."
        case .genericFunctionIsNotSupported:
            return "`@Asm` does not support generic functions."
        case let .unsupportedParameter(type):
            return "`@Asm` parameter type `\(type)` is not supported by v1 C ABI lowering."
        case let .unsupportedReturnType(type):
            return "`@Asm` return type `\(type)` is not supported by v1 C ABI lowering."
        case .unnamedParameterIsNotSupported:
            return "`@Asm` does not support unnamed parameters."
        case let .unsupportedArchitecture(architecture):
            return "`@Asm` does not currently support \(architecture) assembly."
        case let .assemblerFailed(failure):
            return failure.message
        case let .invalidAssemblerOutput(message):
            return message
        }
    }

    var severity: DiagnosticSeverity {
        .error
    }

    var diagnosticID: MessageID {
        MessageID(domain: "Swift", id: "AsmMacro.\(id)")
    }

    private var id: String {
        switch self {
        case .missingSource:
            return "missingSource"
        case .sourceIsNotStatic:
            return "sourceIsNotStatic"
        case .invalidArchitecture:
            return "invalidArchitecture"
        case .requiresFunctionDeclaration:
            return "requiresFunctionDeclaration"
        case .requiresTopLevelFunction:
            return "requiresTopLevelFunction"
        case .functionBodyIsNotSupported:
            return "functionBodyIsNotSupported"
        case .asyncFunctionIsNotSupported:
            return "asyncFunctionIsNotSupported"
        case .throwingFunctionIsNotSupported:
            return "throwingFunctionIsNotSupported"
        case .genericFunctionIsNotSupported:
            return "genericFunctionIsNotSupported"
        case .unsupportedParameter:
            return "unsupportedParameter"
        case .unsupportedReturnType:
            return "unsupportedReturnType"
        case .unnamedParameterIsNotSupported:
            return "unnamedParameterIsNotSupported"
        case .unsupportedArchitecture:
            return "unsupportedArchitecture"
        case .assemblerFailed:
            return "assemblerFailed"
        case .invalidAssemblerOutput:
            return "invalidAssemblerOutput"
        }
    }
}
