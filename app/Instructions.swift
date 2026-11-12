// A fix's special instructions: the Markdown file an installer names on its
// MGVF-INSTRUCTIONS line, which build-app.sh carries in games.json. Shown in a
// sheet from the game's row in Games. The Markdown it reads is the little that
// file needs: headings, paragraphs, bullets, tables and code blocks, each code
// block with a Copy button (a launch options line, for one).
//
// Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

enum InstructionBlock: Hashable {
    case heading(String)
    case paragraph(String)
    case bullet(String)
    /// The first row is the header; Markdown's separator row is left out.
    case table([[String]])
    case code(String)
}

enum Instructions {
    static func blocks(_ text: String) -> [InstructionBlock] {
        var out: [InstructionBlock] = []
        var para: [String] = []
        var rows: [[String]] = []
        var code: [String]?
        func endParagraph() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] } }
        func endTable() { if !rows.isEmpty { out.append(.table(rows)); rows = [] } }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if var lines = code {
                if line.hasPrefix("```") { out.append(.code(lines.joined(separator: "\n"))); code = nil }
                else { lines.append(raw); code = lines }
                continue
            }
            if line.hasPrefix("```") { endParagraph(); endTable(); code = []; continue }
            if line.hasPrefix("|") {
                endParagraph()
                let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }) { continue }
                rows.append(cells)
                continue
            }
            endTable()
            if line.isEmpty { endParagraph(); continue }
            if line.hasPrefix("#") {
                endParagraph()
                out.append(.heading(String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line.hasPrefix("- ") { endParagraph(); out.append(.bullet(String(line.dropFirst(2)))); continue }
            para.append(line)
        }
        if let lines = code { out.append(.code(lines.joined(separator: "\n"))) }
        endParagraph()
        endTable()
        return out
    }

    /// Inline Markdown: `code`, **bold**, links.
    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

struct InstructionsSheet: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView { InstructionsContent(title: game.name, text: game.instructions ?? "") }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 420, idealHeight: 600)
    }
}

/// The sheet's content, on its own so that it can be drawn outside a ScrollView.
struct InstructionsContent: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(title): special instructions").font(.title3.bold())
            ForEach(Array(Instructions.blocks(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder private func blockView(_ block: InstructionBlock) -> some View {
        switch block {
        case .heading(let s):
            Text(Instructions.inline(s)).font(.headline).padding(.top, 6)
        case .paragraph(let s):
            Text(Instructions.inline(s)).fixedSize(horizontal: false, vertical: true)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                Text(Instructions.inline(s)).fixedSize(horizontal: false, vertical: true)
            }
        case .table(let rows):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { j, cell in
                            Text(Instructions.inline(cell))
                                .font(i == 0 ? .caption.bold() : .caption)
                                .fixedSize(horizontal: j == 0, vertical: true)
                                .frame(maxWidth: j == 0 ? nil : .infinity, alignment: .leading)
                        }
                    }
                    if i == 0 { Divider().gridCellColumns(row.count) }
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        case .code(let s):
            HStack(alignment: .top, spacing: 10) {
                Text(s).font(.system(.caption, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(s, forType: .string)
                }
                .controlSize(.small)
                .help("Copies this line, to paste into the game's Launch Options in Steam.")
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
