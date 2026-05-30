//
//  AsmAssembler.swift
//
//
//  Created by Codex on 2026/05/31.
//
//

import Foundation

private enum AsmAssemblerError: Error {
    case llvmMCUnavailable
}

enum AsmArchitecture: String {
    case arm64
    case x86_64

    var triple: String {
        switch self {
        case .arm64:
            return "arm64-apple-macosx"
        case .x86_64:
            return "x86_64-apple-macosx"
        }
    }

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
                "`llvm-mc` emitted \(bytes.count) bytes for arm64; expected a multiple of 4."
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
        do {
            let output = try runLLVMMC(source, architecture: architecture)
            bytes = try Self.parseEncodedBytes(from: output)
        } catch AsmAssemblerError.llvmMCUnavailable {
            bytes = try assembleWithClang(source, architecture: architecture)
        }

        return try AsmMachineCode(architecture: architecture, bytes: bytes)
    }

    private func runLLVMMC(_ source: String, architecture: AsmArchitecture) throws -> String {
        let result = try runXcrun([
            "llvm-mc",
            "-triple",
            architecture.triple,
            "-show-encoding",
            "-"
        ], input: source)

        guard result.status == 0 else {
            let detail = result.diagnostic
            if detail.contains("unable to find utility \"llvm-mc\"") {
                throw AsmAssemblerError.llvmMCUnavailable
            }
            throw AsmMacroDiagnostic.assemblerFailed(
                "`llvm-mc` failed for \(architecture.rawValue): \(detail)"
            )
        }

        return result.outputString
    }

    private func assembleWithClang(_ source: String, architecture: AsmArchitecture) throws -> [UInt8] {
        let clang = try runXcrun([
            "clang",
            "-c",
            "-arch",
            architecture.rawValue,
            "-x",
            "assembler",
            "-",
            "-o",
            "-"
        ], input: source)
        guard clang.status == 0 else {
            throw AsmMacroDiagnostic.assemblerFailed(
                "`clang` failed for \(architecture.rawValue): \(clang.diagnostic)"
            )
        }

        let objdump = try runXcrun([
            "objdump",
            "-s",
            "-j",
            "__text",
            "-"
        ], input: clang.outputData)
        guard objdump.status == 0 else {
            throw AsmMacroDiagnostic.assemblerFailed(
                "`objdump` failed for \(architecture.rawValue): \(objdump.diagnostic)"
            )
        }

        return try Self.parseObjdumpBytes(from: objdump.outputString)
    }

    static func parseEncodedBytes(from output: String) throws -> [UInt8] {
        var bytes: [UInt8] = []

        for line in output.split(separator: "\n") {
            guard let encodedBytes = encodedBytes(in: line) else {
                continue
            }

            let elements = encodedBytes.split(separator: ",")
            for element in elements {
                let text = element.trimmingCharacters(in: .whitespaces)
                let rawValue = text.hasPrefix("0x")
                    ? String(text.dropFirst(2))
                    : text

                guard let byte = UInt8(rawValue, radix: 16) else {
                    throw AsmMacroDiagnostic.invalidAssemblerOutput(
                        "`llvm-mc` emitted an invalid byte: \(text)"
                    )
                }
                bytes.append(byte)
            }
        }

        guard !bytes.isEmpty else {
            throw AsmMacroDiagnostic.invalidAssemblerOutput(
                "`llvm-mc` output did not contain any `encoding: [...]` lines."
            )
        }

        return bytes
    }

    static func parseObjdumpBytes(from output: String) throws -> [UInt8] {
        var isTextSection = false
        var bytes: [UInt8] = []

        for line in output.split(separator: "\n") {
            if line.contains("Contents of section __TEXT,__text:") {
                isTextSection = true
                continue
            }

            guard isTextSection else {
                continue
            }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2,
                  parts[0].allSatisfy(\.isHexDigit) else {
                continue
            }

            for part in parts.dropFirst() {
                guard part.allSatisfy(\.isHexDigit),
                      part.count % 2 == 0 else {
                    break
                }

                var index = part.startIndex
                while index < part.endIndex {
                    let next = part.index(index, offsetBy: 2)
                    let byteString = String(part[index..<next])
                    guard let byte = UInt8(byteString, radix: 16) else {
                        throw AsmMacroDiagnostic.invalidAssemblerOutput(
                            "`objdump` emitted an invalid byte: \(byteString)"
                        )
                    }
                    bytes.append(byte)
                    index = next
                }
            }
        }

        guard !bytes.isEmpty else {
            throw AsmMacroDiagnostic.invalidAssemblerOutput(
                "`objdump` output did not contain any `__TEXT,__text` bytes."
            )
        }

        return bytes
    }

    private static func encodedBytes(in line: Substring) -> Substring? {
        guard let encodingRange = line.range(of: "encoding:") else {
            return nil
        }

        let rest = line[encodingRange.upperBound...]
        guard let openBracket = rest.firstIndex(of: "["),
              let closeBracket = rest[openBracket...].firstIndex(of: "]") else {
            return nil
        }

        return rest[rest.index(after: openBracket)..<closeBracket]
    }

    private func runXcrun(_ arguments: [String]) throws -> (
        status: Int32,
        outputData: Data,
        outputString: String,
        errorString: String,
        diagnostic: String
    ) {
        try runXcrun(arguments, inputData: nil)
    }

    private func runXcrun(_ arguments: [String], input: String) throws -> (
        status: Int32,
        outputData: Data,
        outputString: String,
        errorString: String,
        diagnostic: String
    ) {
        try runXcrun(arguments, inputData: Data(input.utf8))
    }

    private func runXcrun(_ arguments: [String], input: Data) throws -> (
        status: Int32,
        outputData: Data,
        outputString: String,
        errorString: String,
        diagnostic: String
    ) {
        try runXcrun(arguments, inputData: input)
    }

    private func runXcrun(_ arguments: [String], inputData: Data?) throws -> (
        status: Int32,
        outputData: Data,
        outputString: String,
        errorString: String,
        diagnostic: String
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdin: Pipe?
        if inputData != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            stdin = pipe
        } else {
            stdin = nil
        }

        do {
            try process.run()
        } catch {
            throw AsmMacroDiagnostic.assemblerFailed(
                "`xcrun \(arguments.joined(separator: " "))` failed to launch: \(error)"
            )
        }

        if let inputData,
           let stdin {
            stdin.fileHandleForWriting.write(inputData)
            try? stdin.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        let diagnostic = error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? output
            : error

        return (
            process.terminationStatus,
            outputData,
            output,
            error,
            diagnostic.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
