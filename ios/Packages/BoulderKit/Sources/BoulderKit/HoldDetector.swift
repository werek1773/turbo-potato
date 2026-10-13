import Foundation

/// A hold found on a wall photo: centre (0...1 of the photo) and radius
/// (share of the photo's width).
public struct DetectedHold: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let r: Double
    public let color: HoldColor

    public init(x: Double, y: Double, r: Double, color: HoldColor) {
        self.x = x
        self.y = y
        self.r = r
        self.color = color
    }
}

/// Finds holds on a sector photo, as suggestions for staff to fix: every
/// hold becomes a dot with its color and size. No shapes, no guessing which
/// problem a hold belongs to.
///
/// 1. Volumes are the big deep-teal regions; on them a hold is whatever is
///    neither teal nor chalk.
/// 2. On plywood a hold is what differs from the local background (a large
///    box mean), minus plain shadows (same hue as the plywood, only darker).
/// 3. Every pixel gets a hold color; blobs of one color are holds. Parts of
///    one hold split by shade or chalk are joined back.
///
/// Feed it a photo scaled to about `workWidth` pixels wide. Constants were
/// tuned on Volt Łódź photos.
public enum HoldDetector {
    public static let workWidth = 640

    static let volumeMinShare = 0.0045
    static let volumeBigShare = 0.012
    static let holdMinShare = 0.0003
    static let holdMaxShare = 0.03
    /// White and grey blobs smaller than this are glare, not holds.
    static let glareMaxShare = 0.0008

    /// Pixel classes; 0 means no hold color.
    static let classes: [HoldColor] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .white, .grey, .black]
    static let neutral: Set<HoldColor> = [.white, .grey, .black]
    static let warm: Set<HoldColor> = [.red, .orange, .pink]
    static let dark: Set<HoldColor> = [.black, .grey]

    /// `rgba` is 8-bit RGBA, row by row, `width * height * 4` bytes.
    public static func detect(rgba: [UInt8], width: Int, height: Int) -> [DetectedHold] {
        let count = width * height
        guard width > 4, height > 4, rgba.count >= count * 4 else { return [] }

        var hue = [Float](repeating: 0, count: count)
        var sat = [Float](repeating: 0, count: count)
        var val = [Float](repeating: 0, count: count)
        var labL = [Double](repeating: 0, count: count)
        var labA = [Double](repeating: 0, count: count)
        var labB = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let r = Float(rgba[i * 4]) / 255
            let g = Float(rgba[i * 4 + 1]) / 255
            let b = Float(rgba[i * 4 + 2]) / 255
            (hue[i], sat[i], val[i]) = hsv(r, g, b)
            (labL[i], labA[i], labB[i]) = lab(Double(r), Double(g), Double(b))
        }
        let cls = (0..<count).map { classify(hue[$0], sat[$0], val[$0]) }

        // 1. Volumes.
        var cool = (0..<count).map { hue[$0] >= 175 && hue[$0] < 207 && sat[$0] >= 0.22 && val[$0] >= 0.2 }
        cool = dilate(dilate(erode(erode(dilate(dilate(cool, width, height), width, height), width, height), width, height), width, height), width, height)
        let (coolLabels, coolCount) = label(cool, width, height)
        var coolSize = [Int](repeating: 0, count: coolCount + 1)
        var coolSat = [Double](repeating: 0, count: coolCount + 1)
        for i in 0..<count where coolLabels[i] > 0 {
            coolSize[coolLabels[i]] += 1
            coolSat[coolLabels[i]] += Double(sat[i])
        }
        var isVolume = [Bool](repeating: false, count: coolCount + 1)
        for l in 1..<(coolCount + 1) {
            let share = Double(coolSize[l]) / Double(count)
            let meanSat = coolSat[l] / Double(max(coolSize[l], 1))
            // Volumes are big and a deeper teal; a big light-blue hold is smaller and paler.
            isVolume[l] = share >= volumeBigShare || (share >= volumeMinShare && meanSat >= 0.4)
        }

        // 2. Foreground on plywood.
        let radius = max(8, width / 12)
        let meanL = boxMean(labL, width, height, radius)
        let meanA = boxMean(labA, width, height, radius)
        let meanB = boxMean(labB, width, height, radius)
        let whiteClass = Int8(classes.firstIndex(of: .white)! + 1)
        let greyClass = Int8(classes.firstIndex(of: .grey)! + 1)
        var fg = [Bool](repeating: false, count: count)
        for i in 0..<count {
            if coolLabels[i] > 0 && isVolume[coolLabels[i]] {
                // On a volume: not its teal or shading, not chalk or glare.
                let volumeLike = hue[i] >= 150 && hue[i] < 230 && sat[i] >= 0.15
                fg[i] = cls[i] > 0 && !volumeLike && cls[i] != whiteClass && cls[i] != greyClass
                continue
            }
            let chromaDiff = hypot(labA[i] - meanA[i], labB[i] - meanB[i])
            let lighter = labL[i] - meanL[i]
            var isForeground = chromaDiff > 14 || lighter > 12 || val[i] < 0.27
            let bgHue = degrees(atan2(meanB[i], meanA[i]))
            let pixelHue = degrees(atan2(labB[i], labA[i]))
            let hueGap = abs((pixelHue - bgHue + 540).truncatingRemainder(dividingBy: 360) - 180)
            let shadow = hueGap < 14 && lighter < 0 && chromaDiff < 22 && val[i] >= 0.27
            if shadow { isForeground = false }
            fg[i] = isForeground
        }
        fg = dilate(erode(fg, width, height), width, height)

        // 3. Blobs per class.
        var labels = [Int](repeating: 0, count: count)
        var labelClass: [Int8] = [0]
        for c in 1...Int8(classes.count) {
            let mask = (0..<count).map { fg[$0] && cls[$0] == c }
            guard mask.contains(true) else { continue }
            let (l, n) = label(mask, width, height)
            let offset = labelClass.count - 1
            for i in 0..<count where l[i] > 0 { labels[i] = l[i] + offset }
            labelClass += Array(repeating: c, count: n)
        }
        let n = labelClass.count - 1
        guard n > 0 else { return [] }
        var area = [Double](repeating: 0, count: n + 1)
        var sumX = [Double](repeating: 0, count: n + 1)
        var sumY = [Double](repeating: 0, count: n + 1)
        for y in 0..<height {
            for x in 0..<width {
                let l = labels[y * width + x]
                guard l > 0 else { continue }
                area[l] += 1
                sumX[l] += Double(x)
                sumY[l] += Double(y)
            }
        }

        // Neighbouring blobs within 2 px.
        var pairs = Set<Pair>()
        for (dy, dx) in [(0, 1), (1, 0), (0, 2), (2, 0), (1, 1), (1, -1)] {
            for y in 0..<(height - dy) {
                for x in max(0, -dx)..<(width - max(0, dx)) {
                    let a = labels[y * width + x]
                    let b = labels[(y + dy) * width + x + dx]
                    if a > 0, b > 0, a != b { pairs.insert(Pair(min(a, b), max(a, b))) }
                }
            }
        }

        var parent = Array(0...n)
        func find(_ a: Int) -> Int {
            var a = a
            while parent[a] != a {
                parent[a] = parent[parent[a]]
                a = parent[a]
            }
            return a
        }
        func color(_ l: Int) -> HoldColor { classes[Int(labelClass[l]) - 1] }

        // Bigger first, so small bits join the hold they belong to.
        let ordered = pairs.sorted {
            let left = area[$0.a] + area[$0.b], right = area[$1.a] + area[$1.b]
            return left != right ? left > right : ($0.a, $0.b) < ($1.a, $1.b)
        }
        var joined = area
        for pair in ordered {
            let rootA = find(pair.a), rootB = find(pair.b)
            guard rootA != rootB else { continue }
            let (big, small) = joined[rootA] >= joined[rootB] ? (rootA, rootB) : (rootB, rootA)
            let colorA = color(rootA), colorB = color(rootB)
            let same = colorA == colorB
            let warmParts = warm.contains(colorA) && warm.contains(colorB) && joined[small] < 0.5 * joined[big]
            let darkParts = dark.contains(colorA) && dark.contains(colorB)
            let chalk = neutral.contains(color(small)) && !neutral.contains(color(big))
            if same || warmParts || darkParts || chalk {
                parent[small] = big
                joined[big] += joined[small]
            }
        }

        var groupArea: [Int: Double] = [:]
        var groupX: [Int: Double] = [:]
        var groupY: [Int: Double] = [:]
        for l in 1...n {
            let root = find(l)
            groupArea[root, default: 0] += area[l]
            groupX[root, default: 0] += sumX[l]
            groupY[root, default: 0] += sumY[l]
        }

        var holds: [DetectedHold] = []
        for (root, a) in groupArea {
            let share = a / Double(count)
            let holdColor = color(root)
            guard share >= holdMinShare, share <= holdMaxShare else { continue }
            if (holdColor == .white || holdColor == .grey) && share < glareMaxShare { continue }
            holds.append(DetectedHold(
                x: (groupX[root]! / a) / Double(width),
                y: (groupY[root]! / a) / Double(height),
                r: (a / .pi).squareRoot() / Double(width),
                color: holdColor
            ))
        }
        return holds.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    // MARK: - Color

    /// Hue in degrees, saturation and value in 0...1.
    static func hsv(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        let s: Float = maxC > 0 ? delta / maxC : 0
        guard delta > 1e-6 else { return (0, s, maxC) }
        var h: Float
        if maxC == r {
            h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            if h < 0 { h += 6 }
        } else if maxC == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        return (h * 60, s, maxC)
    }

    /// CIE Lab (D65) of an sRGB color in 0...1.
    static func lab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let lr = linear(r), lg = linear(g), lb = linear(b)
        let x = (0.4124 * lr + 0.3576 * lg + 0.1805 * lb) / 0.95047
        let y = 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
        let z = (0.0193 * lr + 0.1192 * lg + 0.9505 * lb) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// The pixel's hold class (index into `classes` + 1), 0 for none.
    static func classify(_ h: Float, _ s: Float, _ v: Float) -> Int8 {
        // Small purple holds are dark and only a little saturated.
        let vivid = s >= 0.27 || (s >= 0.16 && v < 0.47 && h >= 236 && h < 320)
        let color: HoldColor?
        if vivid {
            let redHue = h < 8 || h >= 344
            if redHue && (s >= 0.47 || v < 0.63) {
                color = .red
            } else if (h >= 8 && h < 34 && s >= 0.47) || ((h < 12 || h >= 344) && s < 0.47 && v >= 0.63) {
                // Volt's orange holds are salmon: red hue, pale.
                color = .orange
            } else if h >= 34 && h < 70 && s >= 0.47 {
                color = .yellow
            } else if h >= 70 && h < 176 {
                color = .green
            } else if h >= 176 && h < 244 {
                color = .blue
            } else if h >= 244 && h < 316 {
                color = .purple
            } else if h >= 316 && h < 344 {
                color = .pink
            } else {
                color = nil
            }
        } else if v >= 0.67 {
            // White holds are nearly colorless; pale plywood and glare are not.
            color = s < 0.14 ? .white : nil
        } else {
            color = v >= 0.33 ? .grey : .black
        }
        guard let color, let index = classes.firstIndex(of: color) else { return 0 }
        return Int8(index + 1)
    }

    static func degrees(_ radians: Double) -> Double {
        let d = radians * 180 / .pi
        return d < 0 ? d + 360 : d
    }

    // MARK: - Images

    struct Pair: Hashable {
        let a: Int
        let b: Int
        init(_ a: Int, _ b: Int) { self.a = a; self.b = b }
    }

    /// Mean over a (2r+1)² box, clamped at the edges, via an integral image.
    static func boxMean(_ values: [Double], _ width: Int, _ height: Int, _ radius: Int) -> [Double] {
        let stride = width + 1
        var integral = [Double](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var row = 0.0
            for x in 0..<width {
                row += values[y * width + x]
                integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + row
            }
        }
        var out = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            let y0 = max(0, y - radius), y1 = min(height, y + radius + 1)
            for x in 0..<width {
                let x0 = max(0, x - radius), x1 = min(width, x + radius + 1)
                let total = integral[y1 * stride + x1] - integral[y0 * stride + x1]
                    - integral[y1 * stride + x0] + integral[y0 * stride + x0]
                out[y * width + x] = total / Double((y1 - y0) * (x1 - x0))
            }
        }
        return out
    }

    /// 4-neighbour erosion; the border becomes false.
    static func erode(_ mask: [Bool], _ width: Int, _ height: Int) -> [Bool] {
        var out = [Bool](repeating: false, count: mask.count)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                out[i] = mask[i] && mask[i - 1] && mask[i + 1] && mask[i - width] && mask[i + width]
            }
        }
        return out
    }

    /// 4-neighbour dilation.
    static func dilate(_ mask: [Bool], _ width: Int, _ height: Int) -> [Bool] {
        var out = mask
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                guard !mask[i] else { continue }
                out[i] = (x > 0 && mask[i - 1]) || (x < width - 1 && mask[i + 1])
                    || (y > 0 && mask[i - width]) || (y < height - 1 && mask[i + width])
            }
        }
        return out
    }

    /// 4-connected components: labels 1...n, 0 for background.
    static func label(_ mask: [Bool], _ width: Int, _ height: Int) -> ([Int], Int) {
        var labels = [Int](repeating: 0, count: mask.count)
        var n = 0
        var stack: [Int] = []
        for start in 0..<mask.count where mask[start] && labels[start] == 0 {
            n += 1
            labels[start] = n
            stack.append(start)
            while let i = stack.popLast() {
                let x = i % width, y = i / width
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let j = ny * width + nx
                    if mask[j] && labels[j] == 0 {
                        labels[j] = n
                        stack.append(j)
                    }
                }
            }
        }
        return (labels, n)
    }
}
