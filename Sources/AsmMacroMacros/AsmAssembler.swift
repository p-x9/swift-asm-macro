//
//  AsmAssembler.swift
//
//
//  Created by Codex on 2026/05/31.
//
//

import Assembly
import Foundation

enum AsmArchitecture: String {
    case arm64
    case x86_64

    var condition: String {
        switch self {
        case .arm64:
            return "arch(arm64)"
        case .x86_64:
            return "arch(x86_64)"
        }
    }
}

struct AsmMachineCode {
    let architecture: AsmArchitecture
    let bytes: [UInt8]

    var storageType: String {
        switch architecture {
        case .arm64:
            return tupleType(of: "UInt32", count: words.count)
        case .x86_64:
            return tupleType(of: "UInt8", count: bytes.count)
        }
    }

    var storageValue: String {
        switch architecture {
        case .arm64:
            return tupleValue(words.map { String(format: "0x%08x", $0) })
        case .x86_64:
            return tupleValue(bytes.map { String(format: "0x%02x", $0) })
        }
    }

    var words: [UInt32] {
        guard architecture == .arm64 else {
            return []
        }

        return stride(from: bytes.startIndex, to: bytes.endIndex, by: 4).map {
            Self.makeWord(Array(bytes[$0..<$0 + 4]))
        }
    }

    init(architecture: AsmArchitecture, bytes: [UInt8]) throws {
        if architecture == .arm64 && bytes.count % 4 != 0 {
            throw AsmMacroDiagnostic.invalidAssemblerOutput(
                "`Assembler` emitted \(bytes.count) bytes for arm64; expected a multiple of 4."
            )
        }

        self.architecture = architecture
        self.bytes = bytes
    }

    static func makeWord(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }

    private func tupleType(of elementType: String, count: Int) -> String {
        if count == 1 {
            return elementType
        }

        return "(\(Array(repeating: elementType, count: count).joined(separator: ", ")))"
    }

    private func tupleValue(_ elements: [String]) -> String {
        if elements.count == 1 {
            return elements[0]
        }

        return "(\n    \(elements.joined(separator: ",\n    "))\n)"
    }
}

struct AsmAssembler {
    func assemble(_ source: String, architecture: AsmArchitecture) throws -> AsmMachineCode {
        let bytes: [UInt8]

        switch architecture {
        case .arm64:
            do {
                bytes = try ARM64Assembler.assemble(source)
            } catch {
                throw AsmMacroDiagnostic.assemblerFailed(
                    "`Assembler` failed for arm64: \(error)"
                )
            }
        case .x86_64:
            throw AsmMacroDiagnostic.unsupportedArchitecture("x86_64")
        }

        return try AsmMachineCode(architecture: architecture, bytes: bytes)
    }
}
