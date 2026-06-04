//
//  AsmAssemblyFailure.swift
//
//
//  Created by Codex on 2026/05/31.
//
//

import SwiftSyntax

struct AsmAssemblyFailure: Error {
    let architecture: AsmArchitecture
    let underlyingMessage: String
    let line: AsmSourceLine?

    var message: String {
        "`Assembler` failed for \(architecture.rawValue): \(underlyingMessage)"
    }

    func anchor(in literals: [StringLiteralExprSyntax]) -> AsmDiagnosticAnchor? {
        guard let line else {
            return nil
        }

        var currentInstructionIndex = 0
        for sourceLiteral in literals {
            if let anchor = AsmSourceMap(sourceLiteral: sourceLiteral).anchor(
                for: line.instructionIndex,
                currentInstructionIndex: &currentInstructionIndex
            ) {
                return anchor
            }
        }

        return nil
    }
}
