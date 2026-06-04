//
//  AsmAssemblyFailureLocator.swift
//
//
//  Created by Codex on 2026/06/05.
//
//

import Assembly

enum AsmAssemblyFailureLocator {
    static func locate(
        source: String,
        architecture: AsmArchitecture,
        error: any Error
    ) -> AsmAssemblyFailure {
        let sourceLines = AsmSourceText(source: source).instructionLines
        let message = String(describing: error)
        let line = firstLineFailingLikeOriginalError(
            in: sourceLines,
            architecture: architecture,
            expectedMessage: message
        ) ?? lineMatchingErrorDetails(in: sourceLines, error: error)

        return AsmAssemblyFailure(
            architecture: architecture,
            underlyingMessage: message,
            line: line
        )
    }

    private static func firstLineFailingLikeOriginalError(
        in sourceLines: [AsmSourceLine],
        architecture: AsmArchitecture,
        expectedMessage: String
    ) -> AsmSourceLine? {
        for sourceLine in sourceLines {
            do {
                _ = try assembleSingleLine(sourceLine.instruction, architecture: architecture)
            } catch {
                if String(describing: error) == expectedMessage {
                    return sourceLine
                }
            }
        }

        return nil
    }

    private static func assembleSingleLine(_ instruction: String, architecture: AsmArchitecture) throws -> [UInt8] {
        switch architecture {
        case .arm64:
            return try ARM64Assembler.assemble(instruction)
        case .x86_64:
            throw AsmMacroDiagnostic.unsupportedArchitecture("x86_64")
        }
    }

    private static func lineMatchingErrorDetails(
        in sourceLines: [AsmSourceLine],
        error: any Error
    ) -> AsmSourceLine? {
        guard let assemblerError = error as? AssemblerError else {
            return nil
        }

        switch assemblerError {
        case let .unknownInstruction(mnemonic):
            return sourceLines.first { $0.firstToken == mnemonic.lowercased() }
        case let .invalidOperandCount(instruction, _, _),
             let .immediateOutOfRange(instruction, _, _),
             let .immediateAlignment(instruction, _, _),
             let .branchOutOfRange(instruction, _, _):
            return sourceLines.first { $0.firstToken == instruction.lowercased() }
        case let .invalidRegister(text),
             let .invalidImmediate(text),
             let .unsupportedOperand(text),
             let .invalidMemoryOperand(text),
             let .unsupportedShift(text),
             let .unsupportedExtend(text),
             let .unsupportedCondition(text),
             let .labelNotFound(text):
            return sourceLines.first { $0.instruction.localizedCaseInsensitiveContains(text) }
        case .emptyInput, .invalidByteCount, .unknownEncoding:
            return nil
        }
    }
}
