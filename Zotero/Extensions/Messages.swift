// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal enum Messages {
  /// Due to a beta update, your data must be redownloaded from zotero.org.
  internal static let betaWipeMessage = Messages.tr("Messages", "beta_wipe_message", fallback: "Due to a beta update, your data must be redownloaded from zotero.org.")
  /// Resync Required
  internal static let betaWipeTitle = Messages.tr("Messages", "beta_wipe_title", fallback: "Resync Required")
  internal enum Errors {
    /// Failed API response: %@
    internal static func api(_ p1: Any) -> String {
      return Messages.tr("Messages", "errors.api", String(describing: p1), fallback: "Failed API response: %@")
    }
    /// Could not generate citation preview
    internal static let citationPreview = Messages.tr("Messages", "errors.citation_preview", fallback: "Could not generate citation preview")
    /// Could not connect to database. The device storage might be full.
    internal static let db = Messages.tr("Messages", "errors.db", fallback: "Could not connect to database. The device storage might be full.")
    /// Error creating database. Please try logging in again.
    internal static let dbFailure = Messages.tr("Messages", "errors.db_failure", fallback: "Error creating database. Please try logging in again.")
    /// Messages.strings
    ///   Zotero
    /// 
    ///   English-only message strings.
    internal static let parsing = Messages.tr("Messages", "errors.parsing", fallback: "Could not parse some data. Other data will continue to sync.")
    /// Unknown error
    internal static let unknown = Messages.tr("Messages", "errors.unknown", fallback: "Unknown error")
    internal enum Attachments {
      /// Unable to unzip snapshot
      internal static let cantUnzipSnapshot = Messages.tr("Messages", "errors.attachments.cant_unzip_snapshot", fallback: "Unable to unzip snapshot")
    }
    internal enum Citation {
      /// Could not generate bibliography
      internal static let generateBibliography = Messages.tr("Messages", "errors.citation.generate_bibliography", fallback: "Could not generate bibliography")
      /// Could not generate citation
      internal static let generateCitation = Messages.tr("Messages", "errors.citation.generate_citation", fallback: "Could not generate citation")
      /// Invalid item types selected
      internal static let invalidTypes = Messages.tr("Messages", "errors.citation.invalid_types", fallback: "Invalid item types selected")
      /// No citation style selected. Go to Settings → Quick Copy and select a new style.
      internal static let missingStyle = Messages.tr("Messages", "errors.citation.missing_style", fallback: "No citation style selected. Go to Settings → Quick Copy and select a new style.")
      /// Open Settings
      internal static let openSettings = Messages.tr("Messages", "errors.citation.open_settings", fallback: "Open Settings")
    }
    internal enum Collections {
      /// Could not load items for bibliography
      internal static let bibliographyFailed = Messages.tr("Messages", "errors.collections.bibliography_failed", fallback: "Could not load items for bibliography")
      /// Unable to save collection
      internal static let saveFailed = Messages.tr("Messages", "errors.collections.save_failed", fallback: "Unable to save collection")
    }
    internal enum ItemDetail {
      /// Could not create attachments
      internal static let cantCreateAttachments = Messages.tr("Messages", "errors.item_detail.cant_create_attachments", fallback: "Could not create attachments")
      /// Could not create attachments: %@
      internal static func cantCreateAttachmentsWithNames(_ p1: Any) -> String {
        return Messages.tr("Messages", "errors.item_detail.cant_create_attachments_with_names", String(describing: p1), fallback: "Could not create attachments: %@")
      }
      /// Could not load data. Please try again.
      internal static let cantLoadData = Messages.tr("Messages", "errors.item_detail.cant_load_data", fallback: "Could not load data. Please try again.")
      /// Could not save changes
      internal static let cantSaveChanges = Messages.tr("Messages", "errors.item_detail.cant_save_changes", fallback: "Could not save changes")
      /// Could not save note
      internal static let cantSaveNote = Messages.tr("Messages", "errors.item_detail.cant_save_note", fallback: "Could not save note")
      /// Could not save tags
      internal static let cantSaveTags = Messages.tr("Messages", "errors.item_detail.cant_save_tags", fallback: "Could not save tags")
      /// Could not move item to trash
      internal static let cantTrashItem = Messages.tr("Messages", "errors.item_detail.cant_trash_item", fallback: "Could not move item to trash")
      /// Type "%@" not supported
      internal static func unsupportedType(_ p1: Any) -> String {
        return Messages.tr("Messages", "errors.item_detail.unsupported_type", String(describing: p1), fallback: "Type \"%@\" not supported")
      }
    }
    internal enum Items {
      /// Could not add attachment
      internal static let addAttachment = Messages.tr("Messages", "errors.items.add_attachment", fallback: "Could not add attachment")
      /// Some attachments were not added: %@
      internal static func addSomeAttachments(_ p1: Any) -> String {
        return Messages.tr("Messages", "errors.items.add_some_attachments", String(describing: p1), fallback: "Some attachments were not added: %@")
      }
      /// Could not add item to collection
      internal static let addToCollection = Messages.tr("Messages", "errors.items.add_to_collection", fallback: "Could not add item to collection")
      /// Could not remove item
      internal static let deletion = Messages.tr("Messages", "errors.items.deletion", fallback: "Could not remove item")
      /// Could not remove item from collection
      internal static let deletionFromCollection = Messages.tr("Messages", "errors.items.deletion_from_collection", fallback: "Could not remove item from collection")
      /// Could not generate bibliography
      internal static let generatingBib = Messages.tr("Messages", "errors.items.generating_bib", fallback: "Could not generate bibliography")
      /// Could not load item to duplicate
      internal static let loadDuplication = Messages.tr("Messages", "errors.items.load_duplication", fallback: "Could not load item to duplicate")
      /// Could not load items
      internal static let loading = Messages.tr("Messages", "errors.items.loading", fallback: "Could not load items")
      /// Could not move item
      internal static let moveItem = Messages.tr("Messages", "errors.items.move_item", fallback: "Could not move item")
      /// Could not save note
      internal static let saveNote = Messages.tr("Messages", "errors.items.save_note", fallback: "Could not save note")
    }
    internal enum Libraries {
      /// Unable to load libraries
      internal static let cantLoad = Messages.tr("Messages", "errors.libraries.cantLoad", fallback: "Unable to load libraries")
    }
    internal enum Logging {
      /// Log files could not be found
      internal static let contentReading = Messages.tr("Messages", "errors.logging.content_reading", fallback: "Log files could not be found")
      /// No debug output occurred during logging
      internal static let noLogsRecorded = Messages.tr("Messages", "errors.logging.no_logs_recorded", fallback: "No debug output occurred during logging")
      /// Unexpected response from server
      internal static let responseParsing = Messages.tr("Messages", "errors.logging.response_parsing", fallback: "Unexpected response from server")
      /// Unable to start debug logging
      internal static let start = Messages.tr("Messages", "errors.logging.start", fallback: "Unable to start debug logging")
      /// Debugging Error
      internal static let title = Messages.tr("Messages", "errors.logging.title", fallback: "Debugging Error")
      /// Could not upload logs. Please try again.
      internal static let upload = Messages.tr("Messages", "errors.logging.upload", fallback: "Could not upload logs. Please try again.")
    }
    internal enum Pdf {
      /// Can’t add annotations
      internal static let cantAddAnnotations = Messages.tr("Messages", "errors.pdf.cant_add_annotations", fallback: "Can’t add annotations")
      /// Can’t delete annotations
      internal static let cantDeleteAnnotations = Messages.tr("Messages", "errors.pdf.cant_delete_annotations", fallback: "Can’t delete annotations")
      /// Can’t update annotation
      internal static let cantUpdateAnnotation = Messages.tr("Messages", "errors.pdf.cant_update_annotation", fallback: "Can’t update annotation")
      /// This document has been changed on another device. Please reopen it to continue editing.
      internal static let documentChanged = Messages.tr("Messages", "errors.pdf.document_changed", fallback: "This document has been changed on another device. Please reopen it to continue editing.")
      /// This document is empty.
      internal static let emptyDocument = Messages.tr("Messages", "errors.pdf.empty_document", fallback: "This document is empty.")
      /// This document is not supported.
      internal static let incompatibleDocument = Messages.tr("Messages", "errors.pdf.incompatible_document", fallback: "This document is not supported.")
      /// The combined annotation would be too large.
      internal static let mergeTooBig = Messages.tr("Messages", "errors.pdf.merge_too_big", fallback: "The combined annotation would be too large.")
      /// Unable to merge annotations
      internal static let mergeTooBigTitle = Messages.tr("Messages", "errors.pdf.merge_too_big_title", fallback: "Unable to merge annotations")
      /// Incorrect format of page stored for this document
      internal static let pageIndexNotInt = Messages.tr("Messages", "errors.pdf.page_index_not_int", fallback: "Incorrect format of page stored for this document")
    }
    internal enum Settings {
      /// Could not collect storage data
      internal static let storage = Messages.tr("Messages", "errors.settings.storage", fallback: "Could not collect storage data")
      internal enum Webdav {
        /// You don’t have permission to access the specified folder on the WebDAV server.
        internal static let forbidden = Messages.tr("Messages", "errors.settings.webdav.forbidden", fallback: "You don’t have permission to access the specified folder on the WebDAV server.")
        /// Could not connect to WebDAV server
        internal static let hostNotFound = Messages.tr("Messages", "errors.settings.webdav.host_not_found", fallback: "Could not connect to WebDAV server")
        /// WebDAV password missing
        internal static let noPassword = Messages.tr("Messages", "errors.settings.webdav.no_password", fallback: "WebDAV password missing")
        /// WebDAV URL missing
        internal static let noUrl = Messages.tr("Messages", "errors.settings.webdav.no_url", fallback: "WebDAV URL missing")
        /// WebDAV username missing
        internal static let noUsername = Messages.tr("Messages", "errors.settings.webdav.no_username", fallback: "WebDAV username missing")
        /// WebDAV verification error
        internal static let nonExistentFileNotMissing = Messages.tr("Messages", "errors.settings.webdav.non_existent_file_not_missing", fallback: "WebDAV verification error")
        /// WebDAV verification error
        internal static let parentDirNotFound = Messages.tr("Messages", "errors.settings.webdav.parent_dir_not_found", fallback: "WebDAV verification error")
        /// WebDAV verification error
        internal static let zoteroDirNotFound = Messages.tr("Messages", "errors.settings.webdav.zotero_dir_not_found", fallback: "WebDAV verification error")
      }
    }
    internal enum Shareext {
      /// Error uploading item. The item was saved to your local library.
      internal static let apiError = Messages.tr("Messages", "errors.shareext.api_error", fallback: "Error uploading item. The item was saved to your local library.")
      /// Failed to load data. Please try again.
      internal static let cantLoadData = Messages.tr("Messages", "errors.shareext.cant_load_data", fallback: "Failed to load data. Please try again.")
      /// An error occurred. Please open the Zotero app, sync, and try again.
      internal static let cantLoadSchema = Messages.tr("Messages", "errors.shareext.cant_load_schema", fallback: "An error occurred. Please open the Zotero app, sync, and try again.")
      /// Could not download file
      internal static let downloadFailed = Messages.tr("Messages", "errors.shareext.download_failed", fallback: "Could not download file")
      /// You can still save this page as a webpage item.
      internal static let failedAdditional = Messages.tr("Messages", "errors.shareext.failed_additional", fallback: "You can still save this page as a webpage item.")
      /// Unable to save PDF
      internal static let fileNotPdf = Messages.tr("Messages", "errors.shareext.file_not_pdf", fallback: "Unable to save PDF")
      /// No data returned
      internal static let incompatibleItem = Messages.tr("Messages", "errors.shareext.incompatible_item", fallback: "No data returned")
      /// No items found on page
      internal static let itemsNotFound = Messages.tr("Messages", "errors.shareext.items_not_found", fallback: "No items found on page")
      /// JS call failed
      internal static let javascriptFailed = Messages.tr("Messages", "errors.shareext.javascript_failed", fallback: "JS call failed")
      /// Translator missing
      internal static let missingBaseFiles = Messages.tr("Messages", "errors.shareext.missing_base_files", fallback: "Translator missing")
      /// Could not find file to upload
      internal static let missingFile = Messages.tr("Messages", "errors.shareext.missing_file", fallback: "Could not find file to upload")
      /// Error parsing translator response
      internal static let parsingError = Messages.tr("Messages", "errors.shareext.parsing_error", fallback: "Error parsing translator response")
      /// An error occurred. Please try again.
      internal static let responseMissingData = Messages.tr("Messages", "errors.shareext.response_missing_data", fallback: "An error occurred. Please try again.")
      /// Saving failed
      internal static let translationFailed = Messages.tr("Messages", "errors.shareext.translation_failed", fallback: "Saving failed")
      /// An unknown error occurred.
      internal static let unknown = Messages.tr("Messages", "errors.shareext.unknown", fallback: "An unknown error occurred.")
      /// Error uploading attachment to WebDAV server
      internal static let webdavError = Messages.tr("Messages", "errors.shareext.webdav_error", fallback: "Error uploading attachment to WebDAV server")
      /// WebDAV verification error
      internal static let webdavNotVerified = Messages.tr("Messages", "errors.shareext.webdav_not_verified", fallback: "WebDAV verification error")
    }
    internal enum Styles {
      /// Could not add style “%@”
      internal static func addition(_ p1: Any) -> String {
        return Messages.tr("Messages", "errors.styles.addition", String(describing: p1), fallback: "Could not add style “%@”")
      }
      /// Could not delete style “%@”
      internal static func deletion(_ p1: Any) -> String {
        return Messages.tr("Messages", "errors.styles.deletion", String(describing: p1), fallback: "Could not delete style “%@”")
      }
      /// Could not load styles
      internal static let loading = Messages.tr("Messages", "errors.styles.loading", fallback: "Could not load styles")
    }
    internal enum SyncToolbar {
      /// Plural format key: "%#@errors@"
      internal static func errors(_ p1: Int) -> String {
        return Messages.tr("Messages", "errors.sync_toolbar.errors", p1, fallback: "Plural format key: \"%#@errors@\"")
      }
      /// Could not sync groups. Please try again.
      internal static let groupsFailed = Messages.tr("Messages", "errors.sync_toolbar.groups_failed", fallback: "Could not sync groups. Please try again.")
      /// Plural format key: "%#@webdav_error2@"
      internal static func webdavError2(_ p1: Int) -> String {
        return Messages.tr("Messages", "errors.sync_toolbar.webdav_error2", p1, fallback: "Plural format key: \"%#@webdav_error2@\"")
      }
      /// Invalid prop file: %@
      internal static func webdavItemProp(_ p1: Any) -> String {
        return Messages.tr("Messages", "errors.sync_toolbar.webdav_item_prop", String(describing: p1), fallback: "Invalid prop file: %@")
      }
      /// Your WebDAV server returned an HTTP %d error for a %@ request.
      internal static func webdavRequestFailed(_ p1: Int, _ p2: Any) -> String {
        return Messages.tr("Messages", "errors.sync_toolbar.webdav_request_failed", p1, String(describing: p2), fallback: "Your WebDAV server returned an HTTP %d error for a %@ request.")
      }
    }
    internal enum Translators {
      /// Could not load bundled translators.
      internal static let bundleReset = Messages.tr("Messages", "errors.translators.bundle_reset", fallback: "Could not load bundled translators.")
    }
  }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

extension Messages {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg..., fallback value: String) -> String {
    let format = BundleToken.bundle.localizedString(forKey: key, value: value, table: table)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}

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
