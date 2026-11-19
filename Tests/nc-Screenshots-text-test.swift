// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift

import CoreGraphics
import Foundation

func line(_ text: String, x: CGFloat = 0.1, y: CGFloat, width: CGFloat = 0.5, height: CGFloat = 0.05)
    -> ScreenTextLine {
    ScreenTextLine(text: text, box: CGRect(x: x, y: y, width: width, height: height))
}

@main
enum ScreenTextTests {
    static func main() {
        precondition(ScreenText.join([]) == nil, "no lines, no text")
        precondition(ScreenText.join([line("  ", y: 0.5), line("", y: 0.3)]) == nil, "blank lines are no text")

        let shuffled = [line("third", y: 0.76), line("first", y: 0.90), line("second", y: 0.83)]
        precondition(ScreenText.join(shuffled) == "first\nsecond\nthird", "top to bottom, whatever Vision's order")

        let row = [line("right", x: 0.6, y: 0.81, width: 0.3), line("left", x: 0.1, y: 0.80, width: 0.3)]
        precondition(ScreenText.join(row) == "left right", "one row reads left to right, despite a slight tilt")

        let paragraphs = [line("one", y: 0.90), line("two", y: 0.83), line("three", y: 0.60)]
        precondition(ScreenText.join(paragraphs) == "one\ntwo\n\nthree", "a tall gap starts a paragraph")

        let padded = [line("  first  ", y: 0.9), line("second ", y: 0.83)]
        precondition(ScreenText.join(padded) == "first\nsecond", "each line is trimmed")

        precondition(ScreenText.firstLine(of: "first\nsecond") == "first", "the notice shows the first line")
        precondition(ScreenText.firstLine(of: "only") == "only")

        print("nc-Screenshots-text-test: ok")
    }
}
