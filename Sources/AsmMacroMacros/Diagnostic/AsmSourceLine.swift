//
//  AsmSourceLine.swift
//
//
//  Created by Codex on 2026/06/05.
//
//

struct AsmSourceLine {
    let sourceLineNumber: Int
    let instructionIndex: Int
    let instruction: String
}

extension AsmSourceLine {
    var firstToken: String? {
        instruction
            .split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            .first
            .map { String($0).lowercased() }
    }
}
