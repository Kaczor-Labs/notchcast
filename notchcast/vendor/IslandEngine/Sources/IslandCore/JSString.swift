/// JavaScript's shortest decimal number representation.
package func jsString(_ value: Double) -> String {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
    if value == 0 { return "0" }
    let sign = value < 0 ? "-" : ""
    let (digits, point) = shortestDigits(value.magnitude)
    let count = digits.count
    switch point {
    case count...21:
        return sign + digits + String(repeating: "0", count: point - count)
    case 1...21:
        return sign + digits.prefix(point) + "." + digits.dropFirst(point)
    case -5...0:
        return sign + "0." + String(repeating: "0", count: -point) + digits
    default:
        let exponent = point - 1
        let mantissa = count == 1 ? digits : digits.prefix(1) + "." + digits.dropFirst()
        return sign + mantissa + "e" + (exponent < 0 ? "-" : "+") + String(exponent.magnitude)
    }
}

/// The shortest digits that read back as `value`, and how many sit before the decimal point.
private func shortestDigits(_ value: Double) -> (digits: String, point: Int) {
    let parts = "\(value)".split(separator: "e")
    let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
    var point = mantissa[0].count + (parts.count > 1 ? Int(parts[1])! : 0)
    var digits = Substring(mantissa.joined())
    while digits.first == "0" {
        digits.removeFirst()
        point -= 1
    }
    while digits.last == "0" { digits.removeLast() }
    return (String(digits), point)
}
