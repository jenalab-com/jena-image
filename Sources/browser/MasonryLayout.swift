import AppKit

/// 항목 순서를 유지하면서 현재 가장 짧은 열에 다음 항목을 배치한다.
struct MasonryGeometry {
    let frames: [CGRect]
    let columns: [[Int]]
    let contentSize: CGSize

    init(width: CGFloat, preferredColumnWidth: CGFloat, aspectRatios: [CGFloat],
         captionHeight: CGFloat, imageInset: CGFloat = 2, spacing: CGFloat = 12, inset: CGFloat = 12,
         mode: BrowserLayoutMode = .masonry) {
        let width = max(1, width)
        let available = max(1, width - inset * 2)
        let columnCount = max(1, Int((available + spacing) / (max(40, preferredColumnWidth) + spacing)))
        let columnWidth = (available - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var bottoms = Array(repeating: inset, count: columnCount)
        var frames: [CGRect] = []
        var columns = Array(repeating: [Int](), count: columnCount)
        for (index, aspectRatio) in aspectRatios.enumerated() {
            let ratio = mode == .grid ? 1 : (aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1)
            let column = mode == .grid ? index % columnCount : bottoms.indices.min { bottoms[$0] < bottoms[$1] }!
            let imageHeight = max(1, columnWidth - imageInset * 2) / ratio
            let frame = CGRect(x: inset + CGFloat(column) * (columnWidth + spacing),
                               y: bottoms[column], width: columnWidth,
                               height: ceil(imageHeight) + captionHeight)
            frames.append(frame)
            columns[column].append(index)
            bottoms[column] = frame.maxY + spacing
        }
        self.frames = frames
        self.columns = columns
        self.contentSize = CGSize(width: width, height: aspectRatios.isEmpty ? inset * 2 : bottoms.max()! - spacing + inset)
    }

    /// 각 열은 y 순서이므로 이진 검색으로 화면 주변 항목만 찾는다.
    func indexes(in rect: CGRect) -> [Int] {
        var result: [Int] = []
        for column in columns {
            var low = 0
            var high = column.count
            while low < high {
                let middle = (low + high) / 2
                if frames[column[middle]].maxY <= rect.minY { low = middle + 1 }
                else { high = middle }
            }
            for position in low..<column.count {
                let index = column[position]
                let frame = frames[index]
                if frame.minY >= rect.maxY { break }
                if frame.intersects(rect) { result.append(index) }
            }
        }
        return result.sorted()
    }
}

final class MasonryLayout: NSCollectionViewLayout {
    var layoutMode: BrowserLayoutMode = .masonry { didSet { if oldValue != layoutMode { invalidateLayout() } } }
    var preferredColumnWidth: CGFloat = 180 { didSet { if oldValue != preferredColumnWidth { invalidateLayout() } } }
    var captionHeight: CGFloat = 36 { didSet { if oldValue != captionHeight { invalidateLayout() } } }
    var aspectRatios: [CGFloat] = [] { didSet { if oldValue != aspectRatios { invalidateLayout() } } }
    private var geometry: MasonryGeometry?
    private var attributes: [NSCollectionViewLayoutAttributes] = []
    private var needsRebuild = true
    private var preparedWidth: CGFloat = 0

    override func invalidateLayout() {
        needsRebuild = true
        super.invalidateLayout()
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let width = max(1, collectionView.enclosingScrollView?.contentSize.width ?? collectionView.bounds.width)
        guard needsRebuild || abs(width - preparedWidth) > 0.5 else { return }
        preparedWidth = width
        needsRebuild = false
        let geometry = MasonryGeometry(width: width, preferredColumnWidth: preferredColumnWidth,
                                       aspectRatios: aspectRatios, captionHeight: captionHeight, mode: layoutMode)
        self.geometry = geometry
        attributes = geometry.frames.enumerated().map { index, frame in
            let attribute = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
            attribute.frame = frame
            return attribute
        }
    }

    override var collectionViewContentSize: NSSize {
        geometry?.contentSize ?? .zero
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        (geometry?.indexes(in: rect) ?? []).map { attributes[$0] }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.section == 0, attributes.indices.contains(indexPath.item) else { return nil }
        return attributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        abs(newBounds.width - preparedWidth) > 0.5
    }
}
