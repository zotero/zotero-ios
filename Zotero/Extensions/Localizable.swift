// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal enum L10n {
  /// About Zotero
  internal static let aboutZotero = L10n.tr("Localizable", "about_zotero")
  /// Abstract
  internal static let abstract = L10n.tr("Localizable", "abstract")
  /// Add
  internal static let add = L10n.tr("Localizable", "add")
  /// Due to a beta update, your data must be redownloaded from zotero.org.
  internal static let betaWipeMessage = L10n.tr("Localizable", "beta_wipe_message")
  /// Resync Required
  internal static let betaWipeTitle = L10n.tr("Localizable", "beta_wipe_title")
  /// Cancel
  internal static let cancel = L10n.tr("Localizable", "cancel")
  /// Clear
  internal static let clear = L10n.tr("Localizable", "clear")
  /// Close
  internal static let close = L10n.tr("Localizable", "close")
  /// Copy
  internal static let copy = L10n.tr("Localizable", "copy")
  /// Create
  internal static let create = L10n.tr("Localizable", "create")
  /// Creator
  internal static let creator = L10n.tr("Localizable", "creator")
  /// Date
  internal static let date = L10n.tr("Localizable", "date")
  /// Date Added
  internal static let dateAdded = L10n.tr("Localizable", "date_added")
  /// Date Modified
  internal static let dateModified = L10n.tr("Localizable", "date_modified")
  /// st,nd,rd,th
  internal static let daySuffixes = L10n.tr("Localizable", "day_suffixes")
  /// Delete
  internal static let delete = L10n.tr("Localizable", "delete")
  /// Done
  internal static let done = L10n.tr("Localizable", "done")
  /// Edit
  internal static let edit = L10n.tr("Localizable", "edit")
  /// Error
  internal static let error = L10n.tr("Localizable", "error")
  /// Item Type
  internal static let itemType = L10n.tr("Localizable", "item_type")
  /// Last Updated
  internal static let lastUpdated = L10n.tr("Localizable", "last_updated")
  /// App failed to log in. Please log in again and report Debug ID %@ in the Zotero Forums.
  internal static func loginDebug(_ p1: Any) -> String {
    return L10n.tr("Localizable", "login_debug", String(describing: p1))
  }
  /// Look Up
  internal static let lookUp = L10n.tr("Localizable", "look_up")
  /// App failed to initialize and can’t function properly. Please report Debug ID %@ in the Zotero Forums.
  internal static func migrationDebug(_ p1: Any) -> String {
    return L10n.tr("Localizable", "migration_debug", String(describing: p1))
  }
  /// More Information
  internal static let moreInformation = L10n.tr("Localizable", "more_information")
  /// Move to Trash
  internal static let moveToTrash = L10n.tr("Localizable", "move_to_trash")
  /// Name
  internal static let name = L10n.tr("Localizable", "name")
  /// No
  internal static let no = L10n.tr("Localizable", "no")
  /// Not Found
  internal static let notFound = L10n.tr("Localizable", "not_found")
  /// OK
  internal static let ok = L10n.tr("Localizable", "ok")
  /// Page
  internal static let page = L10n.tr("Localizable", "page")
  /// Privacy Policy
  internal static let privacyPolicy = L10n.tr("Localizable", "privacy_policy")
  /// Publication Title
  internal static let publicationTitle = L10n.tr("Localizable", "publication_title")
  /// Publisher
  internal static let publisher = L10n.tr("Localizable", "publisher")
  /// Recents
  internal static let recent = L10n.tr("Localizable", "recent")
  /// Report
  internal static let report = L10n.tr("Localizable", "report")
  /// Restore
  internal static let restore = L10n.tr("Localizable", "restore")
  /// Retry
  internal static let retry = L10n.tr("Localizable", "retry")
  /// Save
  internal static let save = L10n.tr("Localizable", "save")
  /// Scan Text
  internal static let scanText = L10n.tr("Localizable", "scan_text")
  /// Select
  internal static let select = L10n.tr("Localizable", "select")
  /// Share
  internal static let share = L10n.tr("Localizable", "share")
  /// Support and Feedback
  internal static let supportFeedback = L10n.tr("Localizable", "support_feedback")
  /// Title
  internal static let title = L10n.tr("Localizable", "title")
  /// Total
  internal static let total = L10n.tr("Localizable", "total")
  /// Unknown
  internal static let unknown = L10n.tr("Localizable", "unknown")
  /// Warning
  internal static let warning = L10n.tr("Localizable", "warning")
  /// Year
  internal static let year = L10n.tr("Localizable", "year")
  /// Yes
  internal static let yes = L10n.tr("Localizable", "yes")

  internal enum Accessibility {
    /// Archived
    internal static let archived = L10n.tr("Localizable", "accessibility.archived")
    /// Locked
    internal static let locked = L10n.tr("Localizable", "accessibility.locked")
    /// Untitled
    internal static let untitled = L10n.tr("Localizable", "accessibility.untitled")
    internal enum Collections {
      /// Collapse
      internal static let collapse = L10n.tr("Localizable", "accessibility.collections.collapse")
      /// Create collection
      internal static let createCollection = L10n.tr("Localizable", "accessibility.collections.create_collection")
      /// Expand
      internal static let expand = L10n.tr("Localizable", "accessibility.collections.expand")
      /// Expand all collections
      internal static let expandAllCollections = L10n.tr("Localizable", "accessibility.collections.expand_all_collections")
      /// items
      internal static let items = L10n.tr("Localizable", "accessibility.collections.items")
      /// Search collections
      internal static let searchCollections = L10n.tr("Localizable", "accessibility.collections.search_collections")
    }
    internal enum ItemDetail {
      /// Double tap to download and open
      internal static let downloadAndOpen = L10n.tr("Localizable", "accessibility.item_detail.download_and_open")
      /// Double tap to open
      internal static let `open` = L10n.tr("Localizable", "accessibility.item_detail.open")
    }
    internal enum Items {
      /// Add selected items to collection
      internal static let addToCollection = L10n.tr("Localizable", "accessibility.items.add_to_collection")
      /// Delete selected items
      internal static let delete = L10n.tr("Localizable", "accessibility.items.delete")
      /// Deselect All Items
      internal static let deselectAllItems = L10n.tr("Localizable", "accessibility.items.deselect_all_items")
      /// Duplicate selected item
      internal static let duplicate = L10n.tr("Localizable", "accessibility.items.duplicate")
      /// Filter items
      internal static let filterItems = L10n.tr("Localizable", "accessibility.items.filter_items")
      /// Open item info
      internal static let openItem = L10n.tr("Localizable", "accessibility.items.open_item")
      /// Remove selected items from collection
      internal static let removeFromCollection = L10n.tr("Localizable", "accessibility.items.remove_from_collection")
      /// Restore selected items
      internal static let restore = L10n.tr("Localizable", "accessibility.items.restore")
      /// Select All Items
      internal static let selectAllItems = L10n.tr("Localizable", "accessibility.items.select_all_items")
      /// Select items
      internal static let selectItems = L10n.tr("Localizable", "accessibility.items.select_items")
      /// Share selected items
      internal static let share = L10n.tr("Localizable", "accessibility.items.share")
      /// Sort items
      internal static let sortItems = L10n.tr("Localizable", "accessibility.items.sort_items")
      /// Move selected items to trash
      internal static let trash = L10n.tr("Localizable", "accessibility.items.trash")
    }
    internal enum Pdf {
      /// Double tap to select and edit
      internal static let annotationHint = L10n.tr("Localizable", "accessibility.pdf.annotation_hint")
      /// Author
      internal static let author = L10n.tr("Localizable", "accessibility.pdf.author")
      /// Color picker
      internal static let colorPicker = L10n.tr("Localizable", "accessibility.pdf.color_picker")
      /// Comment
      internal static let comment = L10n.tr("Localizable", "accessibility.pdf.comment")
      /// Edit annotation
      internal static let editAnnotation = L10n.tr("Localizable", "accessibility.pdf.edit_annotation")
      /// Eraser
      internal static let eraserAnnotation = L10n.tr("Localizable", "accessibility.pdf.eraser_annotation")
      /// Eraser
      internal static let eraserAnnotationTool = L10n.tr("Localizable", "accessibility.pdf.eraser_annotation_tool")
      /// Export pdf
      internal static let export = L10n.tr("Localizable", "accessibility.pdf.export")
      /// Highlight annotation
      internal static let highlightAnnotation = L10n.tr("Localizable", "accessibility.pdf.highlight_annotation")
      /// Create highlight annotation
      internal static let highlightAnnotationTool = L10n.tr("Localizable", "accessibility.pdf.highlight_annotation_tool")
      /// Highlighted text
      internal static let highlightedText = L10n.tr("Localizable", "accessibility.pdf.highlighted_text")
      /// Image annotation
      internal static let imageAnnotation = L10n.tr("Localizable", "accessibility.pdf.image_annotation")
      /// Create image annotation
      internal static let imageAnnotationTool = L10n.tr("Localizable", "accessibility.pdf.image_annotation_tool")
      /// Ink annotation
      internal static let inkAnnotation = L10n.tr("Localizable", "accessibility.pdf.ink_annotation")
      /// Create ink annotation
      internal static let inkAnnotationTool = L10n.tr("Localizable", "accessibility.pdf.ink_annotation_tool")
      /// Note annotation
      internal static let noteAnnotation = L10n.tr("Localizable", "accessibility.pdf.note_annotation")
      /// Create note annotation
      internal static let noteAnnotationTool = L10n.tr("Localizable", "accessibility.pdf.note_annotation_tool")
      /// Open text reader
      internal static let openReader = L10n.tr("Localizable", "accessibility.pdf.open_reader")
      /// Redo
      internal static let redo = L10n.tr("Localizable", "accessibility.pdf.redo")
      /// Search PDF
      internal static let searchPdf = L10n.tr("Localizable", "accessibility.pdf.search_pdf")
      /// Selected
      internal static let selected = L10n.tr("Localizable", "accessibility.pdf.selected")
      /// Close sidebar
      internal static let sidebarClose = L10n.tr("Localizable", "accessibility.pdf.sidebar_close")
      /// Open sidebar
      internal static let sidebarOpen = L10n.tr("Localizable", "accessibility.pdf.sidebar_open")
      /// Tags
      internal static let tags = L10n.tr("Localizable", "accessibility.pdf.tags")
      /// Double tap to edit tags
      internal static let tagsHint = L10n.tr("Localizable", "accessibility.pdf.tags_hint")
      /// Undo
      internal static let undo = L10n.tr("Localizable", "accessibility.pdf.undo")
    }
  }

  internal enum Citation {
    /// Bibliography
    internal static let bibliography = L10n.tr("Localizable", "citation.bibliography")
    /// Citations
    internal static let citations = L10n.tr("Localizable", "citation.citations")
    /// Copy to Clipboard
    internal static let copy = L10n.tr("Localizable", "citation.copy")
    /// Copy Bibliography
    internal static let copyBibliography = L10n.tr("Localizable", "citation.copy_bibliography")
    /// Copy Citation
    internal static let copyCitation = L10n.tr("Localizable", "citation.copy_citation")
    /// Language
    internal static let language = L10n.tr("Localizable", "citation.language")
    /// Number
    internal static let locatorPlaceholder = L10n.tr("Localizable", "citation.locator_placeholder")
    /// Notes
    internal static let notes = L10n.tr("Localizable", "citation.notes")
    /// Omit Author
    internal static let omitAuthor = L10n.tr("Localizable", "citation.omit_author")
    /// Output Method
    internal static let outputMethod = L10n.tr("Localizable", "citation.output_method")
    /// Output Mode
    internal static let outputMode = L10n.tr("Localizable", "citation.output_mode")
    /// Preview:
    internal static let preview = L10n.tr("Localizable", "citation.preview")
    /// Save as HTML
    internal static let saveHtml = L10n.tr("Localizable", "citation.save_html")
    /// Style
    internal static let style = L10n.tr("Localizable", "citation.style")
    /// Citation Preview
    internal static let title = L10n.tr("Localizable", "citation.title")
    internal enum Locator {
      /// Book
      internal static let book = L10n.tr("Localizable", "citation.locator.book")
      /// Chapter
      internal static let chapter = L10n.tr("Localizable", "citation.locator.chapter")
      /// Column
      internal static let column = L10n.tr("Localizable", "citation.locator.column")
      /// Figure
      internal static let figure = L10n.tr("Localizable", "citation.locator.figure")
      /// Folio
      internal static let folio = L10n.tr("Localizable", "citation.locator.folio")
      /// Issue
      internal static let issue = L10n.tr("Localizable", "citation.locator.issue")
      /// Line
      internal static let line = L10n.tr("Localizable", "citation.locator.line")
      /// Note
      internal static let note = L10n.tr("Localizable", "citation.locator.note")
      /// Opus
      internal static let opus = L10n.tr("Localizable", "citation.locator.opus")
      /// Page
      internal static let page = L10n.tr("Localizable", "citation.locator.page")
      /// Paragraph
      internal static let paragraph = L10n.tr("Localizable", "citation.locator.paragraph")
      /// Part
      internal static let part = L10n.tr("Localizable", "citation.locator.part")
      /// Section
      internal static let section = L10n.tr("Localizable", "citation.locator.section")
      /// Sub verbo
      internal static let subVerbo = L10n.tr("Localizable", "citation.locator.sub verbo")
      /// Verse
      internal static let verse = L10n.tr("Localizable", "citation.locator.verse")
      /// Volume
      internal static let volume = L10n.tr("Localizable", "citation.locator.volume")
    }
  }

  internal enum Collections {
    /// All Items
    internal static let allItems = L10n.tr("Localizable", "collections.all_items")
    /// Collapse All
    internal static let collapseAll = L10n.tr("Localizable", "collections.collapse_all")
    /// Create Bibliography from Collection
    internal static let createBibliography = L10n.tr("Localizable", "collections.create_bibliography")
    /// Create Collection
    internal static let createTitle = L10n.tr("Localizable", "collections.create_title")
    /// Delete Collection
    internal static let delete = L10n.tr("Localizable", "collections.delete")
    /// Delete Collection and Items
    internal static let deleteWithItems = L10n.tr("Localizable", "collections.delete_with_items")
    /// Download Attachments
    internal static let downloadAttachments = L10n.tr("Localizable", "collections.download_attachments")
    /// Edit Collection
    internal static let editTitle = L10n.tr("Localizable", "collections.edit_title")
    /// Empty Trash
    internal static let emptyTrash = L10n.tr("Localizable", "collections.empty_trash")
    /// Expand All
    internal static let expandAll = L10n.tr("Localizable", "collections.expand_all")
    /// My Publications
    internal static let myPublications = L10n.tr("Localizable", "collections.my_publications")
    /// New Subcollection
    internal static let newSubcollection = L10n.tr("Localizable", "collections.new_subcollection")
    /// Choose Parent
    internal static let pickerTitle = L10n.tr("Localizable", "collections.picker_title")
    /// Find Collection
    internal static let searchTitle = L10n.tr("Localizable", "collections.search_title")
    /// Trash
    internal static let trash = L10n.tr("Localizable", "collections.trash")
    /// Unfiled Items
    internal static let unfiled = L10n.tr("Localizable", "collections.unfiled")
  }

  internal enum CreatorEditor {
    /// Creator Type
    internal static let creator = L10n.tr("Localizable", "creator_editor.creator")
    /// Do you really want to delete this creator?
    internal static let deleteConfirmation = L10n.tr("Localizable", "creator_editor.delete_confirmation")
    /// First Name
    internal static let firstName = L10n.tr("Localizable", "creator_editor.first_name")
    /// Last Name
    internal static let lastName = L10n.tr("Localizable", "creator_editor.last_name")
    /// Switch to two fields
    internal static let switchToDual = L10n.tr("Localizable", "creator_editor.switch_to_dual")
    /// Switch to single field
    internal static let switchToSingle = L10n.tr("Localizable", "creator_editor.switch_to_single")
  }

  internal enum Errors {
    /// Failed API response: %@
    internal static func api(_ p1: Any) -> String {
      return L10n.tr("Localizable", "errors.api", String(describing: p1))
    }
    /// Could not generate citation preview
    internal static let citationPreview = L10n.tr("Localizable", "errors.citation_preview")
    /// Could not connect to database. The device storage might be full.
    internal static let db = L10n.tr("Localizable", "errors.db")
    /// Error creating database. Please try logging in again.
    internal static let dbFailure = L10n.tr("Localizable", "errors.db_failure")
    /// Zotero could not find any identifiers in your input. Please verify your input and try again.
    internal static let lookup = L10n.tr("Localizable", "errors.lookup")
    /// Could not parse some data. Other data will continue to sync.
    internal static let parsing = L10n.tr("Localizable", "errors.parsing")
    /// Some data in My Library could not be downloaded. It may have been saved with a newer version of Zotero.\n\nOther data will continue to sync.
    internal static let schema = L10n.tr("Localizable", "errors.schema")
    /// Unknown error
    internal static let unknown = L10n.tr("Localizable", "errors.unknown")
    /// A remote change was made during the sync
    internal static let versionMismatch = L10n.tr("Localizable", "errors.versionMismatch")
    internal enum Attachments {
      /// The attached file could not be found.
      internal static let cantOpenAttachment = L10n.tr("Localizable", "errors.attachments.cant_open_attachment")
      /// Unable to unzip snapshot
      internal static let cantUnzipSnapshot = L10n.tr("Localizable", "errors.attachments.cant_unzip_snapshot")
      /// Linked files are not supported on iOS. You can open them using the Zotero desktop app.
      internal static let incompatibleAttachment = L10n.tr("Localizable", "errors.attachments.incompatible_attachment")
      /// Please check that the file has synced on the device where it was added.
      internal static let missingAdditional = L10n.tr("Localizable", "errors.attachments.missing_additional")
      /// The attached file is not available on the WebDAV server.
      internal static let missingWebdav = L10n.tr("Localizable", "errors.attachments.missing_webdav")
      /// The attached file is not available in the online library.
      internal static let missingZotero = L10n.tr("Localizable", "errors.attachments.missing_zotero")
    }
    internal enum Citation {
      /// Could not generate bibliography.
      internal static let generateBibliography = L10n.tr("Localizable", "errors.citation.generate_bibliography")
      /// Could not generate citation.
      internal static let generateCitation = L10n.tr("Localizable", "errors.citation.generate_citation")
      /// Invalid item types selected.
      internal static let invalidTypes = L10n.tr("Localizable", "errors.citation.invalid_types")
      /// No citation style selected. Go to Settings → Quick Copy and select a new style.
      internal static let missingStyle = L10n.tr("Localizable", "errors.citation.missing_style")
      /// Open Settings
      internal static let openSettings = L10n.tr("Localizable", "errors.citation.open_settings")
    }
    internal enum Collections {
      /// Could not load items for bibliography.
      internal static let bibliographyFailed = L10n.tr("Localizable", "errors.collections.bibliography_failed")
      /// Please enter a collection name
      internal static let emptyName = L10n.tr("Localizable", "errors.collections.empty_name")
      /// Unable to save collection
      internal static let saveFailed = L10n.tr("Localizable", "errors.collections.save_failed")
    }
    internal enum ItemDetail {
      /// Could not create attachments.
      internal static let cantCreateAttachments = L10n.tr("Localizable", "errors.item_detail.cant_create_attachments")
      /// Could not create attachments: %@
      internal static func cantCreateAttachmentsWithNames(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.item_detail.cant_create_attachments_with_names", String(describing: p1))
      }
      /// Could not load data. Please try again.
      internal static let cantLoadData = L10n.tr("Localizable", "errors.item_detail.cant_load_data")
      /// Could not save changes.
      internal static let cantSaveChanges = L10n.tr("Localizable", "errors.item_detail.cant_save_changes")
      /// Could not save note.
      internal static let cantSaveNote = L10n.tr("Localizable", "errors.item_detail.cant_save_note")
      /// Could not save tags.
      internal static let cantSaveTags = L10n.tr("Localizable", "errors.item_detail.cant_save_tags")
      /// Could not move item to trash.
      internal static let cantTrashItem = L10n.tr("Localizable", "errors.item_detail.cant_trash_item")
      /// Are you sure you want to change the item type?\n\nThe following fields will be lost:\n\n%@
      internal static func droppedFieldsMessage(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.item_detail.dropped_fields_message", String(describing: p1))
      }
      /// Change Item Type
      internal static let droppedFieldsTitle = L10n.tr("Localizable", "errors.item_detail.dropped_fields_title")
      /// Type "%@" not supported.
      internal static func unsupportedType(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.item_detail.unsupported_type", String(describing: p1))
      }
    }
    internal enum Items {
      /// Could not add attachment.
      internal static let addAttachment = L10n.tr("Localizable", "errors.items.add_attachment")
      /// Some attachments were not added: %@.
      internal static func addSomeAttachments(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.items.add_some_attachments", String(describing: p1))
      }
      /// Could not add item to collection.
      internal static let addToCollection = L10n.tr("Localizable", "errors.items.add_to_collection")
      /// Could not remove item.
      internal static let deletion = L10n.tr("Localizable", "errors.items.deletion")
      /// Could not remove item from collection.
      internal static let deletionFromCollection = L10n.tr("Localizable", "errors.items.deletion_from_collection")
      /// Could not generate bibliography
      internal static let generatingBib = L10n.tr("Localizable", "errors.items.generating_bib")
      /// Could not load item to duplicate.
      internal static let loadDuplication = L10n.tr("Localizable", "errors.items.load_duplication")
      /// Could not load items.
      internal static let loading = L10n.tr("Localizable", "errors.items.loading")
      /// Could not move item.
      internal static let moveItem = L10n.tr("Localizable", "errors.items.move_item")
      /// Could not save note.
      internal static let saveNote = L10n.tr("Localizable", "errors.items.save_note")
    }
    internal enum Libraries {
      /// Unable to load libraries
      internal static let cantLoad = L10n.tr("Localizable", "errors.libraries.cantLoad")
    }
    internal enum Logging {
      /// Log files could not be found
      internal static let contentReading = L10n.tr("Localizable", "errors.logging.content_reading")
      /// No debug output occurred during logging
      internal static let noLogsRecorded = L10n.tr("Localizable", "errors.logging.no_logs_recorded")
      /// Unexpected response from server
      internal static let responseParsing = L10n.tr("Localizable", "errors.logging.response_parsing")
      /// Unable to start debug logging
      internal static let start = L10n.tr("Localizable", "errors.logging.start")
      /// Debugging Error
      internal static let title = L10n.tr("Localizable", "errors.logging.title")
      /// Could not upload logs. Please try again.
      internal static let upload = L10n.tr("Localizable", "errors.logging.upload")
    }
    internal enum Login {
      /// Invalid username or password
      internal static let invalidCredentials = L10n.tr("Localizable", "errors.login.invalid_credentials")
      /// Invalid password
      internal static let invalidPassword = L10n.tr("Localizable", "errors.login.invalid_password")
      /// Invalid username
      internal static let invalidUsername = L10n.tr("Localizable", "errors.login.invalid_username")
    }
    internal enum Settings {
      /// Could not collect storage data
      internal static let storage = L10n.tr("Localizable", "errors.settings.storage")
      internal enum Webdav {
        /// A potential problem was found with your WebDAV server.\n\nAn uploaded file was not immediately available for download. There may be a short delay between when you upload files and when they become available, particularly if you are using a cloud storage service.\n\nIf Zotero file syncing appears to work normally, you can ignore this message. If you have trouble, please post to the Zotero Forums.
        internal static let fileMissingAfterUpload = L10n.tr("Localizable", "errors.settings.webdav.file_missing_after_upload")
        /// You don’t have permission to access the specified folder on the WebDAV server.
        internal static let forbidden = L10n.tr("Localizable", "errors.settings.webdav.forbidden")
        /// Could not connect to WebDAV server
        internal static let hostNotFound = L10n.tr("Localizable", "errors.settings.webdav.host_not_found")
        /// Unable to connect to the network. Please try again.
        internal static let internetConnection = L10n.tr("Localizable", "errors.settings.webdav.internet_connection")
        /// WebDAV verification error
        internal static let invalidUrl = L10n.tr("Localizable", "errors.settings.webdav.invalid_url")
        /// WebDAV verification error
        internal static let noPassword = L10n.tr("Localizable", "errors.settings.webdav.no_password")
        /// WebDAV verification error
        internal static let noUrl = L10n.tr("Localizable", "errors.settings.webdav.no_url")
        /// WebDAV verification error
        internal static let noUsername = L10n.tr("Localizable", "errors.settings.webdav.no_username")
        /// WebDAV verification error
        internal static let nonExistentFileNotMissing = L10n.tr("Localizable", "errors.settings.webdav.non_existent_file_not_missing")
        /// Not a valid WebDAV URL
        internal static let notDav = L10n.tr("Localizable", "errors.settings.webdav.not_dav")
        /// WebDAV verification error
        internal static let parentDirNotFound = L10n.tr("Localizable", "errors.settings.webdav.parent_dir_not_found")
        /// The WebDAV server did not accept the username and password you entered.
        internal static let unauthorized = L10n.tr("Localizable", "errors.settings.webdav.unauthorized")
        /// WebDAV verification error
        internal static let zoteroDirNotFound = L10n.tr("Localizable", "errors.settings.webdav.zotero_dir_not_found")
      }
    }
    internal enum Shareext {
      /// Error uploading item. The item was saved to your local library.
      internal static let apiError = L10n.tr("Localizable", "errors.shareext.api_error")
      /// Background uploader not initialized
      internal static let backgroundUploaderFailure = L10n.tr("Localizable", "errors.shareext.background_uploader_failure")
      /// An error occurred. Please try again.
      internal static let cantLoadData = L10n.tr("Localizable", "errors.shareext.cant_load_data")
      /// An error occurred. Please open the Zotero app, sync, and try again.
      internal static let cantLoadSchema = L10n.tr("Localizable", "errors.shareext.cant_load_schema")
      /// Could not download file
      internal static let downloadFailed = L10n.tr("Localizable", "errors.shareext.download_failed")
      /// You can still save this page as a webpage item.
      internal static let failedAdditional = L10n.tr("Localizable", "errors.shareext.failed_additional")
      /// Unable to save PDF
      internal static let fileNotPdf = L10n.tr("Localizable", "errors.shareext.file_not_pdf")
      /// The group “%@” has reached its Zotero Storage quota, and the file could not be uploaded. The group owner can view their account settings for additional storage options.\n\nThe file was saved to the local library.
      internal static func groupQuotaReached(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.shareext.group_quota_reached", String(describing: p1))
      }
      /// No data returned
      internal static let incompatibleItem = L10n.tr("Localizable", "errors.shareext.incompatible_item")
      /// No items found on page
      internal static let itemsNotFound = L10n.tr("Localizable", "errors.shareext.items_not_found")
      /// JS call failed
      internal static let javascriptFailed = L10n.tr("Localizable", "errors.shareext.javascript_failed")
      /// Please log into the app before using this extension.
      internal static let loggedOut = L10n.tr("Localizable", "errors.shareext.logged_out")
      /// Translator missing
      internal static let missingBaseFiles = L10n.tr("Localizable", "errors.shareext.missing_base_files")
      /// Could not find file to upload
      internal static let missingFile = L10n.tr("Localizable", "errors.shareext.missing_file")
      /// Error parsing translator response
      internal static let parsingError = L10n.tr("Localizable", "errors.shareext.parsing_error")
      /// You have reached your Zotero Storage quota, and the file could not be uploaded. See your account settings for additional storage options.\n\nThe file was saved to your local library.
      internal static let personalQuotaReached = L10n.tr("Localizable", "errors.shareext.personal_quota_reached")
      /// An error occurred. Please try again.
      internal static let responseMissingData = L10n.tr("Localizable", "errors.shareext.response_missing_data")
      /// Some data could not be downloaded. It may have been saved with a newer version of Zotero.
      internal static let schemaError = L10n.tr("Localizable", "errors.shareext.schema_error")
      /// Saving failed
      internal static let translationFailed = L10n.tr("Localizable", "errors.shareext.translation_failed")
      /// An unknown error occurred.
      internal static let unknown = L10n.tr("Localizable", "errors.shareext.unknown")
      /// Error uploading attachment to WebDAV server
      internal static let webdavError = L10n.tr("Localizable", "errors.shareext.webdav_error")
      /// WebDAV verification error
      internal static let webdavNotVerified = L10n.tr("Localizable", "errors.shareext.webdav_not_verified")
    }
    internal enum Styles {
      /// Could not add style “%@”.
      internal static func addition(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.styles.addition", String(describing: p1))
      }
      /// Could not delete style “%@”.
      internal static func deletion(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.styles.deletion", String(describing: p1))
      }
      /// Could not load styles.
      internal static let loading = L10n.tr("Localizable", "errors.styles.loading")
    }
    internal enum StylesSearch {
      /// Could not load styles. Do you want to try again?
      internal static let loading = L10n.tr("Localizable", "errors.styles_search.loading")
    }
    internal enum SyncToolbar {
      /// Unable to upload attachment: %@. Please try removing and re-adding the attachment.
      internal static func attachmentMissing(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.attachment_missing", String(describing: p1))
      }
      /// Remote sync in progress. Please try again in a few minutes.
      internal static let conflictRetryLimit = L10n.tr("Localizable", "errors.sync_toolbar.conflict_retry_limit")
      /// Finished sync (%@)
      internal static func finishedWithErrors(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.finished_with_errors", String(describing: p1))
      }
      /// Invalid username or password
      internal static let forbidden = L10n.tr("Localizable", "errors.sync_toolbar.forbidden")
      /// The Zotero sync server did not accept your username and password.\n\nPlease log out and log in with correct login information.
      internal static let forbiddenMessage = L10n.tr("Localizable", "errors.sync_toolbar.forbidden_message")
      /// You don’t have permission to edit groups.
      internal static let groupPermissions = L10n.tr("Localizable", "errors.sync_toolbar.group_permissions")
      /// The group “%@” has reached its Zotero File Storage quota. Some files were not uploaded. Other Zotero data will continue to sync to the server.\nThe group owner can increase the group's storage capacity from the storage settings section on zotero.org.
      internal static func groupQuotaReached(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.group_quota_reached", String(describing: p1))
      }
      /// Could not sync groups. Please try again.
      internal static let groupsFailed = L10n.tr("Localizable", "errors.sync_toolbar.groups_failed")
      /// You have insufficient space on your server. Some files were not uploaded. Other Zotero data will continue to sync to our server.
      internal static let insufficientSpace = L10n.tr("Localizable", "errors.sync_toolbar.insufficient_space")
      /// Unable to connect to the network. Please try again.
      internal static let internetConnection = L10n.tr("Localizable", "errors.sync_toolbar.internet_connection")
      /// No libraries found. Please sign out and back in again.
      internal static let librariesMissing = L10n.tr("Localizable", "errors.sync_toolbar.libraries_missing")
      /// %d issues
      internal static func multipleErrors(_ p1: Int) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.multiple_errors", p1)
      }
      /// 1 issue
      internal static let oneError = L10n.tr("Localizable", "errors.sync_toolbar.one_error")
      /// You have reached your Zotero File Storage quota. Some files were not uploaded. Other Zotero data will continue to sync to the server.\nSee your zotero.org account settings for additional storage options.
      internal static let personalQuotaReached = L10n.tr("Localizable", "errors.sync_toolbar.personal_quota_reached")
      /// Quota Reached.
      internal static let quotaReachedShort = L10n.tr("Localizable", "errors.sync_toolbar.quota_reached_short")
      /// Show Item
      internal static let showItem = L10n.tr("Localizable", "errors.sync_toolbar.show_item")
      /// Show Items
      internal static let showItems = L10n.tr("Localizable", "errors.sync_toolbar.show_items")
      /// Zotero services are temporarily unavailable. Please try again in a few minutes.
      internal static let unavailable = L10n.tr("Localizable", "errors.sync_toolbar.unavailable")
      /// Could not delete files from your WebDAV server: "%@".
      internal static func webdavError(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.webdav_error", String(describing: p1))
      }
      /// Could not delete %d file(s) from your WebDAV server.
      internal static func webdavError2(_ p1: Int) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.webdav_error2", p1)
      }
      /// Invalid prop file: %@
      internal static func webdavItemProp(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.webdav_item_prop", String(describing: p1))
      }
    }
    internal enum Translators {
      /// Could not update translators from bundle. Would you like to try again?
      internal static let bundleLoading = L10n.tr("Localizable", "errors.translators.bundle_loading")
      /// Could not load bundled translators.
      internal static let bundleReset = L10n.tr("Localizable", "errors.translators.bundle_reset")
    }
  }

  internal enum ItemDetail {
    /// Add attachment
    internal static let addAttachment = L10n.tr("Localizable", "item_detail.add_attachment")
    /// Add Creator
    internal static let addCreator = L10n.tr("Localizable", "item_detail.add_creator")
    /// Add note
    internal static let addNote = L10n.tr("Localizable", "item_detail.add_note")
    /// Add tag
    internal static let addTag = L10n.tr("Localizable", "item_detail.add_tag")
    /// Attachments
    internal static let attachments = L10n.tr("Localizable", "item_detail.attachments")
    /// This item has been changed remotely. It will now reload.
    internal static let dataReloaded = L10n.tr("Localizable", "item_detail.data_reloaded")
    /// Remove Download
    internal static let deleteAttachmentFile = L10n.tr("Localizable", "item_detail.delete_attachment_file")
    /// This item has been deleted. Do you want to restore it?
    internal static let deletedMessage = L10n.tr("Localizable", "item_detail.deleted_message")
    /// Deleted
    internal static let deletedTitle = L10n.tr("Localizable", "item_detail.deleted_title")
    /// Merge name
    internal static let mergeName = L10n.tr("Localizable", "item_detail.merge_name")
    /// Move to Standalone Attachment
    internal static let moveToStandaloneAttachment = L10n.tr("Localizable", "item_detail.move_to_standalone_attachment")
    /// Notes
    internal static let notes = L10n.tr("Localizable", "item_detail.notes")
    /// Show less
    internal static let showLess = L10n.tr("Localizable", "item_detail.show_less")
    /// Show more
    internal static let showMore = L10n.tr("Localizable", "item_detail.show_more")
    /// Split name
    internal static let splitName = L10n.tr("Localizable", "item_detail.split_name")
    /// Tags
    internal static let tags = L10n.tr("Localizable", "item_detail.tags")
    /// Untitled
    internal static let untitled = L10n.tr("Localizable", "item_detail.untitled")
    /// View PDF
    internal static let viewPdf = L10n.tr("Localizable", "item_detail.view_pdf")
  }

  internal enum Items {
    /// Ascending
    internal static let ascending = L10n.tr("Localizable", "items.ascending")
    /// Scan Barcode
    internal static let barcode = L10n.tr("Localizable", "items.barcode")
    /// Are you sure you want to delete selected items?
    internal static let deleteMultipleQuestion = L10n.tr("Localizable", "items.delete_multiple_question")
    /// Are you sure you want to delete the selected item?
    internal static let deleteQuestion = L10n.tr("Localizable", "items.delete_question")
    /// Descending
    internal static let descending = L10n.tr("Localizable", "items.descending")
    /// Deselect All
    internal static let deselectAll = L10n.tr("Localizable", "items.deselect_all")
    /// Generating Bibliography
    internal static let generatingBib = L10n.tr("Localizable", "items.generating_bib")
    /// Add by Identifier
    internal static let lookup = L10n.tr("Localizable", "items.lookup")
    /// %d Collections Selected
    internal static func manyCollectionsSelected(_ p1: Int) -> String {
      return L10n.tr("Localizable", "items.many_collections_selected", p1)
    }
    /// Add Manually
    internal static let new = L10n.tr("Localizable", "items.new")
    /// Add File
    internal static let newFile = L10n.tr("Localizable", "items.new_file")
    /// New Standalone Note
    internal static let newNote = L10n.tr("Localizable", "items.new_note")
    /// 1 Collection Selected
    internal static let oneCollectionsSelected = L10n.tr("Localizable", "items.one_collections_selected")
    /// Are you sure you want to remove selected items from this collection?
    internal static let removeFromCollectionMultipleQuestion = L10n.tr("Localizable", "items.remove_from_collection_multiple_question")
    /// Are you sure you want to remove the selected item from this collection?
    internal static let removeFromCollectionQuestion = L10n.tr("Localizable", "items.remove_from_collection_question")
    /// Remove from Collection
    internal static let removeFromCollectionTitle = L10n.tr("Localizable", "items.remove_from_collection_title")
    /// Search Items
    internal static let searchTitle = L10n.tr("Localizable", "items.search_title")
    /// Select All
    internal static let selectAll = L10n.tr("Localizable", "items.select_all")
    /// Sort By
    internal static let sortBy = L10n.tr("Localizable", "items.sort_by")
    /// Sort Order
    internal static let sortOrder = L10n.tr("Localizable", "items.sort_order")
    /// Downloaded %d / %d
    internal static func toolbarDownloaded(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "items.toolbar_downloaded", p1, p2)
    }
    /// Filter: %d items
    internal static func toolbarFilterMultiple(_ p1: Int) -> String {
      return L10n.tr("Localizable", "items.toolbar_filter_multiple", p1)
    }
    /// Filter: 1 item
    internal static let toolbarFilterSingle = L10n.tr("Localizable", "items.toolbar_filter_single")
    /// Select a Collection
    internal static let zeroCollectionsSelected = L10n.tr("Localizable", "items.zero_collections_selected")
    internal enum Action {
      /// Add to Collection
      internal static let addToCollection = L10n.tr("Localizable", "items.action.add_to_collection")
      /// Create Parent Item
      internal static let createParent = L10n.tr("Localizable", "items.action.create_parent")
      /// Download
      internal static let download = L10n.tr("Localizable", "items.action.download")
      /// Duplicate
      internal static let duplicate = L10n.tr("Localizable", "items.action.duplicate")
      /// Remove Download
      internal static let removeDownload = L10n.tr("Localizable", "items.action.remove_download")
      /// Remove from Collection
      internal static let removeFromCollection = L10n.tr("Localizable", "items.action.remove_from_collection")
    }
    internal enum CreatorSummary {
      /// %@ and %@
      internal static func and(_ p1: Any, _ p2: Any) -> String {
        return L10n.tr("Localizable", "items.creator_summary.and", String(describing: p1), String(describing: p2))
      }
      /// %@ et al.
      internal static func etal(_ p1: Any) -> String {
        return L10n.tr("Localizable", "items.creator_summary.etal", String(describing: p1))
      }
    }
    internal enum Filters {
      /// Downloaded Files
      internal static let downloads = L10n.tr("Localizable", "items.filters.downloads")
      /// Tags
      internal static let tags = L10n.tr("Localizable", "items.filters.tags")
      /// Filters
      internal static let title = L10n.tr("Localizable", "items.filters.title")
    }
  }

  internal enum Libraries {
    /// Do you really want to delete "%@"?
    internal static func deleteQuestion(_ p1: Any) -> String {
      return L10n.tr("Localizable", "libraries.delete_question", String(describing: p1))
    }
    /// Group Libraries
    internal static let groupLibraries = L10n.tr("Localizable", "libraries.group_libraries")
    /// My Library
    internal static let myLibrary = L10n.tr("Localizable", "libraries.my_library")
  }

  internal enum Login {
    /// Email
    internal static let email = L10n.tr("Localizable", "login.email")
    /// Forgot Password?
    internal static let forgotPassword = L10n.tr("Localizable", "login.forgot_password")
    /// Password
    internal static let password = L10n.tr("Localizable", "login.password")
    /// Repeat password
    internal static let repeatPassword = L10n.tr("Localizable", "login.repeat_password")
    /// Username
    internal static let username = L10n.tr("Localizable", "login.username")
  }

  internal enum Lookup {
    /// Enter ISBNs, DOls, PMIDs, arXiv IDs, or ADS Bibcodes to add to your library:
    internal static let title = L10n.tr("Localizable", "lookup.title")
  }

  internal enum Onboarding {
    /// <b>Zotero organizes research</b> however you want. Sort your items into collections and tag them with keywords.
    internal static let access = L10n.tr("Localizable", "onboarding.access")
    /// <b>Highlight and take notes</b> directly in your PDFs as you read them.
    internal static let annotate = L10n.tr("Localizable", "onboarding.annotate")
    /// Sign Up
    internal static let createAccount = L10n.tr("Localizable", "onboarding.create_account")
    /// <b>Tap to collect</b> articles and books directly from the web, including their PDFs and full metadata.
    internal static let share = L10n.tr("Localizable", "onboarding.share")
    /// Sign In
    internal static let signIn = L10n.tr("Localizable", "onboarding.sign_in")
    /// <b>Synchronize and collaborate</b> across devices, keeping your reading and notes seamlessly up to date.
    internal static let sync = L10n.tr("Localizable", "onboarding.sync")
  }

  internal enum Pdf {
    /// This document has been deleted. Do you want to restore it?
    internal static let deletedMessage = L10n.tr("Localizable", "pdf.deleted_message")
    /// Deleted
    internal static let deletedTitle = L10n.tr("Localizable", "pdf.deleted_title")
    /// Highlight
    internal static let highlight = L10n.tr("Localizable", "pdf.highlight")
    /// %0.1f pt
    internal static func lineWidthPoint(_ p1: Float) -> String {
      return L10n.tr("Localizable", "pdf.line_width_point", p1)
    }
    internal enum AnnotationPopover {
      /// Delete Annotation
      internal static let delete = L10n.tr("Localizable", "pdf.annotation_popover.delete")
      /// Width
      internal static let lineWidth = L10n.tr("Localizable", "pdf.annotation_popover.line_width")
      /// No comment
      internal static let noComment = L10n.tr("Localizable", "pdf.annotation_popover.no_comment")
      /// Edit Page Number
      internal static let pageLabelTitle = L10n.tr("Localizable", "pdf.annotation_popover.page_label_title")
      /// Size
      internal static let size = L10n.tr("Localizable", "pdf.annotation_popover.size")
      /// Edit Annotation
      internal static let title = L10n.tr("Localizable", "pdf.annotation_popover.title")
      /// Update subsequent pages
      internal static let updateSubsequentPages = L10n.tr("Localizable", "pdf.annotation_popover.update_subsequent_pages")
    }
    internal enum AnnotationsSidebar {
      /// Add comment
      internal static let addComment = L10n.tr("Localizable", "pdf.annotations_sidebar.add_comment")
      /// Add tags
      internal static let addTags = L10n.tr("Localizable", "pdf.annotations_sidebar.add_tags")
      /// Merge
      internal static let merge = L10n.tr("Localizable", "pdf.annotations_sidebar.merge")
      /// Search
      internal static let searchTitle = L10n.tr("Localizable", "pdf.annotations_sidebar.search_title")
      internal enum Filter {
        /// Select Tags…
        internal static let tagsPlaceholder = L10n.tr("Localizable", "pdf.annotations_sidebar.filter.tags_placeholder")
        /// Filter Annotations
        internal static let title = L10n.tr("Localizable", "pdf.annotations_sidebar.filter.title")
      }
    }
    internal enum Export {
      /// Export
      internal static let export = L10n.tr("Localizable", "pdf.export.export")
      /// Include annotations
      internal static let includeAnnotations = L10n.tr("Localizable", "pdf.export.include_annotations")
    }
    internal enum Search {
      /// Search failed
      internal static let failed = L10n.tr("Localizable", "pdf.search.failed")
      /// Found %d matches
      internal static func multipleMatches(_ p1: Int) -> String {
        return L10n.tr("Localizable", "pdf.search.multiple_matches", p1)
      }
      /// Found 1 match
      internal static let oneMatch = L10n.tr("Localizable", "pdf.search.one_match")
      /// Search in Document
      internal static let title = L10n.tr("Localizable", "pdf.search.title")
    }
    internal enum Settings {
      /// Allow device to sleep
      internal static let idleTimerTitle = L10n.tr("Localizable", "pdf.settings.idle_timer_title")
      internal enum Appearance {
        /// Automatic
        internal static let auto = L10n.tr("Localizable", "pdf.settings.appearance.auto")
        /// Dark
        internal static let darkMode = L10n.tr("Localizable", "pdf.settings.appearance.dark_mode")
        /// Light
        internal static let lightMode = L10n.tr("Localizable", "pdf.settings.appearance.light_mode")
        /// Appearance
        internal static let title = L10n.tr("Localizable", "pdf.settings.appearance.title")
      }
      internal enum PageFitting {
        /// Automatic
        internal static let automatic = L10n.tr("Localizable", "pdf.settings.page_fitting.automatic")
        /// Fill
        internal static let fill = L10n.tr("Localizable", "pdf.settings.page_fitting.fill")
        /// Fit
        internal static let fit = L10n.tr("Localizable", "pdf.settings.page_fitting.fit")
        /// Page Fitting
        internal static let title = L10n.tr("Localizable", "pdf.settings.page_fitting.title")
      }
      internal enum PageMode {
        /// Automatic
        internal static let automatic = L10n.tr("Localizable", "pdf.settings.page_mode.automatic")
        /// Double
        internal static let double = L10n.tr("Localizable", "pdf.settings.page_mode.double")
        /// Single
        internal static let single = L10n.tr("Localizable", "pdf.settings.page_mode.single")
        /// Page Mode
        internal static let title = L10n.tr("Localizable", "pdf.settings.page_mode.title")
      }
      internal enum PageTransition {
        /// Continuous
        internal static let continuous = L10n.tr("Localizable", "pdf.settings.page_transition.continuous")
        /// Jump
        internal static let jump = L10n.tr("Localizable", "pdf.settings.page_transition.jump")
        /// Page Transition
        internal static let title = L10n.tr("Localizable", "pdf.settings.page_transition.title")
      }
      internal enum ScrollDirection {
        /// Horizontal
        internal static let horizontal = L10n.tr("Localizable", "pdf.settings.scroll_direction.horizontal")
        /// Scroll Direction
        internal static let title = L10n.tr("Localizable", "pdf.settings.scroll_direction.title")
        /// Vertical
        internal static let vertical = L10n.tr("Localizable", "pdf.settings.scroll_direction.vertical")
      }
    }
    internal enum Sidebar {
      /// No Annotations
      internal static let noAnnotations = L10n.tr("Localizable", "pdf.sidebar.no_annotations")
      /// No Outline
      internal static let noOutline = L10n.tr("Localizable", "pdf.sidebar.no_outline")
    }
  }

  internal enum Searchbar {
    /// Cancel Search
    internal static let accessibilityCancel = L10n.tr("Localizable", "searchbar.accessibility_cancel")
    /// Clear Search
    internal static let accessibilityClear = L10n.tr("Localizable", "searchbar.accessibility_clear")
    /// Search
    internal static let placeholder = L10n.tr("Localizable", "searchbar.placeholder")
  }

  internal enum Settings {
    /// Debug Output Logging
    internal static let debug = L10n.tr("Localizable", "settings.debug")
    /// Export Database File
    internal static let exportDb = L10n.tr("Localizable", "settings.export_db")
    /// Item count
    internal static let itemCount = L10n.tr("Localizable", "settings.item_count")
    /// Show item count for all collections.
    internal static let itemCountSubtitle = L10n.tr("Localizable", "settings.item_count_subtitle")
    /// To debug a startup issue, force-quit the app and start it again.
    internal static let loggingDesc1 = L10n.tr("Localizable", "settings.logging_desc1")
    /// To debug a share extension issue, open the share extension.
    internal static let loggingDesc2 = L10n.tr("Localizable", "settings.logging_desc2")
    /// Logging
    internal static let loggingTitle = L10n.tr("Localizable", "settings.logging_title")
    /// Sign Out
    internal static let logout = L10n.tr("Localizable", "settings.logout")
    /// Any local data that was not synced will be deleted. Do you really want to sign out?
    internal static let logoutWarning = L10n.tr("Localizable", "settings.logout_warning")
    /// User Permission
    internal static let permission = L10n.tr("Localizable", "settings.permission")
    /// Ask for user permission for each write action
    internal static let permissionSubtitle = L10n.tr("Localizable", "settings.permission_subtitle")
    /// Reset to bundled
    internal static let resetToBundled = L10n.tr("Localizable", "settings.reset_to_bundled")
    /// Send Manually
    internal static let sendManually = L10n.tr("Localizable", "settings.send_manually")
    /// Start Logging
    internal static let startLogging = L10n.tr("Localizable", "settings.start_logging")
    /// Start Logging on Next App Launch
    internal static let startLoggingOnLaunch = L10n.tr("Localizable", "settings.start_logging_on_launch")
    /// Stop Logging
    internal static let stopLogging = L10n.tr("Localizable", "settings.stop_logging")
    /// Local Storage
    internal static let storage = L10n.tr("Localizable", "settings.storage")
    /// Settings
    internal static let title = L10n.tr("Localizable", "settings.title")
    /// Translators
    internal static let translators = L10n.tr("Localizable", "settings.translators")
    /// Update translators
    internal static let translatorsUpdate = L10n.tr("Localizable", "settings.translators_update")
    /// Updating…
    internal static let translatorsUpdating = L10n.tr("Localizable", "settings.translators_updating")
    /// Version %@ Build %@
    internal static func versionAndBuild(_ p1: Any, _ p2: Any) -> String {
      return L10n.tr("Localizable", "settings.versionAndBuild", String(describing: p1), String(describing: p2))
    }
    /// Connect to Server
    internal static let websocketConnect = L10n.tr("Localizable", "settings.websocket_connect")
    /// Connected
    internal static let websocketConnected = L10n.tr("Localizable", "settings.websocket_connected")
    /// Connecting
    internal static let websocketConnecting = L10n.tr("Localizable", "settings.websocket_connecting")
    /// Disconnect from Server
    internal static let websocketDisconnect = L10n.tr("Localizable", "settings.websocket_disconnect")
    /// Disconnected
    internal static let websocketDisconnected = L10n.tr("Localizable", "settings.websocket_disconnected")
    /// Server Connection
    internal static let websocketTitle = L10n.tr("Localizable", "settings.websocket_title")
    internal enum Cite {
      /// Get additional styles
      internal static let getMoreStyles = L10n.tr("Localizable", "settings.cite.get_more_styles")
      /// Citation Styles
      internal static let stylesTitle = L10n.tr("Localizable", "settings.cite.styles_title")
      /// Cite
      internal static let title = L10n.tr("Localizable", "settings.cite.title")
    }
    internal enum CiteSearch {
      /// Search styles
      internal static let searchTitle = L10n.tr("Localizable", "settings.cite_search.search_title")
    }
    internal enum CrashAlert {
      /// Copy and Export Database
      internal static let exportDb = L10n.tr("Localizable", "settings.crash_alert.export_db")
      /// Your Report ID is %@
      internal static func message(_ p1: Any) -> String {
        return L10n.tr("Localizable", "settings.crash_alert.message", String(describing: p1))
      }
      /// Your Report ID is %@. If Zotero crashes repeatedly, please tap "Export Database" and send exported files to support@zotero.org.
      internal static func messageWithDb(_ p1: Any) -> String {
        return L10n.tr("Localizable", "settings.crash_alert.message_with_db", String(describing: p1))
      }
      /// Crash Log Sent
      internal static let title = L10n.tr("Localizable", "settings.crash_alert.title")
    }
    internal enum Export {
      /// Copy as HTML
      internal static let copyAsHtml = L10n.tr("Localizable", "settings.export.copy_as_html")
      /// Default Format
      internal static let defaultFormat = L10n.tr("Localizable", "settings.export.default_format")
      /// Language
      internal static let language = L10n.tr("Localizable", "settings.export.language")
      /// Quick Copy
      internal static let title = L10n.tr("Localizable", "settings.export.title")
    }
    internal enum General {
      /// Show collection sizes
      internal static let showCollectionItemCounts = L10n.tr("Localizable", "settings.general.show_collection_item_counts")
      /// Show Items from Subcollections
      internal static let showSubcollectionsTitle = L10n.tr("Localizable", "settings.general.show_subcollections_title")
      /// General
      internal static let title = L10n.tr("Localizable", "settings.general.title")
    }
    internal enum LogAlert {
      /// Your Debug ID is %@
      internal static func message(_ p1: Any) -> String {
        return L10n.tr("Localizable", "settings.log_alert.message", String(describing: p1))
      }
      /// Sending Logs
      internal static let progressTitle = L10n.tr("Localizable", "settings.log_alert.progress_title")
      /// Logs Sent
      internal static let title = L10n.tr("Localizable", "settings.log_alert.title")
    }
    internal enum Saving {
      /// Automatically attach associated PDFs and other files when saving items
      internal static let filesMessage = L10n.tr("Localizable", "settings.saving.files_message")
      /// Save Files
      internal static let filesTitle = L10n.tr("Localizable", "settings.saving.files_title")
      /// Automatically tag items with keywords and subject headings
      internal static let tagsMessage = L10n.tr("Localizable", "settings.saving.tags_message")
      /// Save Automatic Tags
      internal static let tagsTitle = L10n.tr("Localizable", "settings.saving.tags_title")
      /// Saving
      internal static let title = L10n.tr("Localizable", "settings.saving.title")
    }
    internal enum Storage {
      /// Delete All Local Attachment Files
      internal static let deleteAll = L10n.tr("Localizable", "settings.storage.delete_all")
      /// Are you sure you want to delete all attachment files from this device?\n\nOther synced devices will not be affected.
      internal static let deleteAllQuestion = L10n.tr("Localizable", "settings.storage.delete_all_question")
      /// Are you sure you want to delete all attachment files in %@ from this device?\n\nOther synced devices will not be affected.
      internal static func deleteLibraryQuestion(_ p1: Any) -> String {
        return L10n.tr("Localizable", "settings.storage.delete_library_question", String(describing: p1))
      }
      /// %d files
      internal static func multipleFiles(_ p1: Int) -> String {
        return L10n.tr("Localizable", "settings.storage.multiple_files", p1)
      }
      /// 1 file
      internal static let oneFile = L10n.tr("Localizable", "settings.storage.one_file")
    }
    internal enum Sync {
      /// Account
      internal static let account = L10n.tr("Localizable", "settings.sync.account")
      /// Data Syncing
      internal static let dataSyncing = L10n.tr("Localizable", "settings.sync.data_syncing")
      /// Delete Account
      internal static let deleteAccount = L10n.tr("Localizable", "settings.sync.delete_account")
      /// File Syncing
      internal static let fileSyncing = L10n.tr("Localizable", "settings.sync.file_syncing")
      /// Sync attachment files in My Library using
      internal static let fileSyncingTypeMessage = L10n.tr("Localizable", "settings.sync.file_syncing_type_message")
      /// Manage Account
      internal static let manageAccount = L10n.tr("Localizable", "settings.sync.manage_account")
      /// Password
      internal static let password = L10n.tr("Localizable", "settings.sync.password")
      /// Account
      internal static let title = L10n.tr("Localizable", "settings.sync.title")
      /// Username
      internal static let username = L10n.tr("Localizable", "settings.sync.username")
      /// Verified
      internal static let verified = L10n.tr("Localizable", "settings.sync.verified")
      /// Verify Server
      internal static let verify = L10n.tr("Localizable", "settings.sync.verify")
      internal enum DirectoryNotFound {
        /// %@ does not exist.\n\nDo you want to create it now?
        internal static func message(_ p1: Any) -> String {
          return L10n.tr("Localizable", "settings.sync.directory_not_found.message", String(describing: p1))
        }
        /// Directory not found
        internal static let title = L10n.tr("Localizable", "settings.sync.directory_not_found.title")
      }
    }
  }

  internal enum Shareext {
    /// More
    internal static let collectionOther = L10n.tr("Localizable", "shareext.collection_other")
    /// Collection
    internal static let collectionTitle = L10n.tr("Localizable", "shareext.collection_title")
    /// Searching for items
    internal static let decodingAttachment = L10n.tr("Localizable", "shareext.decoding_attachment")
    /// Item
    internal static let itemTitle = L10n.tr("Localizable", "shareext.item_title")
    /// Loading Collections
    internal static let loadingCollections = L10n.tr("Localizable", "shareext.loading_collections")
    /// Save to Zotero
    internal static let save = L10n.tr("Localizable", "shareext.save")
    /// Can't sync collections
    internal static let syncError = L10n.tr("Localizable", "shareext.sync_error")
    /// Tags
    internal static let tagsTitle = L10n.tr("Localizable", "shareext.tags_title")
    internal enum Translation {
      /// Choose an item
      internal static let itemSelection = L10n.tr("Localizable", "shareext.translation.item_selection")
      /// Saving with %@
      internal static func translatingWith(_ p1: Any) -> String {
        return L10n.tr("Localizable", "shareext.translation.translating_with", String(describing: p1))
      }
    }
  }

  internal enum Sync {
    internal enum ConflictResolution {
      /// The item “%@” has been removed. Do you want to keep your changes?
      internal static func changedItemDeleted(_ p1: Any) -> String {
        return L10n.tr("Localizable", "sync.conflict_resolution.changed_item_deleted", String(describing: p1))
      }
    }
  }

  internal enum SyncToolbar {
    /// Sync failed (%@)
    internal static func aborted(_ p1: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.aborted", String(describing: p1))
    }
    /// Applying remote deletions in %@
    internal static func deletion(_ p1: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.deletion", String(describing: p1))
    }
    /// Finished sync
    internal static let finished = L10n.tr("Localizable", "sync_toolbar.finished")
    /// Syncing groups
    internal static let groups = L10n.tr("Localizable", "sync_toolbar.groups")
    /// Syncing groups (%d / %d)
    internal static func groupsWithData(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "sync_toolbar.groups_with_data", p1, p2)
    }
    /// Syncing %@
    internal static func library(_ p1: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.library", String(describing: p1))
    }
    /// Syncing %@ in %@
    internal static func object(_ p1: Any, _ p2: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.object", String(describing: p1), String(describing: p2))
    }
    /// Syncing %@ (%d / %d) in %@
    internal static func objectWithData(_ p1: Any, _ p2: Int, _ p3: Int, _ p4: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.object_with_data", String(describing: p1), p2, p3, String(describing: p4))
    }
    /// Sync starting
    internal static let starting = L10n.tr("Localizable", "sync_toolbar.starting")
    /// Uploading attachment (%d / %d)
    internal static func uploads(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "sync_toolbar.uploads", p1, p2)
    }
    /// Uploading changes (%d / %d)
    internal static func writes(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "sync_toolbar.writes", p1, p2)
    }
    internal enum Object {
      /// collections
      internal static let collections = L10n.tr("Localizable", "sync_toolbar.object.collections")
      /// groups
      internal static let groups = L10n.tr("Localizable", "sync_toolbar.object.groups")
      /// items
      internal static let items = L10n.tr("Localizable", "sync_toolbar.object.items")
      /// searches
      internal static let searches = L10n.tr("Localizable", "sync_toolbar.object.searches")
    }
  }

  internal enum TagPicker {
    /// Create Tag “%@”
    internal static func createTag(_ p1: Any) -> String {
      return L10n.tr("Localizable", "tag_picker.create_tag", String(describing: p1))
    }
    /// Tag name
    internal static let placeholder = L10n.tr("Localizable", "tag_picker.placeholder")
    /// %d selected
    internal static func title(_ p1: Int) -> String {
      return L10n.tr("Localizable", "tag_picker.title", p1)
    }
  }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

extension L10n {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg...) -> String {
    let format = BundleToken.bundle.localizedString(forKey: key, value: nil, table: table)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}

// swiftlint:disable convenience_type
private final class BundleToken {
  static let bundle = Bundle(for: BundleToken.self)
}
// swiftlint:enable convenience_type
