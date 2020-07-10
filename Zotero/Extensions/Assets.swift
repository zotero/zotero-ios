// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#elseif os(tvOS) || os(watchOS)
  import UIKit
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
    internal static let cellHighlighted = ColorAsset(name: "cellHighlighted")
    internal static let cellSelected = ColorAsset(name: "cellSelected")
    internal static let onboardingTitle = ColorAsset(name: "onboardingTitle")
    internal static let zoteroBlue = ColorAsset(name: "zoteroBlue")
  }
  internal enum Images {
    internal enum Annotations {
      internal static let area = ImageAsset(name: "Annotations/area")
      internal static let highlight = ImageAsset(name: "Annotations/highlight")
      internal static let note = ImageAsset(name: "Annotations/note")
    }
    internal static let attachmentDetailDocument = ImageAsset(name: "attachment-detail-document")
    internal static let attachmentDetailDownloadFailed = ImageAsset(name: "attachment-detail-download-failed")
    internal static let attachmentDetailDownload = ImageAsset(name: "attachment-detail-download")
    internal static let attachmentDetailLinkedDocument = ImageAsset(name: "attachment-detail-linked-document")
    internal static let attachmentDetailLinkedPdf = ImageAsset(name: "attachment-detail-linked-pdf")
    internal static let attachmentDetailLinkedUrl = ImageAsset(name: "attachment-detail-linked-url")
    internal static let attachmentDetailMissing = ImageAsset(name: "attachment-detail-missing")
    internal static let attachmentDetailPdf = ImageAsset(name: "attachment-detail-pdf")
    internal static let attachmentDetailWebpageSnapshot = ImageAsset(name: "attachment-detail-webpage-snapshot")
    internal static let attachmentListDocumentDownloadFailed = ImageAsset(name: "attachment-list-document-download-failed")
    internal static let attachmentListDocumentDownload = ImageAsset(name: "attachment-list-document-download")
    internal static let attachmentListDocumentMissing = ImageAsset(name: "attachment-list-document-missing")
    internal static let attachmentListDocument = ImageAsset(name: "attachment-list-document")
    internal static let attachmentListPdfDownloadFailed = ImageAsset(name: "attachment-list-pdf-download-failed")
    internal static let attachmentListPdfDownload = ImageAsset(name: "attachment-list-pdf-download")
    internal static let attachmentListPdfMissing = ImageAsset(name: "attachment-list-pdf-missing")
    internal static let attachmentListPdf = ImageAsset(name: "attachment-list-pdf")
    internal enum Cells {
      internal static let collection = ImageAsset(name: "Cells/collection")
      internal static let document = ImageAsset(name: "Cells/document")
      internal static let library = ImageAsset(name: "Cells/library")
      internal static let libraryReadonly = ImageAsset(name: "Cells/library_readonly")
      internal static let trash = ImageAsset(name: "Cells/trash")
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
    internal enum Onboarding {
      internal static let access = ImageAsset(name: "Onboarding/access")
      internal static let annotate = ImageAsset(name: "Onboarding/annotate")
      internal static let share = ImageAsset(name: "Onboarding/share")
      internal static let sync = ImageAsset(name: "Onboarding/sync")
    }
    internal static let emptyTrash = ImageAsset(name: "empty_trash")
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

internal struct ImageAsset {
  internal fileprivate(set) var name: String

  #if os(macOS)
  internal typealias Image = NSImage
  #elseif os(iOS) || os(tvOS) || os(watchOS)
  internal typealias Image = UIImage
  #endif

  internal var image: Image {
    let bundle = BundleToken.bundle
    #if os(iOS) || os(tvOS)
    let image = Image(named: name, in: bundle, compatibleWith: nil)
    #elseif os(macOS)
    let image = bundle.image(forResource: NSImage.Name(name))
    #elseif os(watchOS)
    let image = Image(named: name)
    #endif
    guard let result = image else {
      fatalError("Unable to load image asset named \(name).")
    }
    return result
  }
}

internal extension ImageAsset.Image {
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

// swiftlint:disable convenience_type
private final class BundleToken {
  static let bundle: Bundle = {
    Bundle(for: BundleToken.self)
  }()
}
// swiftlint:enable convenience_type
