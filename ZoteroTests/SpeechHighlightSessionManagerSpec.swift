//
//  SpeechHighlightSessionManagerSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 11.03.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import NaturalLanguage

@testable import Zotero

import Nimble
import Quick

private final class MockPageProvider: SpeechHighlightSessionManagerDelegate {
    typealias PageIndex = Int

    var pages: [Int: String] = [:]
    /// Maps pageIndex → next pageIndex
    var nextPageMap: [Int: Int] = [:]
    /// Maps pageIndex → previous pageIndex
    var previousPageMap: [Int: Int] = [:]

    func highlightSessionNextPageData(from pageIndex: Int) -> (pageText: String, pageIndex: Int)? {
        guard let nextIndex = nextPageMap[pageIndex], let text = pages[nextIndex] else { return nil }
        return (text, nextIndex)
    }

    func highlightSessionPreviousPageData(from pageIndex: Int) -> (pageText: String, pageIndex: Int)? {
        guard let prevIndex = previousPageMap[pageIndex], let text = pages[prevIndex] else { return nil }
        return (text, prevIndex)
    }
}

final class SpeechHighlightSessionManagerSpec: QuickSpec {
    // Voice info that won't go back (high progress, long elapsed)
    static let noGoBack: HighlightVoiceInfo = .remote(granularity: .sentence, audioProgress: 0.9, elapsedTime: 10)
    // Voice info that will go back (low progress, short elapsed)
    static let goBack: HighlightVoiceInfo = .remote(granularity: .sentence, audioProgress: 0.1, elapsedTime: 1)
    static let paragraphNoGoBack: HighlightVoiceInfo = .remote(granularity: .paragraph, audioProgress: 0.9, elapsedTime: 10)
    static let paragraphGoBack: HighlightVoiceInfo = .remote(granularity: .paragraph, audioProgress: 0.1, elapsedTime: 1)

    override class func spec() {
        describe("SpeechHighlightSessionManager") {
            var manager: SpeechHighlightSessionManager<MockPageProvider>!
            var mockDelegate: MockPageProvider!

            beforeEach {
                mockDelegate = MockPageProvider()
                manager = SpeechHighlightSessionManager<MockPageProvider>()
                manager.delegate = mockDelegate
            }

            // MARK: - Start Session

            describe("startSession") {
                it("starts a session at the current sentence") {
                    let pageText = "First sentence. Second sentence. Third sentence."
                    let result = manager.startSession(
                        voiceInfo: noGoBack, position: 16,
                        pageText: pageText, pageIndex: 0
                    )

                    expect(result?.text).to(equal("Second sentence."))
                    expect(result?.pageIndex).to(equal(0))
                    expect(manager.hasActiveSession).to(beTrue())
                    expect(manager.session?.unitRanges.count).to(equal(1))
                    expect(manager.session?.pageIndex).to(equal(0))
                }

                it("goes back to previous sentence with low audio progress") {
                    let pageText = "First sentence. Second sentence. Third sentence."
                    let result = manager.startSession(
                        voiceInfo: goBack, position: 16,
                        pageText: pageText, pageIndex: 0
                    )

                    expect(result?.text).to(equal("First sentence."))
                }

                it("stays on current sentence when go back but no previous exists") {
                    let pageText = "First sentence. Second sentence."
                    let result = manager.startSession(
                        voiceInfo: goBack, position: 0,
                        pageText: pageText, pageIndex: 0
                    )

                    expect(result?.text).to(equal("First sentence."))
                }

                it("goes back to previous page when at start of current page") {
                    mockDelegate.pages = [0: "Last sentence on page 1."]
                    mockDelegate.previousPageMap = [1: 0]

                    let result = manager.startSession(
                        voiceInfo: goBack, position: 0,
                        pageText: "First sentence on page 2.", pageIndex: 1
                    )

                    expect(result?.text).to(equal("Last sentence on page 1."))
                    expect(result?.pageIndex).to(equal(0))
                    expect(manager.session?.pageIndex).to(equal(0))
                }

                it("starts a session with paragraph granularity") {
                    let pageText = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
                    let result = manager.startSession(
                        voiceInfo: paragraphNoGoBack, position: 20,
                        pageText: pageText, pageIndex: 0
                    )

                    expect(result?.text).to(equal("Second paragraph."))
                }

                it("returns nil for empty text") {
                    let result = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: "", pageIndex: 0
                    )

                    expect(result).to(beNil())
                }

                context("local voice go-back heuristic") {
                    it("goes back when position is at start of sentence") {
                        let pageText = "First sentence. Second sentence. Third sentence."
                        let result = manager.startSession(
                            voiceInfo: .local, position: 16,
                            pageText: pageText, pageIndex: 0
                        )

                        expect(result?.text).to(equal("First sentence."))
                    }

                    it("does not go back when position is past midpoint of sentence") {
                        let pageText = "First sentence. Second sentence. Third sentence."
                        let result = manager.startSession(
                            voiceInfo: .local, position: 26,
                            pageText: pageText, pageIndex: 0
                        )

                        expect(result?.text).to(equal("Second sentence."))
                    }
                }
            }

            // MARK: - Move Forward

            describe("moveForward") {
                it("returns nil when no session is active") {
                    expect(manager.moveForward()).to(beNil())
                }

                it("moves to next sentence in text") {
                    let pageText = "First sentence. Second sentence. Third sentence."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: pageText, pageIndex: 0
                    )

                    let result = manager.moveForward()

                    expect(result?.text).to(equal("Second sentence."))
                    expect(result?.pageIndex).to(equal(0))
                    expect(manager.session?.unitRanges.count).to(equal(1))
                }

                it("uses anchor+1 from expanded selection instead of finding next in text") {
                    let pageText = "S1. S2. S3. S4. S5."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 8,
                        pageText: pageText, pageIndex: 0
                    )

                    _ = manager.extendForward()
                    _ = manager.extendForward()
                    expect(manager.session?.unitRanges.count).to(equal(3))

                    let result = manager.moveForward()
                    expect(result?.text).to(equal("S4."))
                    expect(manager.session?.unitRanges.count).to(equal(1))
                }

                it("crosses to next page when at end of current page") {
                    mockDelegate.pages = [1: "Next page sentence."]
                    mockDelegate.nextPageMap = [0: 1]

                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: "Only sentence.", pageIndex: 0
                    )

                    let result = manager.moveForward()
                    expect(result?.text).to(equal("Next page sentence."))
                    expect(result?.pageIndex).to(equal(1))
                    expect(manager.session?.pageIndex).to(equal(1))
                }

                it("returns nil at end of last page") {
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: "Only sentence.", pageIndex: 0
                    )

                    expect(manager.moveForward()).to(beNil())
                }
            }

            // MARK: - Move Backward

            describe("moveBackward") {
                it("returns nil when no session is active") {
                    expect(manager.moveBackward()).to(beNil())
                }

                it("moves to previous sentence in text") {
                    let pageText = "First sentence. Second sentence. Third sentence."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 16,
                        pageText: pageText, pageIndex: 0
                    )

                    let result = manager.moveBackward()

                    expect(result?.text).to(equal("First sentence."))
                    expect(result?.pageIndex).to(equal(0))
                }

                it("uses anchor-1 from expanded selection instead of finding previous in text") {
                    let pageText = "S1. S2. S3. S4. S5."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 8,
                        pageText: pageText, pageIndex: 0
                    )

                    _ = manager.extendBackward()
                    _ = manager.extendBackward()
                    expect(manager.session?.anchorIndex).to(equal(2))

                    let result = manager.moveBackward()
                    expect(result?.text).to(equal("S2."))
                    expect(manager.session?.unitRanges.count).to(equal(1))
                }

                it("crosses to previous page when at start of current page") {
                    mockDelegate.pages = [0: "Previous page sentence."]
                    mockDelegate.previousPageMap = [1: 0]

                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: "Only sentence.", pageIndex: 1
                    )

                    let result = manager.moveBackward()
                    expect(result?.text).to(equal("Previous page sentence."))
                    expect(result?.pageIndex).to(equal(0))
                    expect(manager.session?.pageIndex).to(equal(0))
                }

                it("returns nil at start of first page") {
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: "Only sentence.", pageIndex: 0
                    )

                    expect(manager.moveBackward()).to(beNil())
                }
            }

            // MARK: - Extend Forward

            describe("extendForward") {
                it("appends next unit when not expanded backward") {
                    let pageText = "S1. S2. S3."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: pageText, pageIndex: 0
                    )

                    let result = manager.extendForward()

                    expect(result?.text).to(equal("S1. S2."))
                    expect(manager.session?.unitRanges.count).to(equal(2))
                }

                it("shrinks from start when expanded backward") {
                    let pageText = "S1. S2. S3."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 4,
                        pageText: pageText, pageIndex: 0
                    )

                    _ = manager.extendBackward()
                    let result = manager.extendForward()
                    expect(result?.text).to(equal("S2."))
                    expect(manager.session?.unitRanges.count).to(equal(1))
                }

                it("does not cross to next page") {
                    mockDelegate.pages = [1: "Next page sentence."]
                    mockDelegate.nextPageMap = [0: 1]

                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: "Only sentence.", pageIndex: 0
                    )

                    expect(manager.extendForward()).to(beNil())
                }
            }

            // MARK: - Extend Backward

            describe("extendBackward") {
                it("prepends previous unit when not expanded forward") {
                    let pageText = "S1. S2. S3."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 8,
                        pageText: pageText, pageIndex: 0
                    )

                    let result = manager.extendBackward()

                    expect(result?.text).to(equal("S2. S3."))
                    expect(manager.session?.unitRanges.count).to(equal(2))
                }

                it("shrinks from end when expanded forward") {
                    let pageText = "S1. S2. S3."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 4,
                        pageText: pageText, pageIndex: 0
                    )

                    _ = manager.extendForward()
                    let result = manager.extendBackward()
                    expect(result?.text).to(equal("S2."))
                    expect(manager.session?.unitRanges.count).to(equal(1))
                }

                it("does not cross to previous page") {
                    mockDelegate.pages = [0: "Previous page sentence."]
                    mockDelegate.previousPageMap = [1: 0]

                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: "Only sentence.", pageIndex: 1
                    )

                    expect(manager.extendBackward()).to(beNil())
                }
            }

            // MARK: - End Session

            describe("endSession") {
                it("returns combined text with page index and clears session") {
                    let pageText = "S1. S2. S3."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: pageText, pageIndex: 5
                    )
                    _ = manager.extendForward()

                    let result = manager.endSession()

                    expect(result?.text).to(equal("S1. S2."))
                    expect(result?.pageIndex).to(equal(5))
                    expect(manager.hasActiveSession).to(beFalse())
                }

                it("returns nil when no session is active") {
                    expect(manager.endSession()).to(beNil())
                }
            }

            // MARK: - Cancel Session

            describe("cancelSession") {
                it("clears session without returning text") {
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: "S1. S2.", pageIndex: 0
                    )

                    manager.cancelSession()

                    expect(manager.hasActiveSession).to(beFalse())
                }
            }

            // MARK: - Complex Navigation Scenarios

            describe("complex navigation") {
                it("handles the full S1-S5 scenario from spec") {
                    let pageText = "S1. S2. S3. S4. S5."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 8,
                        pageText: pageText, pageIndex: 0
                    )

                    expect(manager.currentText()).to(equal("S3."))

                    _ = manager.extendForward()
                    expect(manager.currentText()).to(equal("S3. S4."))

                    _ = manager.extendForward()
                    expect(manager.currentText()).to(equal("S3. S4. S5."))

                    _ = manager.moveForward()
                    expect(manager.currentText()).to(equal("S4."))
                    expect(manager.session?.unitRanges.count).to(equal(1))
                }

                it("handles moveBackward when anchor-1 is out of bounds") {
                    let pageText = "S1. S2. S3. S4. S5."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 8,
                        pageText: pageText, pageIndex: 0
                    )

                    _ = manager.extendForward()
                    _ = manager.extendForward()

                    _ = manager.moveBackward()
                    expect(manager.currentText()).to(equal("S2."))
                }

                it("extend forward then backward returns to original selection") {
                    let pageText = "S1. S2. S3."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 4,
                        pageText: pageText, pageIndex: 0
                    )

                    _ = manager.extendForward()
                    expect(manager.currentText()).to(equal("S2. S3."))

                    _ = manager.extendBackward()
                    expect(manager.currentText()).to(equal("S2."))

                    _ = manager.extendBackward()
                    expect(manager.currentText()).to(equal("S1. S2."))
                }

                it("navigates across multiple pages with moveForward") {
                    mockDelegate.pages = [0: "Page 1 sentence.", 1: "Page 2 sentence.", 2: "Page 3 sentence."]
                    mockDelegate.nextPageMap = [0: 1, 1: 2]

                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: "Page 1 sentence.", pageIndex: 0
                    )

                    var result = manager.moveForward()
                    expect(result?.text).to(equal("Page 2 sentence."))
                    expect(result?.pageIndex).to(equal(1))

                    result = manager.moveForward()
                    expect(result?.text).to(equal("Page 3 sentence."))
                    expect(result?.pageIndex).to(equal(2))

                    expect(manager.moveForward()).to(beNil())
                }

                it("navigates across multiple pages with moveBackward") {
                    mockDelegate.pages = [0: "Page 1 sentence.", 1: "Page 2 sentence."]
                    mockDelegate.previousPageMap = [2: 1, 1: 0]

                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: "Page 3 sentence.", pageIndex: 2
                    )

                    var result = manager.moveBackward()
                    expect(result?.text).to(equal("Page 2 sentence."))
                    expect(result?.pageIndex).to(equal(1))

                    result = manager.moveBackward()
                    expect(result?.text).to(equal("Page 1 sentence."))
                    expect(result?.pageIndex).to(equal(0))

                    expect(manager.moveBackward()).to(beNil())
                }
            }

            // MARK: - Paragraph Granularity

            describe("paragraph granularity") {
                it("moves between paragraphs") {
                    let pageText = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
                    _ = manager.startSession(
                        voiceInfo: paragraphNoGoBack, position: 0,
                        pageText: pageText, pageIndex: 0
                    )

                    expect(manager.currentText()).to(equal("First paragraph."))

                    _ = manager.moveForward()
                    expect(manager.currentText()).to(equal("Second paragraph."))

                    _ = manager.moveForward()
                    expect(manager.currentText()).to(equal("Third paragraph."))
                }

                it("extends across paragraphs on same page") {
                    let pageText = "P1.\n\nP2.\n\nP3."
                    _ = manager.startSession(
                        voiceInfo: paragraphNoGoBack, position: 5,
                        pageText: pageText, pageIndex: 0
                    )

                    _ = manager.extendForward()
                    expect(manager.currentText()).to(equal("P2.\n\nP3."))

                    _ = manager.extendBackward()
                    expect(manager.currentText()).to(equal("P2."))

                    _ = manager.extendBackward()
                    expect(manager.currentText()).to(equal("P1.\n\nP2."))
                }

                it("goes back to previous paragraph with low progress") {
                    let pageText = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
                    let result = manager.startSession(
                        voiceInfo: paragraphGoBack, position: 20,
                        pageText: pageText, pageIndex: 0
                    )

                    expect(result?.text).to(equal("First paragraph."))
                }
            }

            // MARK: - Session Range

            describe("session range") {
                it("combined range spans all unit ranges") {
                    let pageText = "S1. S2. S3."
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: pageText, pageIndex: 0
                    )

                    _ = manager.extendForward()
                    _ = manager.extendForward()

                    let range = manager.session!.range
                    expect(range.location).to(equal(0))
                    expect(range.location + range.length).to(equal(pageText.count))
                }
            }

            // MARK: - Page Index Tracking

            describe("page index tracking") {
                it("preserves page index through navigation on same page") {
                    _ = manager.startSession(
                        voiceInfo: noGoBack, position: 0,
                        pageText: "S1. S2. S3.", pageIndex: 42
                    )

                    expect(manager.session?.pageIndex).to(equal(42))

                    _ = manager.moveForward()
                    expect(manager.session?.pageIndex).to(equal(42))

                    let result = manager.endSession()
                    expect(result?.pageIndex).to(equal(42))
                }
            }
        }
    }
}
