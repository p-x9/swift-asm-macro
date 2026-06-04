//
//  AsmSourceText.swift
//
//
//  Created by Codex on 2026/06/05.
//
//

import Foundation

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
