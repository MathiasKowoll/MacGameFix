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
            let columns = rows.map(\.count).max() ?? 1
            TableLayout(columns: columns) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    ForEach(0..<columns, id: \.self) { j in
                        Text(Instructions.inline(j < row.count ? row[j] : ""))
                            .font(i == 0 ? .caption.bold() : .caption)
                    }
                    if i == 0 { Divider().layoutValue(key: TableLayout.Rule.self, value: true) }
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

/// A table's cells, row by row, and the rule under its header. Each column gets a share of the
/// width by how much text it holds, as a browser lays out a table: a column of short phrases
/// keeps to what it needs and a column of long sentences takes the rest, instead of the first
/// column taking its whole length on one line and leaving the long one a narrow strip.
struct TableLayout: Layout {
    let columns: Int
    var hSpacing: CGFloat = 14
    var vSpacing: CGFloat = 6
    /// The narrowest a column with more text than that is made.
    var floor: CGFloat = 120

    /// Marks the rule under the header, which spans the table.
    struct Rule: LayoutValueKey { static let defaultValue = false }

    private func widths(_ cells: [LayoutSubview], width: CGFloat?) -> [CGFloat] {
        var ideal = [CGFloat](repeating: 0, count: columns)
        for (k, cell) in cells.enumerated() {
            ideal[k % columns] = max(ideal[k % columns], cell.sizeThatFits(.unspecified).width)
        }
        guard let width else { return ideal }
        let room = max(0, width - hSpacing * CGFloat(columns - 1))
        var out = ideal
        if ideal.reduce(0, +) > room {
            let least = ideal.map { min($0, floor) }
            let spare = max(0, room - least.reduce(0, +))
            let more = zip(ideal, least).map { $0 - $1 }
            let total = more.reduce(0, +)
            out = (0..<columns).map { least[$0] + (total > 0 ? spare * more[$0] / total : 0) }
        }
        out[columns - 1] += max(0, room - out.reduce(0, +))
        return out
    }

    private func rows(_ subviews: Subviews, _ w: [CGFloat]) -> [(views: [LayoutSubview], height: CGFloat)] {
        var out: [(views: [LayoutSubview], height: CGFloat)] = []
        var row: [LayoutSubview] = []
        let total = w.reduce(0, +) + hSpacing * CGFloat(columns - 1)
        for view in subviews {
            if view[Rule.self] {
                out.append(([view], view.sizeThatFits(ProposedViewSize(width: total, height: nil)).height))
                continue
            }
            row.append(view)
            if row.count == columns {
                let h = row.enumerated().map { $1.sizeThatFits(ProposedViewSize(width: w[$0], height: nil)).height }.max() ?? 0
                out.append((row, h)); row = []
            }
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = widths(subviews.filter { !$0[Rule.self] }, width: proposal.width)
        let r = rows(subviews, w)
        let height = r.map(\.height).reduce(0, +) + vSpacing * CGFloat(max(0, r.count - 1))
        return CGSize(width: w.reduce(0, +) + hSpacing * CGFloat(columns - 1), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = widths(subviews.filter { !$0[Rule.self] }, width: bounds.width)
        var y = bounds.minY
        for row in rows(subviews, w) {
            var x = bounds.minX
            for (j, view) in row.views.enumerated() {
                let width = view[Rule.self] ? bounds.width : w[j]
                view.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                           proposal: ProposedViewSize(width: width, height: row.height))
                x += width + hSpacing
            }
            y += row.height + vSpacing
        }
    }
}
