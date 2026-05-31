//
//  AsmAssemblyFailure.swift
//
//
//  Created by Codex on 2026/05/31.
//
//

import Assembly
import Foundation
import SwiftSyntax

struct AsmAssemblyFailure: Error {
    let architecture: AsmArchitecture
    let underlyingMessage: String
    let line: AsmSourceLine?

    var message: String {
        "`Assembler` failed for \(architecture.rawValue): \(underlyingMessage)"
    }

    func anchor(in literal: StringLiteralExprSyntax) -> AsmDiagnosticAnchor? {
        guard let line else {
            return nil
        }

        return AsmSourceMap(literal: literal).anchor(for: line.instructionIndex)
    }
}

struct AsmDiagnosticAnchor {
    let node: Syntax
    let position: AbsolutePosition
}

struct AsmSourceLine {
    let sourceLineNumber: Int
    let instructionIndex: Int
    let instruction: String
}

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

private extension AsmSourceLine {
    var firstToken: String? {
        instruction
            .split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            .first
            .map { String($0).lowercased() }
    }
}

struct AsmSourceText {
    let source: String

    var instructionLines: [AsmSourceLine] {
        var instructionIndex = 0

        return source
            .components(separatedBy: .newlines)
            .enumerated()
            .compactMap { offset, rawLine -> AsmSourceLine? in
                guard let instruction = AsmInstructionLine(rawLine).instruction else {
                    return nil
                }

                instructionIndex += 1
                return AsmSourceLine(
                    sourceLineNumber: offset + 1,
                    instructionIndex: instructionIndex,
                    instruction: instruction
                )
            }
    }
}

struct AsmSourceMap {
    private let literal: StringLiteralExprSyntax

    init(literal: StringLiteralExprSyntax) {
        self.literal = literal
    }

    func anchor(for instructionIndex: Int) -> AsmDiagnosticAnchor? {
        var currentInstructionIndex = 0

        for segment in stringSegments {
            if let anchor = anchor(
                for: instructionIndex,
                in: segment,
                currentInstructionIndex: &currentInstructionIndex
            ) {
                return anchor
            }
        }

        return nil
    }

    private var stringSegments: [StringSegmentSyntax] {
        literal.segments.compactMap { segment in
            guard case let .stringSegment(stringSegment) = segment else {
                return nil
            }

            return stringSegment
        }
    }

    private func anchor(
        for targetInstructionIndex: Int,
        in segment: StringSegmentSyntax,
        currentInstructionIndex: inout Int
    ) -> AsmDiagnosticAnchor? {
        let content = segment.content
        let text = content.text
        var lineStart = text.startIndex
        var lineStartUTF8Offset = 0

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let rawLine = String(text[lineStart..<lineEnd])

            if let instruction = AsmInstructionLine(rawLine).instruction {
                currentInstructionIndex += 1
                if currentInstructionIndex == targetInstructionIndex {
                    return anchor(for: instruction, in: rawLine, content: content, lineStartUTF8Offset: lineStartUTF8Offset)
                }
            }

            guard lineEnd < text.endIndex else {
                break
            }

            let nextLineStart = text.index(after: lineEnd)
            lineStartUTF8Offset += text[lineStart..<nextLineStart].utf8.count
            lineStart = nextLineStart
        }

        return nil
    }

    private func anchor(
        for instruction: String,
        in rawLine: String,
        content: TokenSyntax,
        lineStartUTF8Offset: Int
    ) -> AsmDiagnosticAnchor? {
        guard let instructionRange = rawLine.range(of: instruction) else {
            return nil
        }

        let columnOffset = rawLine[..<instructionRange.lowerBound].utf8.count
        return AsmDiagnosticAnchor(
            node: Syntax(content),
            position: content.positionAfterSkippingLeadingTrivia.advanced(
                by: lineStartUTF8Offset + columnOffset
            )
        )
    }
}

struct AsmInstructionLine {
    let rawLine: String

    init(_ rawLine: String) {
        self.rawLine = rawLine
    }

    var instruction: String? {
        let line = rawLineWithoutLabels
        return line.isEmpty ? nil : line
    }

    private var rawLineWithoutLabels: String {
        var line = lineWithoutComment.trimmingCharacters(in: .whitespacesAndNewlines)

        while let colonIndex = labelColonIndex(in: line) {
            line = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                break
            }
        }

        return line
    }

    private var lineWithoutComment: String {
        var bracketDepth = 0

        for index in rawLine.indices {
            let character = rawLine[index]
            if character == "[" {
                bracketDepth += 1
            }
            if character == "]" {
                bracketDepth = max(0, bracketDepth - 1)
            }
            if bracketDepth == 0 {
                if character == ";" {
                    return String(rawLine[..<index])
                }
                let nextIndex = rawLine.index(after: index)
                if character == "/", nextIndex < rawLine.endIndex, rawLine[nextIndex] == "/" {
                    return String(rawLine[..<index])
                }
            }
        }

        return rawLine
    }

    private func labelColonIndex(in line: String) -> String.Index? {
        var bracketDepth = 0

        for index in line.indices {
            let character = line[index]
            if character == "[" {
                bracketDepth += 1
            }
            if character == "]" {
                bracketDepth = max(0, bracketDepth - 1)
            }
            if bracketDepth == 0, character == ":" {
                return index
            }
            if bracketDepth == 0, character.isWhitespace {
                return nil
            }
        }

        return nil
    }
}
