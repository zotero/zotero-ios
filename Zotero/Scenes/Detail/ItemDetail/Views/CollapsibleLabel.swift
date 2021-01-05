//
//  CollapsibleLabel.swift
//  Zotero
//
//  Created by Michal Rentka on 02/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class CollapsibleLabel: UILabel {
    var collapsedNumberOfLines: Int = 0
    var showMoreString: NSAttributedString?
    var showLessString: NSAttributedString?

    private var isCollapsed = false
    private var collapsedString: NSAttributedString?
    private var expandedString: NSAttributedString?
    private var originalString: NSAttributedString?

    func set(text: NSAttributedString, isCollapsed: Bool) {
        if self.originalString != text {
            self.createStrings(from: text)
            self.originalString = text
        }
        self.attributedText = isCollapsed ? self.collapsedString : self.expandedString
        self.isCollapsed = isCollapsed
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let original = self.originalString else { return }

        self.createStrings(from: original)
        self.attributedText = self.isCollapsed ? self.collapsedString : self.expandedString
    }

    /// Creates `collapsedString` and `expandedString` from given text.
    /// - parameter text: Text to adjust.
    private func createStrings(from text: NSAttributedString) {
        if let string = self.collapsedString(from: text) {
            self.collapsedString = string
            self.expandedString = self.expandedString(from: text) ?? text
        } else {
            self.collapsedString = text
            self.expandedString = text
        }
    }

    /// Creates an "expanded" version of given string. Expanded string appends a `showLessString` at a new line.
    /// - returns: An `NSAttributedString` with appended `showLessString` if `showLessString` is available, `nil` otherwise.
    private func expandedString(from string: NSAttributedString) -> NSAttributedString? {
        guard let showLessString = self.showLessString else { return nil }
        return self.fit(attributedString: showLessString, toLastLineOf: string, lineLimit: nil)
    }

    /// Creates a "collapsed" version of given string. Collapsed string appends a `showMoreString` at the last line, limited by `collapsedNumberOfLines`, if needed.
    /// - parameter string: String to collapse.
    /// - returns: An `NSAttributedString` with appended `showMoreString` if there are more than `collapsedNumberOfLines`, `nil` otherwise.
    private func collapsedString(from string: NSAttributedString) -> NSAttributedString? {
        guard let showMoreString = self.showMoreString,
              !string.string.isEmpty && self.collapsedNumberOfLines > 0 else { return nil }
        return self.fit(attributedString: showMoreString, toLastLineOf: string, lineLimit: self.collapsedNumberOfLines)
    }

    private func fit(attributedString stringToFit: NSAttributedString, toLastLineOf string: NSAttributedString, lineLimit: Int?) -> NSAttributedString? {
        guard let lines = string.lines(for: self.frame.width) else { return nil }

        if let limit = lineLimit, lines.count <= limit {
            return nil
        }

        let limit = lineLimit ?? lines.count
        let lastLine = lines[limit - 1]
        let lastLineWithFittedString = self.line(string.attributedString(for: lastLine), withFittedString: stringToFit)
        let result = NSMutableAttributedString()
        for index in 0..<(limit - 1) {
            result.append(string.attributedString(for: lines[index]))
        }
        result.append(lastLineWithFittedString)
        if let paragraphStyle = string.attributes(at: 0, effectiveRange: nil)[.paragraphStyle] as? NSParagraphStyle {
            result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        }

        return result
    }

    /// Create a new `NSAttributedString` from `line` by trimming last words until the remaining string appended with `string` fits one line with current label width.
    /// - parameter line: Original line.
    /// - parameter string: String which is appended to the end of the line.
    /// - returns: A new string, derived from `line`, which fits one line and has `string` appended at the end.
    private func line(_ line: NSAttributedString, withFittedString string: NSAttributedString) -> NSAttributedString {
        // Check whether the `fittedString` fits into the line as a whole
        var newLine: NSAttributedString

        // If last character of whole line is a white space, remove it
        if line.string[line.string.index(line.string.endIndex, offsetBy: -1)] == " " {
            newLine = line.attributedSubstring(from: NSRange(location: 0, length: line.length - 1))
                          .appendingString(string)
        } else {
            newLine = line.appendingString(string)
        }

        if self.textFitsWidth(text: newLine) {
            return newLine
        }

        // If it doesn't fit, go word by word and check whether it fits without given word
        (line.string as NSString).enumerateSubstrings(in: _NSRange(location: 0, length: line.length),
                                                      options: [.byWords, .reverse]) { _, subrange, _, stop in
            let length: Int
            if subrange.location == 0 {
                length = 0
            } else if line.string[line.string.index(line.string.startIndex, offsetBy: subrange.location - 1)] == " " {
                // If last character before this word is a white space, skip it
                length = subrange.location - 1
            } else {
                length = subrange.location
            }

            newLine = line.attributedSubstring(from: NSRange(location: 0, length: length))
                          .appendingString(string)

            if self.textFitsWidth(text: newLine) {
                stop.pointee = true
            }
        }

        return newLine
    }

    /// Check whether given text fits current width of label
    /// - parameter text: Text to check whether it fits
    /// - returns: `true` if it fits, `false` otherwise
    private func textFitsWidth(text: NSAttributedString) -> Bool {
        let lineHeight: CGFloat

        if let paragraphStyle = text.attributes(at: 0, effectiveRange: nil)[.paragraphStyle] as? NSParagraphStyle,
           paragraphStyle.maximumLineHeight > 0 {
            lineHeight = paragraphStyle.maximumLineHeight
        } else {
            let font = (text.attributes(at: 0, effectiveRange: nil)[.font] as? UIFont) ?? self.font
            lineHeight = font?.lineHeight ?? 0
        }

        let size = CGSize(width: self.frame.width, height: .greatestFiniteMagnitude)
        let height = text.boundingRect(with: size, options: [.usesLineFragmentOrigin], context: nil).size.height
        return height <= lineHeight
    }
}

fileprivate extension NSAttributedString {
    func lines(for width: CGFloat) -> [CTLine]? {
        let path = UIBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
        let frameSetterRef = CTFramesetterCreateWithAttributedString(self as CFAttributedString)
        let frameRef = CTFramesetterCreateFrame(frameSetterRef, CFRange(location: 0, length: 0), path.cgPath, nil)
        let lines = CTFrameGetLines(frameRef) as [AnyObject]
        return lines as? [CTLine]
    }

    func attributedString(for line: CTLine) -> NSAttributedString {
        let range = CTLineGetStringRange(line)
        return self.attributedSubstring(from: NSRange(location: range.location, length: range.length))
    }

    func appendingString(_ appendingString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: self)
        mutableString.append(appendingString)
        return mutableString
    }
}
