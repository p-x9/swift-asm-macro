//
//  AsmInstructionLine.swift
//
//
//  Created by Codex on 2026/06/05.
//
//

import Foundation

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
