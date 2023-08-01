// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#elseif os(tvOS) || os(watchOS)
  import UIKit
#endif
#if canImport(SwiftUI)
  import SwiftUI
#endif

// Deprecated typealiases
@available(*, deprecated, renamed: "ColorAsset.Color", message: "This typealias will be removed in SwiftGen 7.0")
internal typealias AssetColorTypeAlias = ColorAsset.Color
@available(*, deprecated, renamed: "ImageAsset.Image", message: "This typealias will be removed in SwiftGen 7.0")
internal typealias AssetImageTypeAlias = ImageAsset.Image

// swiftlint:disable superfluous_disable_command file_length implicit_return

// MARK: - Asset Catalogs

// swiftlint:disable identifier_name line_length nesting type_body_length type_name
internal enum Asset {
  internal enum Colors {
    internal static let annotationHighlightSelection = ColorAsset(name: "annotationHighlightSelection")
    internal static let annotationPopoverBackground = ColorAsset(name: "annotationPopoverBackground")
    internal static let annotationSelectedCellBorder = ColorAsset(name: "annotationSelectedCellBorder")
    internal static let annotationSeparator = ColorAsset(name: "annotationSeparator")
    internal static let annotationSidebarBorderColor = ColorAsset(name: "annotationSidebarBorderColor")
    internal static let annotationText = ColorAsset(name: "annotationText")
    internal static let attachmentError = ColorAsset(name: "attachmentError")
    internal static let attachmentMissing = ColorAsset(name: "attachmentMissing")
    internal static let cellHighlighted = ColorAsset(name: "cellHighlighted")
    internal static let cellSelected = ColorAsset(name: "cellSelected")
    internal static let defaultCellBackground = ColorAsset(name: "defaultCellBackground")
    internal static let itemDetailDarkSeparator = ColorAsset(name: "itemDetailDarkSeparator")
    internal static let itemDetailHeaderTitle = ColorAsset(name: "itemDetailHeaderTitle")
    internal static let navbarBackground = ColorAsset(name: "navbarBackground")
    internal static let onboardingTitle = ColorAsset(name: "onboardingTitle")
    internal static let pdfScrubberBarBackground = ColorAsset(name: "pdfScrubberBarBackground")
    internal static let searchBackground = ColorAsset(name: "searchBackground")
    internal static let searchMagnifyingGlass = ColorAsset(name: "searchMagnifyingGlass")
    internal static let zoteroBlue = ColorAsset(name: "zoteroBlue")
    internal static let zoteroBlueWithDarkMode = ColorAsset(name: "zoteroBlueWithDarkMode")
    internal static let zoteroDarkBlue = ColorAsset(name: "zoteroDarkBlue")
  }
  internal enum Images {
    internal enum Annotations {
      internal static let annotationNoteColor = ImageAsset(name: "Annotations/annotation-note-color")
      internal static let annotationNote = ImageAsset(name: "Annotations/annotation-note")
      internal static let areaLarge = ImageAsset(name: "Annotations/area.large")
      internal static let areaMedium = ImageAsset(name: "Annotations/area.medium")
      internal static let commentColor = ImageAsset(name: "Annotations/comment-color")
      internal static let comment = ImageAsset(name: "Annotations/comment")
      internal static let eraserLarge = ImageAsset(name: "Annotations/eraser.large")
      internal static let highlighterLarge = ImageAsset(name: "Annotations/highlighter.large")
      internal static let highlighterMedium = ImageAsset(name: "Annotations/highlighter.medium")
      internal static let inkLarge = ImageAsset(name: "Annotations/ink.large")
      internal static let inkMedium = ImageAsset(name: "Annotations/ink.medium")
      internal static let noteLarge = ImageAsset(name: "Annotations/note.large")
      internal static let noteMedium = ImageAsset(name: "Annotations/note.medium")
    }
    internal enum Attachments {
      internal static let badgeDetailDownload = ImageAsset(name: "Attachments/badge-detail-download")
      internal static let badgeDetailFailed = ImageAsset(name: "Attachments/badge-detail-failed")
      internal static let badgeDetailMissing = ImageAsset(name: "Attachments/badge-detail-missing")
      internal static let badgeListDownload = ImageAsset(name: "Attachments/badge-list-download")
      internal static let badgeListFailed = ImageAsset(name: "Attachments/badge-list-failed")
      internal static let badgeListMissing = ImageAsset(name: "Attachments/badge-list-missing")
      internal static let badgeShareextFailed = ImageAsset(name: "Attachments/badge-shareext-failed")
      internal static let detailDocument = ImageAsset(name: "Attachments/detail-document")
      internal static let detailImage = ImageAsset(name: "Attachments/detail-image")
      internal static let detailLinkedDocument = ImageAsset(name: "Attachments/detail-linked-document")
      internal static let detailLinkedPdf = ImageAsset(name: "Attachments/detail-linked-pdf")
      internal static let detailLinkedUrl = ImageAsset(name: "Attachments/detail-linked-url")
      internal static let detailPdf = ImageAsset(name: "Attachments/detail-pdf")
      internal static let detailPlaintext = ImageAsset(name: "Attachments/detail-plaintext")
      internal static let detailWebpageSnapshot = ImageAsset(name: "Attachments/detail-webpage-snapshot")
      internal static let listDocument = ImageAsset(name: "Attachments/list-document")
      internal static let listImage = ImageAsset(name: "Attachments/list-image")
      internal static let listLink = ImageAsset(name: "Attachments/list-link")
      internal static let listPdf = ImageAsset(name: "Attachments/list-pdf")
      internal static let listPlaintext = ImageAsset(name: "Attachments/list-plaintext")
      internal static let listWebPageSnapshot = ImageAsset(name: "Attachments/list-web-page-snapshot")
    }
    internal enum Cells {
      internal static let collection = ImageAsset(name: "Cells/collection")
      internal static let collectionChildren = ImageAsset(name: "Cells/collection_children")
      internal static let document = ImageAsset(name: "Cells/document")
      internal static let library = ImageAsset(name: "Cells/library")
      internal static let libraryArchived = ImageAsset(name: "Cells/library_archived")
      internal static let libraryReadonly = ImageAsset(name: "Cells/library_readonly")
      internal static let note = ImageAsset(name: "Cells/note")
      internal static let trash = ImageAsset(name: "Cells/trash")
      internal static let unfiled = ImageAsset(name: "Cells/unfiled")
    }
    internal enum ItemTypes {
      internal static let artwork = ImageAsset(name: "Item types/artwork")
      internal static let audioRecording = ImageAsset(name: "Item types/audio-recording")
      internal static let bill = ImageAsset(name: "Item types/bill")
      internal static let blogPost = ImageAsset(name: "Item types/blog-post")
      internal static let bookSection = ImageAsset(name: "Item types/book-section")
      internal static let book = ImageAsset(name: "Item types/book")
      internal static let `case` = ImageAsset(name: "Item types/case")
      internal static let computerProgram = ImageAsset(name: "Item types/computer-program")
      internal static let conferencePaper = ImageAsset(name: "Item types/conference-paper")
      internal static let dictionaryEntry = ImageAsset(name: "Item types/dictionary-entry")
      internal static let documentLinked = ImageAsset(name: "Item types/document-linked")
      internal static let document = ImageAsset(name: "Item types/document")
      internal static let email = ImageAsset(name: "Item types/email")
      internal static let encyclopediaArticle = ImageAsset(name: "Item types/encyclopedia-article")
      internal static let film = ImageAsset(name: "Item types/film")
      internal static let forumPost = ImageAsset(name: "Item types/forum-post")
      internal static let hearing = ImageAsset(name: "Item types/hearing")
      internal static let instantMessage = ImageAsset(name: "Item types/instant-message")
      internal static let interview = ImageAsset(name: "Item types/interview")
      internal static let journalArticle = ImageAsset(name: "Item types/journal-article")
      internal static let letter = ImageAsset(name: "Item types/letter")
      internal static let magazineArticle = ImageAsset(name: "Item types/magazine-article")
      internal static let manuscript = ImageAsset(name: "Item types/manuscript")
      internal static let map = ImageAsset(name: "Item types/map")
      internal static let newspaperArticle = ImageAsset(name: "Item types/newspaper-article")
      internal static let note = ImageAsset(name: "Item types/note")
      internal static let patent = ImageAsset(name: "Item types/patent")
      internal static let pdfLinked = ImageAsset(name: "Item types/pdf-linked")
      internal static let pdf = ImageAsset(name: "Item types/pdf")
      internal static let podcast = ImageAsset(name: "Item types/podcast")
      internal static let presentation = ImageAsset(name: "Item types/presentation")
      internal static let radioBroadcast = ImageAsset(name: "Item types/radio-broadcast")
      internal static let report = ImageAsset(name: "Item types/report")
      internal static let statute = ImageAsset(name: "Item types/statute")
      internal static let thesis = ImageAsset(name: "Item types/thesis")
      internal static let tvBroadcast = ImageAsset(name: "Item types/tv-broadcast")
      internal static let videoRecording = ImageAsset(name: "Item types/video-recording")
      internal static let webPageLinked = ImageAsset(name: "Item types/web-page-linked")
      internal static let webPageSnapshot = ImageAsset(name: "Item types/web-page-snapshot")
      internal static let webPage = ImageAsset(name: "Item types/web-page")
    }
    internal enum Login {
      internal static let logo = ImageAsset(name: "Login/logo")
    }
    internal enum Onboarding {
      internal static let access = ImageAsset(name: "Onboarding/access")
      internal static let annotate = ImageAsset(name: "Onboarding/annotate")
      internal static let share = ImageAsset(name: "Onboarding/share")
      internal static let sync = ImageAsset(name: "Onboarding/sync")
    }
    internal static let dragHandle = ImageAsset(name: "drag_handle")
    internal static let emptyTrash = ImageAsset(name: "empty_trash")
    internal static let pdfRawReader = ImageAsset(name: "pdf_raw_reader")
    internal static let restoreTrash = ImageAsset(name: "restore_trash")
  }
}
// swiftlint:enable identifier_name line_length nesting type_body_length type_name

// MARK: - Implementation Details

internal final class ColorAsset {
  internal fileprivate(set) var name: String

  #if os(macOS)
  internal typealias Color = NSColor
  #elseif os(iOS) || os(tvOS) || os(watchOS)
  internal typealias Color = UIColor
  #endif

  @available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, *)
  internal private(set) lazy var color: Color = {
    guard let color = Color(asset: self) else {
      fatalError("Unable to load color asset named \(name).")
    }
    return color
  }()

  #if os(iOS) || os(tvOS)
  @available(iOS 11.0, tvOS 11.0, *)
  internal func color(compatibleWith traitCollection: UITraitCollection) -> Color {
    let bundle = BundleToken.bundle
    guard let color = Color(named: name, in: bundle, compatibleWith: traitCollection) else {
      fatalError("Unable to load color asset named \(name).")
    }
    return color
  }
  #endif

  #if canImport(SwiftUI)
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
  internal private(set) lazy var swiftUIColor: SwiftUI.Color = {
    SwiftUI.Color(asset: self)
  }()
  #endif

  fileprivate init(name: String) {
    self.name = name
  }
}

internal extension ColorAsset.Color {
  @available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, *)
  convenience init?(asset: ColorAsset) {
    let bundle = BundleToken.bundle
    #if os(iOS) || os(tvOS)
    self.init(named: asset.name, in: bundle, compatibleWith: nil)
    #elseif os(macOS)
    self.init(named: NSColor.Name(asset.name), bundle: bundle)
    #elseif os(watchOS)
    self.init(named: asset.name)
    #endif
  }
}

#if canImport(SwiftUI)
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
internal extension SwiftUI.Color {
  init(asset: ColorAsset) {
    let bundle = BundleToken.bundle
    self.init(asset.name, bundle: bundle)
  }
}
#endif

internal struct ImageAsset {
  internal fileprivate(set) var name: String

  #if os(macOS)
  internal typealias Image = NSImage
  #elseif os(iOS) || os(tvOS) || os(watchOS)
  internal typealias Image = UIImage
  #endif

  @available(iOS 8.0, tvOS 9.0, watchOS 2.0, macOS 10.7, *)
  internal var image: Image {
    let bundle = BundleToken.bundle
    #if os(iOS) || os(tvOS)
    let image = Image(named: name, in: bundle, compatibleWith: nil)
    #elseif os(macOS)
    let name = NSImage.Name(self.name)
    let image = (bundle == .main) ? NSImage(named: name) : bundle.image(forResource: name)
    #elseif os(watchOS)
    let image = Image(named: name)
    #endif
    guard let result = image else {
      fatalError("Unable to load image asset named \(name).")
    }
    return result
  }

  #if os(iOS) || os(tvOS)
  @available(iOS 8.0, tvOS 9.0, *)
  internal func image(compatibleWith traitCollection: UITraitCollection) -> Image {
    let bundle = BundleToken.bundle
    guard let result = Image(named: name, in: bundle, compatibleWith: traitCollection) else {
      fatalError("Unable to load image asset named \(name).")
    }
    return result
  }
  #endif

  #if canImport(SwiftUI)
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
  internal var swiftUIImage: SwiftUI.Image {
    SwiftUI.Image(asset: self)
  }
  #endif
}

internal extension ImageAsset.Image {
  @available(iOS 8.0, tvOS 9.0, watchOS 2.0, *)
  @available(macOS, deprecated,
    message: "This initializer is unsafe on macOS, please use the ImageAsset.image property")
  convenience init?(asset: ImageAsset) {
    #if os(iOS) || os(tvOS)
    let bundle = BundleToken.bundle
    self.init(named: asset.name, in: bundle, compatibleWith: nil)
    #elseif os(macOS)
    self.init(named: NSImage.Name(asset.name))
    #elseif os(watchOS)
    self.init(named: asset.name)
    #endif
  }
}

#if canImport(SwiftUI)
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
internal extension SwiftUI.Image {
  init(asset: ImageAsset) {
    let bundle = BundleToken.bundle
    self.init(asset.name, bundle: bundle)
  }

  init(asset: ImageAsset, label: Text) {
    let bundle = BundleToken.bundle
    self.init(asset.name, bundle: bundle, label: label)
  }

  init(decorative asset: ImageAsset) {
    let bundle = BundleToken.bundle
    self.init(decorative: asset.name, bundle: bundle)
  }
}
#endif

// swiftlint:disable convenience_type
private final class BundleToken {
  static let bundle: Bundle = {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle(for: BundleToken.self)
    #endif
  }()
}
// swiftlint:enable convenience_type
