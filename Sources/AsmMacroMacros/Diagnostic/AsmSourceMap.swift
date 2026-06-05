//
//  AsmSourceMap.swift
//
//
//  Created by Codex on 2026/06/05.
//
//

import SwiftSyntax

struct AsmSourceMap {
    private let sourceLiteral: StringLiteralExprSyntax

    init(sourceLiteral: StringLiteralExprSyntax) {
        self.sourceLiteral = sourceLiteral
    }

    func anchor(
        for instructionIndex: Int,
        currentInstructionIndex: inout Int
    ) -> AsmDiagnosticAnchor? {
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
        sourceLiteral.segments.compactMap { segment in
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
                    return anchor(
                        for: instruction,
                        in: rawLine,
                        content: content,
                        lineStartUTF8Offset: lineStartUTF8Offset
                    )
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
