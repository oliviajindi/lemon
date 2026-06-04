import SwiftUI

/// Simple wrapping layout for chips/tags. It keeps the hand-made menu UI from
/// needing rigid grids when tag names have different lengths.
struct FlowLayout: Layout {
    enum Alignment { case leading, center }

    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8
    var alignment: Alignment = .leading

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(for: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { partial, row in
            partial + row.height
        } + CGFloat(max(0, rows.count - 1)) * rowSpacing
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            let startX = alignment == .center
                ? bounds.minX + (bounds.width - row.width) / 2
                : bounds.minX
            var x = startX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [FlowRow] {
        var rows: [FlowRow] = []
        var current = FlowRow()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.items.isEmpty
                ? size.width
                : current.width + spacing + size.width

            if !current.items.isEmpty && proposedWidth > maxWidth {
                rows.append(current)
                current = FlowRow()
            }

            current.add(FlowItem(index: index, size: size), spacing: spacing)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

private struct FlowRow {
    var items: [FlowItem] = []
    var width: CGFloat = 0
    var height: CGFloat = 0

    mutating func add(_ item: FlowItem, spacing: CGFloat) {
        if !items.isEmpty {
            width += spacing
        }
        items.append(item)
        width += item.size.width
        height = max(height, item.size.height)
    }
}

private struct FlowItem {
    let index: Int
    let size: CGSize
}
