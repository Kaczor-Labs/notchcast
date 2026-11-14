/// `Array.prototype.sort` as V8 runs it: binary insertion up to 15 elements, TimSort above.
/// Swift's sort places items differently when the comparator is not a strict order, as a NaN
/// priority makes upstream's, so the store sorts with this. `compare` returns a JS number;
/// below zero puts the first argument first.
func jsSort<Element>(_ array: inout [Element], by compare: (Element, Element) -> Double) {
    withoutActuallyEscaping(compare) { compare in
        var sorter = JSSorter(items: array, compare: { a, b in
            let order = compare(a, b)
            return order.isNaN ? 0 : order
        })
        sorter.sort()
        array = sorter.items
    }
}

private struct JSSorter<Element> {
    var items: [Element]
    let compare: (Element, Element) -> Double
    var minGallop = 7
    var runs: [(base: Int, count: Int)] = []

    func less(_ a: Element, _ b: Element) -> Bool { compare(a, b) < 0 }

    mutating func sort() {
        let n = items.count
        guard n >= 2 else { return }
        if n <= 15 {
            insert(low: 0, start: 1, high: n)
            return
        }
        var low = 0
        var remaining = n
        var partitions = 1
        while n / partitions >= 64 { partitions *= 2 }
        var partition = 0
        while remaining > 0 {
            var run = countRun(low: low, high: low + remaining)
            partition += 1
            let minRun = partition * n / partitions - (partition - 1) * n / partitions
            if run < minRun {
                let forced = min(minRun, remaining)
                insert(low: low, start: low + run, high: low + forced)
                run = forced
            }
            runs.append((low, run))
            mergeCollapse()
            low += run
            remaining -= run
        }
        while runs.count > 1 {
            var i = runs.count - 2
            if i > 0 && runs[i - 1].count < runs[i + 1].count { i -= 1 }
            merge(at: i)
        }
    }

    mutating func insert(low: Int, start: Int, high: Int) {
        var start = max(start, low + 1)
        while start < high {
            let pivot = items[start]
            var left = low
            var right = start
            while left < right {
                let mid = left + ((right - left) >> 1)
                if less(pivot, items[mid]) { right = mid } else { left = mid + 1 }
            }
            var i = start
            while i > left {
                items[i] = items[i - 1]
                i -= 1
            }
            items[left] = pivot
            start += 1
        }
    }

    mutating func countRun(low: Int, high: Int) -> Int {
        if low + 1 == high { return 1 }
        var count = 2
        let descending = less(items[low + 1], items[low])
        var previous = items[low + 1]
        var i = low + 2
        while i < high {
            let order = compare(items[i], previous)
            if descending ? order >= 0 : order < 0 { break }
            previous = items[i]
            count += 1
            i += 1
        }
        if descending { items[low..<low + count].reverse() }
        return count
    }

    mutating func mergeCollapse() {
        while runs.count > 1 {
            var n = runs.count - 2
            let count = runs.map { $0.count }
            if (n > 0 && count[n - 1] <= count[n] + count[n + 1])
                || (n > 1 && count[n - 2] <= count[n - 1] + count[n])
            {
                if count[n - 1] < count[n + 1] { n -= 1 }
                merge(at: n)
            } else if count[n] <= count[n + 1] {
                merge(at: n)
            } else {
                break
            }
        }
    }

    mutating func merge(at i: Int) {
        var (baseA, countA) = runs[i]
        let (baseB, fullB) = runs[i + 1]
        runs[i] = (baseA, countA + fullB)
        runs.remove(at: i + 1)
        let k = gallopRight(items[baseB], in: items, base: baseA, count: countA, hint: 0)
        baseA += k
        countA -= k
        if countA == 0 { return }
        let countB = gallopLeft(items[baseA + countA - 1], in: items, base: baseB, count: fullB, hint: fullB - 1)
        if countB == 0 { return }
        if countA <= countB {
            mergeLow(baseA: baseA, countA: countA, baseB: baseB, countB: countB)
        } else {
            mergeHigh(baseA: baseA, countA: countA, baseB: baseB, countB: countB)
        }
    }

    /// Leftmost slot for `key` in `a[base..<base+count]`, searched outward from `hint`.
    func gallopLeft(_ key: Element, in a: [Element], base: Int, count: Int, hint: Int) -> Int {
        var last = 0
        var offset = 1
        if less(a[base + hint], key) {
            let maxOffset = count - hint
            while offset < maxOffset && less(a[base + hint + offset], key) {
                last = offset
                offset = (offset << 1) + 1
            }
            offset = min(offset, maxOffset)
            last += hint
            offset += hint
        } else {
            let maxOffset = hint + 1
            while offset < maxOffset && !less(a[base + hint - offset], key) {
                last = offset
                offset = (offset << 1) + 1
            }
            offset = min(offset, maxOffset)
            (last, offset) = (hint - offset, hint - last)
        }
        last += 1
        while last < offset {
            let mid = last + ((offset - last) >> 1)
            if less(a[base + mid], key) { last = mid + 1 } else { offset = mid }
        }
        return offset
    }

    /// Rightmost slot for `key` in `a[base..<base+count]`, searched outward from `hint`.
    func gallopRight(_ key: Element, in a: [Element], base: Int, count: Int, hint: Int) -> Int {
        var last = 0
        var offset = 1
        if less(key, a[base + hint]) {
            let maxOffset = hint + 1
            while offset < maxOffset && less(key, a[base + hint - offset]) {
                last = offset
                offset = (offset << 1) + 1
            }
            offset = min(offset, maxOffset)
            (last, offset) = (hint - offset, hint - last)
        } else {
            let maxOffset = count - hint
            while offset < maxOffset && !less(key, a[base + hint + offset]) {
                last = offset
                offset = (offset << 1) + 1
            }
            offset = min(offset, maxOffset)
            last += hint
            offset += hint
        }
        last += 1
        while last < offset {
            let mid = last + ((offset - last) >> 1)
            if less(key, a[base + mid]) { offset = mid } else { last = mid + 1 }
        }
        return offset
    }

    mutating func mergeLow(baseA: Int, countA: Int, baseB: Int, countB: Int) {
        let temp = Array(items[baseA..<baseA + countA])
        var a = 0
        var b = baseB
        var dest = baseA
        var countA = countA
        var countB = countB
        var gallop = minGallop
        defer { minGallop = gallop }

        func copyRest() {
            for j in 0..<countA { items[dest + j] = temp[a + j] }
        }
        func copyB() {
            for j in 0..<countB { items[dest + j] = items[b + j] }
            items[dest + countB] = temp[a]
        }

        items[dest] = items[b]
        dest += 1
        b += 1
        countB -= 1
        if countB == 0 { return copyRest() }
        if countA == 1 { return copyB() }
        while true {
            var winsA = 0
            var winsB = 0
            while true {
                if less(items[b], temp[a]) {
                    items[dest] = items[b]
                    dest += 1
                    b += 1
                    winsB += 1
                    winsA = 0
                    countB -= 1
                    if countB == 0 { return copyRest() }
                    if winsB >= gallop { break }
                } else {
                    items[dest] = temp[a]
                    dest += 1
                    a += 1
                    winsA += 1
                    winsB = 0
                    countA -= 1
                    if countA == 1 { return copyB() }
                    if winsA >= gallop { break }
                }
            }
            gallop += 1
            repeat {
                gallop -= gallop > 1 ? 1 : 0
                minGallop = gallop
                var k = gallopRight(items[b], in: temp, base: a, count: countA, hint: 0)
                winsA = k
                if k > 0 {
                    for j in 0..<k { items[dest + j] = temp[a + j] }
                    dest += k
                    a += k
                    countA -= k
                    if countA == 1 { return copyB() }
                    if countA == 0 { return }
                }
                items[dest] = items[b]
                dest += 1
                b += 1
                countB -= 1
                if countB == 0 { return copyRest() }
                k = gallopLeft(temp[a], in: items, base: b, count: countB, hint: 0)
                winsB = k
                if k > 0 {
                    for j in 0..<k { items[dest + j] = items[b + j] }
                    dest += k
                    b += k
                    countB -= k
                    if countB == 0 { return copyRest() }
                }
                items[dest] = temp[a]
                dest += 1
                a += 1
                countA -= 1
                if countA == 1 { return copyB() }
            } while winsA >= 7 || winsB >= 7
            gallop += 1
        }
    }

    mutating func mergeHigh(baseA: Int, countA: Int, baseB: Int, countB: Int) {
        let temp = Array(items[baseB..<baseB + countB])
        var b = countB - 1
        var a = baseA + countA - 1
        var dest = baseB + countB - 1
        var countA = countA
        var countB = countB
        var gallop = minGallop
        defer { minGallop = gallop }

        func copyRest() {
            for j in 0..<countB { items[dest - (countB - 1) + j] = temp[j] }
        }
        func copyA() {
            let to = dest - countA
            let from = a - countA
            for j in stride(from: countA - 1, through: 0, by: -1) { items[to + 1 + j] = items[from + 1 + j] }
            items[to] = temp[b]
        }

        items[dest] = items[a]
        dest -= 1
        a -= 1
        countA -= 1
        if countA == 0 { return copyRest() }
        if countB == 1 { return copyA() }
        while true {
            var winsA = 0
            var winsB = 0
            while true {
                if less(temp[b], items[a]) {
                    items[dest] = items[a]
                    dest -= 1
                    a -= 1
                    winsA += 1
                    winsB = 0
                    countA -= 1
                    if countA == 0 { return copyRest() }
                    if winsA >= gallop { break }
                } else {
                    items[dest] = temp[b]
                    dest -= 1
                    b -= 1
                    winsB += 1
                    winsA = 0
                    countB -= 1
                    if countB == 1 { return copyA() }
                    if winsB >= gallop { break }
                }
            }
            gallop += 1
            repeat {
                gallop -= gallop > 1 ? 1 : 0
                minGallop = gallop
                var k = countA - gallopRight(temp[b], in: items, base: baseA, count: countA, hint: countA - 1)
                winsA = k
                if k > 0 {
                    dest -= k
                    a -= k
                    for j in stride(from: k - 1, through: 0, by: -1) { items[dest + 1 + j] = items[a + 1 + j] }
                    countA -= k
                    if countA == 0 { return copyRest() }
                }
                items[dest] = temp[b]
                dest -= 1
                b -= 1
                countB -= 1
                if countB == 1 { return copyA() }
                k = countB - gallopLeft(items[a], in: temp, base: 0, count: countB, hint: countB - 1)
                winsB = k
                if k > 0 {
                    dest -= k
                    b -= k
                    for j in 0..<k { items[dest + 1 + j] = temp[b + 1 + j] }
                    countB -= k
                    if countB == 1 { return copyA() }
                    if countB == 0 { return copyRest() }
                }
                items[dest] = items[a]
                dest -= 1
                a -= 1
                countA -= 1
                if countA == 0 { return copyRest() }
            } while winsA >= 7 || winsB >= 7
            gallop += 1
        }
    }
}
