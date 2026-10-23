import CoreGraphics
import Foundation

struct TabStripLayout: Equatable {
    struct Item: Equatable {
        var id: UUID
        var length: CGFloat
        var titleMode: TitleMode
    }

    enum TitleMode: Equatable {
        case full
        case short
        case icon
    }

    var items: [Item]
    var overlap: CGFloat

    static let fullLength: CGFloat = 86
    static let minLength: CGFloat = 36

    static func make(
        tabs: [(id: UUID, title: String)],
        budget: CGFloat,
        baseOverlap: CGFloat,
        activeIDs: Set<UUID>,
        fill: Bool = false,
        full: CGFloat = fullLength,
        floors: [CGFloat] = []
    ) -> TabStripLayout {
        let count = tabs.count
        guard count > 0 else {
            return TabStripLayout(items: [], overlap: max(0, baseOverlap))
        }

        let minimum = minLength
        let gaps = CGFloat(max(count - 1, 0))
        let safeBudget = max(budget, minimum)
        var overlap = min(max(baseOverlap, 0), minimum - 8)
        let activeFlags = tabs.map { activeIDs.contains($0.id) }
        let activeCount = activeFlags.filter { $0 }.count
        let restCount = count - activeCount

        func occupied(_ lengths: [CGFloat], overlap: CGFloat) -> CGFloat {
            lengths.reduce(0, +) - gaps * overlap
        }

        var lengths = (0..<count).map { index in
            let floor = index < floors.count ? floors[index] : full
            return max(full, floor)
        }
        if occupied(lengths, overlap: overlap) > safeBudget {
            if restCount == 0 {
                let fitted = (safeBudget + gaps * overlap) / CGFloat(count)
                if fitted >= minimum {
                    lengths = Array(repeating: min(full, fitted), count: count)
                } else if gaps > 0 {
                    lengths = Array(repeating: minimum, count: count)
                    overlap = (CGFloat(count) * minimum - safeBudget) / gaps
                } else {
                    lengths = [min(full, max(minimum, safeBudget))]
                }
            } else {
                func occupiedRest(_ rest: CGFloat, overlap: CGFloat) -> CGFloat {
                    CGFloat(activeCount) * full + CGFloat(restCount) * rest - gaps * overlap
                }
                if occupiedRest(minimum, overlap: overlap) <= safeBudget {
                    var low = minimum
                    var high = full
                    for _ in 0..<18 {
                        let mid = (low + high) / 2
                        if occupiedRest(mid, overlap: overlap) <= safeBudget {
                            low = mid
                        } else {
                            high = mid
                        }
                    }
                    for index in lengths.indices {
                        lengths[index] = activeFlags[index] ? full : low
                    }
                } else {
                    var compressed = activeFlags.map { $0 ? full : minimum }
                    if count > 1 {
                        for index in compressed.indices where !activeFlags[index] {
                            let besideActive = (index > 0 && activeFlags[index - 1]) || (index + 1 < count && activeFlags[index + 1])
                            if besideActive {
                                compressed[index] = minimum + 12
                            }
                        }
                    }
                    func overlapNeeded(_ values: [CGFloat]) -> CGFloat {
                        guard gaps > 0 else { return overlap }
                        let sum = values.reduce(0, +)
                        guard sum > safeBudget else { return overlap }
                        return (sum - safeBudget) / gaps
                    }
                    let bonusOverlap = overlapNeeded(compressed)
                    let thinnest = compressed.min() ?? minimum
                    if thinnest - bonusOverlap >= 14 {
                        lengths = compressed
                        overlap = bonusOverlap
                    } else {
                        lengths = activeFlags.map { $0 ? full : minimum }
                        overlap = overlapNeeded(lengths)
                    }
                }
            }
        }

        let maxOverlap = max(0, minimum - 8)
        overlap = min(max(overlap, 0), maxOverlap)
        if fill {
            let current = occupied(lengths, overlap: overlap)
            if current > 1, current < safeBudget {
                let cap = max(full, floors.max() ?? full, 160)
                let room = min(safeBudget, current * (cap / max(lengths.max() ?? full, 1)))
                let factor = room / current
                for index in lengths.indices {
                    let floor = index < floors.count ? floors[index] : minimum
                    lengths[index] = min(cap, max(floor, lengths[index] * factor))
                }
                let used = occupied(lengths, overlap: overlap)
                if used < safeBudget, gaps > 0 {
                    let loosened = (lengths.reduce(0, +) - safeBudget) / gaps
                    overlap = min(overlap, max(0, loosened))
                }
            }
        }
        if !floors.isEmpty {
            overlap = min(max(baseOverlap, 0), minimum - 8)
        }
        for index in lengths.indices {
            let floor = index < floors.count ? floors[index] : 28
            lengths[index] = max(lengths[index], floor)
            if floors.isEmpty {
                lengths[index] = min(lengths[index], max(safeBudget, 28))
            }
        }

        let items = zip(tabs.indices, zip(tabs, lengths)).map { index, pair in
            let (tab, length) = pair
            let active = activeIDs.contains(tab.id)
            let mode: TitleMode
            if index < floors.count || length >= 76 || (active && length >= 64) {
                mode = .full
            } else if length >= 48 {
                mode = .short
            } else {
                mode = .icon
            }
            return Item(id: tab.id, length: length.rounded(.toNearestOrAwayFromZero), titleMode: mode)
        }
        return TabStripLayout(items: items, overlap: overlap)
    }
}

func skuffShortTitle(_ title: String) -> String {
    if title.count <= 8 { return title }
    return String(title.prefix(7)) + "…"
}
