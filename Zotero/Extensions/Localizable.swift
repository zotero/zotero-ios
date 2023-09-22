// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal enum L10n {
  /// About Zotero
  internal static let aboutZotero = L10n.tr("Localizable", "about_zotero", fallback: "About Zotero")
  /// Abstract
  internal static let abstract = L10n.tr("Localizable", "abstract", fallback: "Abstract")
  /// Add
  internal static let add = L10n.tr("Localizable", "add", fallback: "Add")
  /// Due to a beta update, your data must be redownloaded from zotero.org.
  internal static let betaWipeMessage = L10n.tr("Localizable", "beta_wipe_message", fallback: "Due to a beta update, your data must be redownloaded from zotero.org.")
  /// Resync Required
  internal static let betaWipeTitle = L10n.tr("Localizable", "beta_wipe_title", fallback: "Resync Required")
  /// Cancel
  internal static let cancel = L10n.tr("Localizable", "cancel", fallback: "Cancel")
  /// Cancel All
  internal static let cancelAll = L10n.tr("Localizable", "cancel_all", fallback: "Cancel All")
  /// Clear
  internal static let clear = L10n.tr("Localizable", "clear", fallback: "Clear")
  /// Localizable.strings
  ///   Zotero
  /// 
  ///   Created by Michal Rentka on 21/04/2020.
  ///   Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
  internal static let close = L10n.tr("Localizable", "close", fallback: "Close")
  /// Copy
  internal static let copy = L10n.tr("Localizable", "copy", fallback: "Copy")
  /// Create
  internal static let create = L10n.tr("Localizable", "create", fallback: "Create")
  /// Creator
  internal static let creator = L10n.tr("Localizable", "creator", fallback: "Creator")
  /// Date
  internal static let date = L10n.tr("Localizable", "date", fallback: "Date")
  /// Date Added
  internal static let dateAdded = L10n.tr("Localizable", "date_added", fallback: "Date Added")
  /// Date Modified
  internal static let dateModified = L10n.tr("Localizable", "date_modified", fallback: "Date Modified")
  /// st,nd,rd,th
  internal static let daySuffixes = L10n.tr("Localizable", "day_suffixes", fallback: "st,nd,rd,th")
  /// Delete
  internal static let delete = L10n.tr("Localizable", "delete", fallback: "Delete")
  /// Done
  internal static let done = L10n.tr("Localizable", "done", fallback: "Done")
  /// Edit
  internal static let edit = L10n.tr("Localizable", "edit", fallback: "Edit")
  /// Error
  internal static let error = L10n.tr("Localizable", "error", fallback: "Error")
  /// Item Type
  internal static let itemType = L10n.tr("Localizable", "item_type", fallback: "Item Type")
  /// Keep
  internal static let keep = L10n.tr("Localizable", "keep", fallback: "Keep")
  /// Last Updated
  internal static let lastUpdated = L10n.tr("Localizable", "last_updated", fallback: "Last Updated")
  /// App failed to log in. Please log in again and report Debug ID %@ in the Zotero Forums.
  internal static func loginDebug(_ p1: Any) -> String {
    return L10n.tr("Localizable", "login_debug", String(describing: p1), fallback: "App failed to log in. Please log in again and report Debug ID %@ in the Zotero Forums.")
  }
  /// Look Up
  internal static let lookUp = L10n.tr("Localizable", "look_up", fallback: "Look Up")
  /// App failed to initialize and can’t function properly. Please report Debug ID %@ in the Zotero Forums.
  internal static func migrationDebug(_ p1: Any) -> String {
    return L10n.tr("Localizable", "migration_debug", String(describing: p1), fallback: "App failed to initialize and can’t function properly. Please report Debug ID %@ in the Zotero Forums.")
  }
  /// More Information
  internal static let moreInformation = L10n.tr("Localizable", "more_information", fallback: "More Information")
  /// Move to Trash
  internal static let moveToTrash = L10n.tr("Localizable", "move_to_trash", fallback: "Move to Trash")
  /// Name
  internal static let name = L10n.tr("Localizable", "name", fallback: "Name")
  /// No
  internal static let no = L10n.tr("Localizable", "no", fallback: "No")
  /// Not Found
  internal static let notFound = L10n.tr("Localizable", "not_found", fallback: "Not Found")
  /// OK
  internal static let ok = L10n.tr("Localizable", "ok", fallback: "OK")
  /// Page
  internal static let page = L10n.tr("Localizable", "page", fallback: "Page")
  /// Privacy Policy
  internal static let privacyPolicy = L10n.tr("Localizable", "privacy_policy", fallback: "Privacy Policy")
  /// Publication Title
  internal static let publicationTitle = L10n.tr("Localizable", "publication_title", fallback: "Publication Title")
  /// Publisher
  internal static let publisher = L10n.tr("Localizable", "publisher", fallback: "Publisher")
  /// Recents
  internal static let recent = L10n.tr("Localizable", "recent", fallback: "Recents")
  /// Remove
  internal static let remove = L10n.tr("Localizable", "remove", fallback: "Remove")
  /// Report
  internal static let report = L10n.tr("Localizable", "report", fallback: "Report")
  /// Restore
  internal static let restore = L10n.tr("Localizable", "restore", fallback: "Restore")
  /// Retry
  internal static let retry = L10n.tr("Localizable", "retry", fallback: "Retry")
  /// Save
  internal static let save = L10n.tr("Localizable", "save", fallback: "Save")
  /// Scan Text
  internal static let scanText = L10n.tr("Localizable", "scan_text", fallback: "Scan Text")
  /// Select
  internal static let select = L10n.tr("Localizable", "select", fallback: "Select")
  /// Share
  internal static let share = L10n.tr("Localizable", "share", fallback: "Share")
  /// Size
  internal static let size = L10n.tr("Localizable", "size", fallback: "Size")
  /// Support and Feedback
  internal static let supportFeedback = L10n.tr("Localizable", "support_feedback", fallback: "Support and Feedback")
  /// Title
  internal static let title = L10n.tr("Localizable", "title", fallback: "Title")
  /// Total
  internal static let total = L10n.tr("Localizable", "total", fallback: "Total")
  /// Unknown
  internal static let unknown = L10n.tr("Localizable", "unknown", fallback: "Unknown")
  /// Warning
  internal static let warning = L10n.tr("Localizable", "warning", fallback: "Warning")
  /// Year
  internal static let year = L10n.tr("Localizable", "year", fallback: "Year")
  /// Yes
  internal static let yes = L10n.tr("Localizable", "yes", fallback: "Yes")
  internal enum Accessibility {
    /// Archived
    internal static let archived = L10n.tr("Localizable", "accessibility.archived", fallback: "Archived")
    /// Locked
    internal static let locked = L10n.tr("Localizable", "accessibility.locked", fallback: "Locked")
    /// Untitled
    internal static let untitled = L10n.tr("Localizable", "accessibility.untitled", fallback: "Untitled")
    internal enum Collections {
      /// Collapse
      internal static let collapse = L10n.tr("Localizable", "accessibility.collections.collapse", fallback: "Collapse")
      /// Create collection
      internal static let createCollection = L10n.tr("Localizable", "accessibility.collections.create_collection", fallback: "Create collection")
      /// Expand
      internal static let expand = L10n.tr("Localizable", "accessibility.collections.expand", fallback: "Expand")
      /// Expand all collections
      internal static let expandAllCollections = L10n.tr("Localizable", "accessibility.collections.expand_all_collections", fallback: "Expand all collections")
      /// items
      internal static let items = L10n.tr("Localizable", "accessibility.collections.items", fallback: "items")
      /// Search collections
      internal static let searchCollections = L10n.tr("Localizable", "accessibility.collections.search_collections", fallback: "Search collections")
    }
    internal enum ItemDetail {
      /// Double tap to download and open
      internal static let downloadAndOpen = L10n.tr("Localizable", "accessibility.item_detail.download_and_open", fallback: "Double tap to download and open")
      /// Double tap to open
      internal static let `open` = L10n.tr("Localizable", "accessibility.item_detail.open", fallback: "Double tap to open")
    }
    internal enum Items {
      /// Add selected items to collection
      internal static let addToCollection = L10n.tr("Localizable", "accessibility.items.add_to_collection", fallback: "Add selected items to collection")
      /// Delete selected items
      internal static let delete = L10n.tr("Localizable", "accessibility.items.delete", fallback: "Delete selected items")
      /// Deselect All Items
      internal static let deselectAllItems = L10n.tr("Localizable", "accessibility.items.deselect_all_items", fallback: "Deselect All Items")
      /// Duplicate selected item
      internal static let duplicate = L10n.tr("Localizable", "accessibility.items.duplicate", fallback: "Duplicate selected item")
      /// Filter items
      internal static let filterItems = L10n.tr("Localizable", "accessibility.items.filter_items", fallback: "Filter items")
      /// Open item info
      internal static let openItem = L10n.tr("Localizable", "accessibility.items.open_item", fallback: "Open item info")
      /// Remove selected items from collection
      internal static let removeFromCollection = L10n.tr("Localizable", "accessibility.items.remove_from_collection", fallback: "Remove selected items from collection")
      /// Restore selected items
      internal static let restore = L10n.tr("Localizable", "accessibility.items.restore", fallback: "Restore selected items")
      /// Select All Items
      internal static let selectAllItems = L10n.tr("Localizable", "accessibility.items.select_all_items", fallback: "Select All Items")
      /// Select items
      internal static let selectItems = L10n.tr("Localizable", "accessibility.items.select_items", fallback: "Select items")
      /// Share selected items
      internal static let share = L10n.tr("Localizable", "accessibility.items.share", fallback: "Share selected items")
      /// Sort items
      internal static let sortItems = L10n.tr("Localizable", "accessibility.items.sort_items", fallback: "Sort items")
      /// Move selected items to trash
      internal static let trash = L10n.tr("Localizable", "accessibility.items.trash", fallback: "Move selected items to trash")
    }
    internal enum Pdf {
      /// Double tap to select and edit
      internal static let annotationHint = L10n.tr("Localizable", "accessibility.pdf.annotation_hint", fallback: "Double tap to select and edit")
      /// Author
      internal static let author = L10n.tr("Localizable", "accessibility.pdf.author", fallback: "Author")
      /// Color picker
      internal static let colorPicker = L10n.tr("Localizable", "accessibility.pdf.color_picker", fallback: "Color picker")
      /// Comment
      internal static let comment = L10n.tr("Localizable", "accessibility.pdf.comment", fallback: "Comment")
      /// Edit annotation
      internal static let editAnnotation = L10n.tr("Localizable", "accessibility.pdf.edit_annotation", fallback: "Edit annotation")
      /// Eraser
      internal static let eraserAnnotation = L10n.tr("Localizable", "accessibility.pdf.eraser_annotation", fallback: "Eraser")
      /// Eraser
      internal static let eraserAnnotationTool = L10n.tr("Localizable", "accessibility.pdf.eraser_annotation_tool", fallback: "Eraser")
      /// Export pdf
      internal static let export = L10n.tr("Localizable", "accessibility.pdf.export", fallback: "Export pdf")
      /// Highlight annotation
      internal static let highlightAnnotation = L10n.tr("Localizable", "accessibility.pdf.highlight_annotation", fallback: "Highlight annotation")
      /// Create highlight annotation
      internal static let highlightAnnotationTool = L10n.tr("Localizable", "accessibility.pdf.highlight_annotation_tool", fallback: "Create highlight annotation")
      /// Highlighted text
      internal static let highlightedText = L10n.tr("Localizable", "accessibility.pdf.highlighted_text", fallback: "Highlighted text")
      /// Image annotation
      internal static let imageAnnotation = L10n.tr("Localizable", "accessibility.pdf.image_annotation", fallback: "Image annotation")
      /// Create image annotation
      internal static let imageAnnotationTool = L10n.tr("Localizable", "accessibility.pdf.image_annotation_tool", fallback: "Create image annotation")
      /// Ink annotation
      internal static let inkAnnotation = L10n.tr("Localizable", "accessibility.pdf.ink_annotation", fallback: "Ink annotation")
      /// Create ink annotation
      internal static let inkAnnotationTool = L10n.tr("Localizable", "accessibility.pdf.ink_annotation_tool", fallback: "Create ink annotation")
      /// Note annotation
      internal static let noteAnnotation = L10n.tr("Localizable", "accessibility.pdf.note_annotation", fallback: "Note annotation")
      /// Create note annotation
      internal static let noteAnnotationTool = L10n.tr("Localizable", "accessibility.pdf.note_annotation_tool", fallback: "Create note annotation")
      /// Open text reader
      internal static let openReader = L10n.tr("Localizable", "accessibility.pdf.open_reader", fallback: "Open text reader")
      /// Redo
      internal static let redo = L10n.tr("Localizable", "accessibility.pdf.redo", fallback: "Redo")
      /// Search PDF
      internal static let searchPdf = L10n.tr("Localizable", "accessibility.pdf.search_pdf", fallback: "Search PDF")
      /// Selected
      internal static let selected = L10n.tr("Localizable", "accessibility.pdf.selected", fallback: "Selected")
      /// Settings
      internal static let settings = L10n.tr("Localizable", "accessibility.pdf.settings", fallback: "Settings")
      /// Share annotation
      internal static let shareAnnotation = L10n.tr("Localizable", "accessibility.pdf.share_annotation", fallback: "Share annotation")
      /// Share annotation image
      internal static let shareAnnotationImage = L10n.tr("Localizable", "accessibility.pdf.share_annotation_image", fallback: "Share annotation image")
      /// Show more
      internal static let showMoreTools = L10n.tr("Localizable", "accessibility.pdf.show_more_tools", fallback: "Show more")
      /// Close sidebar
      internal static let sidebarClose = L10n.tr("Localizable", "accessibility.pdf.sidebar_close", fallback: "Close sidebar")
      /// Open sidebar
      internal static let sidebarOpen = L10n.tr("Localizable", "accessibility.pdf.sidebar_open", fallback: "Open sidebar")
      /// Tags
      internal static let tags = L10n.tr("Localizable", "accessibility.pdf.tags", fallback: "Tags")
      /// Double tap to edit tags
      internal static let tagsHint = L10n.tr("Localizable", "accessibility.pdf.tags_hint", fallback: "Double tap to edit tags")
      /// Toggle annotation toolbar
      internal static let toggleAnnotationToolbar = L10n.tr("Localizable", "accessibility.pdf.toggle_annotation_toolbar", fallback: "Toggle annotation toolbar")
      /// Undo
      internal static let undo = L10n.tr("Localizable", "accessibility.pdf.undo", fallback: "Undo")
    }
  }
  internal enum Citation {
    /// Bibliography
    internal static let bibliography = L10n.tr("Localizable", "citation.bibliography", fallback: "Bibliography")
    /// Citations
    internal static let citations = L10n.tr("Localizable", "citation.citations", fallback: "Citations")
    /// Copy to Clipboard
    internal static let copy = L10n.tr("Localizable", "citation.copy", fallback: "Copy to Clipboard")
    /// Copy Bibliography
    internal static let copyBibliography = L10n.tr("Localizable", "citation.copy_bibliography", fallback: "Copy Bibliography")
    /// Copy Citation
    internal static let copyCitation = L10n.tr("Localizable", "citation.copy_citation", fallback: "Copy Citation")
    /// Language
    internal static let language = L10n.tr("Localizable", "citation.language", fallback: "Language")
    /// Number
    internal static let locatorPlaceholder = L10n.tr("Localizable", "citation.locator_placeholder", fallback: "Number")
    /// Notes
    internal static let notes = L10n.tr("Localizable", "citation.notes", fallback: "Notes")
    /// Omit Author
    internal static let omitAuthor = L10n.tr("Localizable", "citation.omit_author", fallback: "Omit Author")
    /// Output Method
    internal static let outputMethod = L10n.tr("Localizable", "citation.output_method", fallback: "Output Method")
    /// Output Mode
    internal static let outputMode = L10n.tr("Localizable", "citation.output_mode", fallback: "Output Mode")
    /// Preview:
    internal static let preview = L10n.tr("Localizable", "citation.preview", fallback: "Preview:")
    /// Save as HTML
    internal static let saveHtml = L10n.tr("Localizable", "citation.save_html", fallback: "Save as HTML")
    /// Style
    internal static let style = L10n.tr("Localizable", "citation.style", fallback: "Style")
    /// Citation Preview
    internal static let title = L10n.tr("Localizable", "citation.title", fallback: "Citation Preview")
    internal enum Locator {
      /// Book
      internal static let book = L10n.tr("Localizable", "citation.locator.book", fallback: "Book")
      /// Chapter
      internal static let chapter = L10n.tr("Localizable", "citation.locator.chapter", fallback: "Chapter")
      /// Column
      internal static let column = L10n.tr("Localizable", "citation.locator.column", fallback: "Column")
      /// Figure
      internal static let figure = L10n.tr("Localizable", "citation.locator.figure", fallback: "Figure")
      /// Folio
      internal static let folio = L10n.tr("Localizable", "citation.locator.folio", fallback: "Folio")
      /// Issue
      internal static let issue = L10n.tr("Localizable", "citation.locator.issue", fallback: "Issue")
      /// Line
      internal static let line = L10n.tr("Localizable", "citation.locator.line", fallback: "Line")
      /// Note
      internal static let note = L10n.tr("Localizable", "citation.locator.note", fallback: "Note")
      /// Opus
      internal static let opus = L10n.tr("Localizable", "citation.locator.opus", fallback: "Opus")
      /// Page
      internal static let page = L10n.tr("Localizable", "citation.locator.page", fallback: "Page")
      /// Paragraph
      internal static let paragraph = L10n.tr("Localizable", "citation.locator.paragraph", fallback: "Paragraph")
      /// Part
      internal static let part = L10n.tr("Localizable", "citation.locator.part", fallback: "Part")
      /// Section
      internal static let section = L10n.tr("Localizable", "citation.locator.section", fallback: "Section")
      /// Sub verbo
      internal static let subVerbo = L10n.tr("Localizable", "citation.locator.sub verbo", fallback: "Sub verbo")
      /// Verse
      internal static let verse = L10n.tr("Localizable", "citation.locator.verse", fallback: "Verse")
      /// Volume
      internal static let volume = L10n.tr("Localizable", "citation.locator.volume", fallback: "Volume")
    }
  }
  internal enum Collections {
    /// All Items
    internal static let allItems = L10n.tr("Localizable", "collections.all_items", fallback: "All Items")
    /// Collapse All
    internal static let collapseAll = L10n.tr("Localizable", "collections.collapse_all", fallback: "Collapse All")
    /// Create Bibliography from Collection
    internal static let createBibliography = L10n.tr("Localizable", "collections.create_bibliography", fallback: "Create Bibliography from Collection")
    /// Create Collection
    internal static let createTitle = L10n.tr("Localizable", "collections.create_title", fallback: "Create Collection")
    /// Delete Collection
    internal static let delete = L10n.tr("Localizable", "collections.delete", fallback: "Delete Collection")
    /// Delete Collection and Items
    internal static let deleteWithItems = L10n.tr("Localizable", "collections.delete_with_items", fallback: "Delete Collection and Items")
    /// Download Attachments
    internal static let downloadAttachments = L10n.tr("Localizable", "collections.download_attachments", fallback: "Download Attachments")
    /// Edit Collection
    internal static let editTitle = L10n.tr("Localizable", "collections.edit_title", fallback: "Edit Collection")
    /// Empty Trash
    internal static let emptyTrash = L10n.tr("Localizable", "collections.empty_trash", fallback: "Empty Trash")
    /// Expand All
    internal static let expandAll = L10n.tr("Localizable", "collections.expand_all", fallback: "Expand All")
    /// My Publications
    internal static let myPublications = L10n.tr("Localizable", "collections.my_publications", fallback: "My Publications")
    /// New Subcollection
    internal static let newSubcollection = L10n.tr("Localizable", "collections.new_subcollection", fallback: "New Subcollection")
    /// Choose Parent
    internal static let pickerTitle = L10n.tr("Localizable", "collections.picker_title", fallback: "Choose Parent")
    /// Find Collection
    internal static let searchTitle = L10n.tr("Localizable", "collections.search_title", fallback: "Find Collection")
    /// Trash
    internal static let trash = L10n.tr("Localizable", "collections.trash", fallback: "Trash")
    /// Unfiled Items
    internal static let unfiled = L10n.tr("Localizable", "collections.unfiled", fallback: "Unfiled Items")
  }
  internal enum CreatorEditor {
    /// Creator Type
    internal static let creator = L10n.tr("Localizable", "creator_editor.creator", fallback: "Creator Type")
    /// Do you really want to delete this creator?
    internal static let deleteConfirmation = L10n.tr("Localizable", "creator_editor.delete_confirmation", fallback: "Do you really want to delete this creator?")
    /// First Name
    internal static let firstName = L10n.tr("Localizable", "creator_editor.first_name", fallback: "First Name")
    /// Last Name
    internal static let lastName = L10n.tr("Localizable", "creator_editor.last_name", fallback: "Last Name")
    /// Switch to two fields
    internal static let switchToDual = L10n.tr("Localizable", "creator_editor.switch_to_dual", fallback: "Switch to two fields")
    /// Switch to single field
    internal static let switchToSingle = L10n.tr("Localizable", "creator_editor.switch_to_single", fallback: "Switch to single field")
  }
  internal enum Errors {
    /// Failed API response: %@
    internal static func api(_ p1: Any) -> String {
      return L10n.tr("Localizable", "errors.api", String(describing: p1), fallback: "Failed API response: %@")
    }
    /// Could not generate citation preview
    internal static let citationPreview = L10n.tr("Localizable", "errors.citation_preview", fallback: "Could not generate citation preview")
    /// Could not connect to database. The device storage might be full.
    internal static let db = L10n.tr("Localizable", "errors.db", fallback: "Could not connect to database. The device storage might be full.")
    /// Error creating database. Please try logging in again.
    internal static let dbFailure = L10n.tr("Localizable", "errors.db_failure", fallback: "Error creating database. Please try logging in again.")
    /// Could not parse some data. Other data will continue to sync.
    internal static let parsing = L10n.tr("Localizable", "errors.parsing", fallback: "Could not parse some data. Other data will continue to sync.")
    /// Some data in My Library could not be downloaded. It may have been saved with a newer version of Zotero.
    /// 
    /// Other data will continue to sync.
    internal static let schema = L10n.tr("Localizable", "errors.schema", fallback: "Some data in My Library could not be downloaded. It may have been saved with a newer version of Zotero.\n\nOther data will continue to sync.")
    /// Unknown error
    internal static let unknown = L10n.tr("Localizable", "errors.unknown", fallback: "Unknown error")
    /// A remote change was made during the sync
    internal static let versionMismatch = L10n.tr("Localizable", "errors.versionMismatch", fallback: "A remote change was made during the sync")
    internal enum Attachments {
      /// The attached file could not be found.
      internal static let cantOpenAttachment = L10n.tr("Localizable", "errors.attachments.cant_open_attachment", fallback: "The attached file could not be found.")
      /// Unable to unzip snapshot
      internal static let cantUnzipSnapshot = L10n.tr("Localizable", "errors.attachments.cant_unzip_snapshot", fallback: "Unable to unzip snapshot")
      /// Linked files are not supported on iOS. You can open them using the Zotero desktop app.
      internal static let incompatibleAttachment = L10n.tr("Localizable", "errors.attachments.incompatible_attachment", fallback: "Linked files are not supported on iOS. You can open them using the Zotero desktop app.")
      /// Please check that the file has synced on the device where it was added.
      internal static let missingAdditional = L10n.tr("Localizable", "errors.attachments.missing_additional", fallback: "Please check that the file has synced on the device where it was added.")
      /// The attached file is not available on the WebDAV server.
      internal static let missingWebdav = L10n.tr("Localizable", "errors.attachments.missing_webdav", fallback: "The attached file is not available on the WebDAV server.")
      /// The attached file is not available in the online library.
      internal static let missingZotero = L10n.tr("Localizable", "errors.attachments.missing_zotero", fallback: "The attached file is not available in the online library.")
    }
    internal enum Citation {
      /// Could not generate bibliography.
      internal static let generateBibliography = L10n.tr("Localizable", "errors.citation.generate_bibliography", fallback: "Could not generate bibliography.")
      /// Could not generate citation.
      internal static let generateCitation = L10n.tr("Localizable", "errors.citation.generate_citation", fallback: "Could not generate citation.")
      /// Invalid item types selected.
      internal static let invalidTypes = L10n.tr("Localizable", "errors.citation.invalid_types", fallback: "Invalid item types selected.")
      /// No citation style selected. Go to Settings → Quick Copy and select a new style.
      internal static let missingStyle = L10n.tr("Localizable", "errors.citation.missing_style", fallback: "No citation style selected. Go to Settings → Quick Copy and select a new style.")
      /// Open Settings
      internal static let openSettings = L10n.tr("Localizable", "errors.citation.open_settings", fallback: "Open Settings")
    }
    internal enum Collections {
      /// Could not load items for bibliography.
      internal static let bibliographyFailed = L10n.tr("Localizable", "errors.collections.bibliography_failed", fallback: "Could not load items for bibliography.")
      /// Please enter a collection name
      internal static let emptyName = L10n.tr("Localizable", "errors.collections.empty_name", fallback: "Please enter a collection name")
      /// Unable to save collection
      internal static let saveFailed = L10n.tr("Localizable", "errors.collections.save_failed", fallback: "Unable to save collection")
    }
    internal enum ItemDetail {
      /// Could not create attachments.
      internal static let cantCreateAttachments = L10n.tr("Localizable", "errors.item_detail.cant_create_attachments", fallback: "Could not create attachments.")
      /// Could not create attachments: %@
      internal static func cantCreateAttachmentsWithNames(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.item_detail.cant_create_attachments_with_names", String(describing: p1), fallback: "Could not create attachments: %@")
      }
      /// Could not load data. Please try again.
      internal static let cantLoadData = L10n.tr("Localizable", "errors.item_detail.cant_load_data", fallback: "Could not load data. Please try again.")
      /// Could not save changes.
      internal static let cantSaveChanges = L10n.tr("Localizable", "errors.item_detail.cant_save_changes", fallback: "Could not save changes.")
      /// Could not save note.
      internal static let cantSaveNote = L10n.tr("Localizable", "errors.item_detail.cant_save_note", fallback: "Could not save note.")
      /// Could not save tags.
      internal static let cantSaveTags = L10n.tr("Localizable", "errors.item_detail.cant_save_tags", fallback: "Could not save tags.")
      /// Could not move item to trash.
      internal static let cantTrashItem = L10n.tr("Localizable", "errors.item_detail.cant_trash_item", fallback: "Could not move item to trash.")
      /// Are you sure you want to change the item type?
      /// 
      /// The following fields will be lost:
      /// 
      /// %@
      internal static func droppedFieldsMessage(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.item_detail.dropped_fields_message", String(describing: p1), fallback: "Are you sure you want to change the item type?\n\nThe following fields will be lost:\n\n%@")
      }
      /// Change Item Type
      internal static let droppedFieldsTitle = L10n.tr("Localizable", "errors.item_detail.dropped_fields_title", fallback: "Change Item Type")
      /// Type "%@" not supported.
      internal static func unsupportedType(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.item_detail.unsupported_type", String(describing: p1), fallback: "Type \"%@\" not supported.")
      }
    }
    internal enum Items {
      /// Could not add attachment.
      internal static let addAttachment = L10n.tr("Localizable", "errors.items.add_attachment", fallback: "Could not add attachment.")
      /// Some attachments were not added: %@.
      internal static func addSomeAttachments(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.items.add_some_attachments", String(describing: p1), fallback: "Some attachments were not added: %@.")
      }
      /// Could not add item to collection.
      internal static let addToCollection = L10n.tr("Localizable", "errors.items.add_to_collection", fallback: "Could not add item to collection.")
      /// Could not remove item.
      internal static let deletion = L10n.tr("Localizable", "errors.items.deletion", fallback: "Could not remove item.")
      /// Could not remove item from collection.
      internal static let deletionFromCollection = L10n.tr("Localizable", "errors.items.deletion_from_collection", fallback: "Could not remove item from collection.")
      /// Could not generate bibliography
      internal static let generatingBib = L10n.tr("Localizable", "errors.items.generating_bib", fallback: "Could not generate bibliography")
      /// Could not load item to duplicate.
      internal static let loadDuplication = L10n.tr("Localizable", "errors.items.load_duplication", fallback: "Could not load item to duplicate.")
      /// Could not load items.
      internal static let loading = L10n.tr("Localizable", "errors.items.loading", fallback: "Could not load items.")
      /// Could not move item.
      internal static let moveItem = L10n.tr("Localizable", "errors.items.move_item", fallback: "Could not move item.")
      /// Could not save note.
      internal static let saveNote = L10n.tr("Localizable", "errors.items.save_note", fallback: "Could not save note.")
    }
    internal enum Libraries {
      /// Unable to load libraries
      internal static let cantLoad = L10n.tr("Localizable", "errors.libraries.cantLoad", fallback: "Unable to load libraries")
    }
    internal enum Logging {
      /// Log files could not be found
      internal static let contentReading = L10n.tr("Localizable", "errors.logging.content_reading", fallback: "Log files could not be found")
      /// No debug output occurred during logging
      internal static let noLogsRecorded = L10n.tr("Localizable", "errors.logging.no_logs_recorded", fallback: "No debug output occurred during logging")
      /// Unexpected response from server
      internal static let responseParsing = L10n.tr("Localizable", "errors.logging.response_parsing", fallback: "Unexpected response from server")
      /// Unable to start debug logging
      internal static let start = L10n.tr("Localizable", "errors.logging.start", fallback: "Unable to start debug logging")
      /// Debugging Error
      internal static let title = L10n.tr("Localizable", "errors.logging.title", fallback: "Debugging Error")
      /// Could not upload logs. Please try again.
      internal static let upload = L10n.tr("Localizable", "errors.logging.upload", fallback: "Could not upload logs. Please try again.")
    }
    internal enum Login {
      /// Invalid username or password
      internal static let invalidCredentials = L10n.tr("Localizable", "errors.login.invalid_credentials", fallback: "Invalid username or password")
      /// Invalid password
      internal static let invalidPassword = L10n.tr("Localizable", "errors.login.invalid_password", fallback: "Invalid password")
      /// Invalid username
      internal static let invalidUsername = L10n.tr("Localizable", "errors.login.invalid_username", fallback: "Invalid username")
    }
    internal enum Lookup {
      /// Zotero could not find any identifiers in your input. Please verify your input and try again.
      internal static let noIdentifiersAndNoLookupData = L10n.tr("Localizable", "errors.lookup.no_identifiers_and_no_lookup_data", fallback: "Zotero could not find any identifiers in your input. Please verify your input and try again.")
      /// Zotero could not find any new identifiers in your input, or they are already being added. Please verify your input and try again.
      internal static let noIdentifiersWithLookupData = L10n.tr("Localizable", "errors.lookup.no_identifiers_with_lookup_data", fallback: "Zotero could not find any new identifiers in your input, or they are already being added. Please verify your input and try again.")
    }
    internal enum Pdf {
      /// Can't add annotations.
      internal static let cantAddAnnotations = L10n.tr("Localizable", "errors.pdf.cant_add_annotations", fallback: "Can't add annotations.")
      /// Can't delete annotations.
      internal static let cantDeleteAnnotations = L10n.tr("Localizable", "errors.pdf.cant_delete_annotations", fallback: "Can't delete annotations.")
      /// Can't update annotation.
      internal static let cantUpdateAnnotation = L10n.tr("Localizable", "errors.pdf.cant_update_annotation", fallback: "Can't update annotation.")
      /// The combined annotation would be too large.
      internal static let mergeTooBig = L10n.tr("Localizable", "errors.pdf.merge_too_big", fallback: "The combined annotation would be too large.")
      /// Unable to merge annotations
      internal static let mergeTooBigTitle = L10n.tr("Localizable", "errors.pdf.merge_too_big_title", fallback: "Unable to merge annotations")
      /// Incorrect format of page stored for this document.
      internal static let pageIndexNotInt = L10n.tr("Localizable", "errors.pdf.page_index_not_int", fallback: "Incorrect format of page stored for this document.")
    }
    internal enum Settings {
      /// Could not collect storage data
      internal static let storage = L10n.tr("Localizable", "errors.settings.storage", fallback: "Could not collect storage data")
      internal enum Webdav {
        /// A potential problem was found with your WebDAV server.
        /// 
        /// An uploaded file was not immediately available for download. There may be a short delay between when you upload files and when they become available, particularly if you are using a cloud storage service.
        /// 
        /// If Zotero file syncing appears to work normally, you can ignore this message. If you have trouble, please post to the Zotero Forums.
        internal static let fileMissingAfterUpload = L10n.tr("Localizable", "errors.settings.webdav.file_missing_after_upload", fallback: "A potential problem was found with your WebDAV server.\n\nAn uploaded file was not immediately available for download. There may be a short delay between when you upload files and when they become available, particularly if you are using a cloud storage service.\n\nIf Zotero file syncing appears to work normally, you can ignore this message. If you have trouble, please post to the Zotero Forums.")
        /// You don’t have permission to access the specified folder on the WebDAV server.
        internal static let forbidden = L10n.tr("Localizable", "errors.settings.webdav.forbidden", fallback: "You don’t have permission to access the specified folder on the WebDAV server.")
        /// Could not connect to WebDAV server
        internal static let hostNotFound = L10n.tr("Localizable", "errors.settings.webdav.host_not_found", fallback: "Could not connect to WebDAV server")
        /// Unable to connect to the network. Please try again.
        internal static let internetConnection = L10n.tr("Localizable", "errors.settings.webdav.internet_connection", fallback: "Unable to connect to the network. Please try again.")
        /// WebDAV verification error
        internal static let invalidUrl = L10n.tr("Localizable", "errors.settings.webdav.invalid_url", fallback: "WebDAV verification error")
        /// WebDAV verification error
        internal static let noPassword = L10n.tr("Localizable", "errors.settings.webdav.no_password", fallback: "WebDAV verification error")
        /// WebDAV verification error
        internal static let noUrl = L10n.tr("Localizable", "errors.settings.webdav.no_url", fallback: "WebDAV verification error")
        /// WebDAV verification error
        internal static let noUsername = L10n.tr("Localizable", "errors.settings.webdav.no_username", fallback: "WebDAV verification error")
        /// WebDAV verification error
        internal static let nonExistentFileNotMissing = L10n.tr("Localizable", "errors.settings.webdav.non_existent_file_not_missing", fallback: "WebDAV verification error")
        /// Not a valid WebDAV URL
        internal static let notDav = L10n.tr("Localizable", "errors.settings.webdav.not_dav", fallback: "Not a valid WebDAV URL")
        /// WebDAV verification error
        internal static let parentDirNotFound = L10n.tr("Localizable", "errors.settings.webdav.parent_dir_not_found", fallback: "WebDAV verification error")
        /// The WebDAV server did not accept the username and password you entered.
        internal static let unauthorized = L10n.tr("Localizable", "errors.settings.webdav.unauthorized", fallback: "The WebDAV server did not accept the username and password you entered.")
        /// WebDAV verification error
        internal static let zoteroDirNotFound = L10n.tr("Localizable", "errors.settings.webdav.zotero_dir_not_found", fallback: "WebDAV verification error")
      }
    }
    internal enum Shareext {
      /// Error uploading item. The item was saved to your local library.
      internal static let apiError = L10n.tr("Localizable", "errors.shareext.api_error", fallback: "Error uploading item. The item was saved to your local library.")
      /// Background uploader not initialized
      internal static let backgroundUploaderFailure = L10n.tr("Localizable", "errors.shareext.background_uploader_failure", fallback: "Background uploader not initialized")
      /// Failed to load data. Please try again.
      internal static let cantLoadData = L10n.tr("Localizable", "errors.shareext.cant_load_data", fallback: "Failed to load data. Please try again.")
      /// An error occurred. Please open the Zotero app, sync, and try again.
      internal static let cantLoadSchema = L10n.tr("Localizable", "errors.shareext.cant_load_schema", fallback: "An error occurred. Please open the Zotero app, sync, and try again.")
      /// Could not download file
      internal static let downloadFailed = L10n.tr("Localizable", "errors.shareext.download_failed", fallback: "Could not download file")
      /// You can still save this page as a webpage item.
      internal static let failedAdditional = L10n.tr("Localizable", "errors.shareext.failed_additional", fallback: "You can still save this page as a webpage item.")
      /// Unable to save PDF
      internal static let fileNotPdf = L10n.tr("Localizable", "errors.shareext.file_not_pdf", fallback: "Unable to save PDF")
      /// The group “%@” has reached its Zotero Storage quota, and the file could not be uploaded. The group owner can view their account settings for additional storage options.
      /// 
      /// The file was saved to the local library.
      internal static func groupQuotaReached(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.shareext.group_quota_reached", String(describing: p1), fallback: "The group “%@” has reached its Zotero Storage quota, and the file could not be uploaded. The group owner can view their account settings for additional storage options.\n\nThe file was saved to the local library.")
      }
      /// No data returned
      internal static let incompatibleItem = L10n.tr("Localizable", "errors.shareext.incompatible_item", fallback: "No data returned")
      /// No items found on page
      internal static let itemsNotFound = L10n.tr("Localizable", "errors.shareext.items_not_found", fallback: "No items found on page")
      /// JS call failed
      internal static let javascriptFailed = L10n.tr("Localizable", "errors.shareext.javascript_failed", fallback: "JS call failed")
      /// Please log into the app before using this extension.
      internal static let loggedOut = L10n.tr("Localizable", "errors.shareext.logged_out", fallback: "Please log into the app before using this extension.")
      /// Translator missing
      internal static let missingBaseFiles = L10n.tr("Localizable", "errors.shareext.missing_base_files", fallback: "Translator missing")
      /// Could not find file to upload
      internal static let missingFile = L10n.tr("Localizable", "errors.shareext.missing_file", fallback: "Could not find file to upload")
      /// Error parsing translator response
      internal static let parsingError = L10n.tr("Localizable", "errors.shareext.parsing_error", fallback: "Error parsing translator response")
      /// You have reached your Zotero Storage quota, and the file could not be uploaded. See your account settings for additional storage options.
      /// 
      /// The file was saved to your local library.
      internal static let personalQuotaReached = L10n.tr("Localizable", "errors.shareext.personal_quota_reached", fallback: "You have reached your Zotero Storage quota, and the file could not be uploaded. See your account settings for additional storage options.\n\nThe file was saved to your local library.")
      /// An error occurred. Please try again.
      internal static let responseMissingData = L10n.tr("Localizable", "errors.shareext.response_missing_data", fallback: "An error occurred. Please try again.")
      /// Some data could not be downloaded. It may have been saved with a newer version of Zotero.
      internal static let schemaError = L10n.tr("Localizable", "errors.shareext.schema_error", fallback: "Some data could not be downloaded. It may have been saved with a newer version of Zotero.")
      /// Saving failed
      internal static let translationFailed = L10n.tr("Localizable", "errors.shareext.translation_failed", fallback: "Saving failed")
      /// An unknown error occurred.
      internal static let unknown = L10n.tr("Localizable", "errors.shareext.unknown", fallback: "An unknown error occurred.")
      /// Error uploading attachment to WebDAV server
      internal static let webdavError = L10n.tr("Localizable", "errors.shareext.webdav_error", fallback: "Error uploading attachment to WebDAV server")
      /// WebDAV verification error
      internal static let webdavNotVerified = L10n.tr("Localizable", "errors.shareext.webdav_not_verified", fallback: "WebDAV verification error")
    }
    internal enum Styles {
      /// Could not add style “%@”.
      internal static func addition(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.styles.addition", String(describing: p1), fallback: "Could not add style “%@”.")
      }
      /// Could not delete style “%@”.
      internal static func deletion(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.styles.deletion", String(describing: p1), fallback: "Could not delete style “%@”.")
      }
      /// Could not load styles.
      internal static let loading = L10n.tr("Localizable", "errors.styles.loading", fallback: "Could not load styles.")
    }
    internal enum StylesSearch {
      /// Could not load styles. Do you want to try again?
      internal static let loading = L10n.tr("Localizable", "errors.styles_search.loading", fallback: "Could not load styles. Do you want to try again?")
    }
    internal enum Sync {
      /// You no longer have file-editing access for the group ‘%@’, and files you’ve changed locally cannot be uploaded. If you continue, all group files will be reset to their state on %@.
      /// 
      /// If you would like a chance to copy modified files elsewhere or to request file-editing access from a group administrator, you can skip syncing of the group now.
      internal static func fileWriteDenied(_ p1: Any, _ p2: Any) -> String {
        return L10n.tr("Localizable", "errors.sync.file_write_denied", String(describing: p1), String(describing: p2), fallback: "You no longer have file-editing access for the group ‘%@’, and files you’ve changed locally cannot be uploaded. If you continue, all group files will be reset to their state on %@.\n\nIf you would like a chance to copy modified files elsewhere or to request file-editing access from a group administrator, you can skip syncing of the group now.")
      }
      /// Group '%@' is no longer accessible. What would you like to do?
      internal static func groupRemoved(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync.group_removed", String(describing: p1), fallback: "Group '%@' is no longer accessible. What would you like to do?")
      }
      /// Keep changes
      internal static let keepChanges = L10n.tr("Localizable", "errors.sync.keep_changes", fallback: "Keep changes")
      /// You can't write to group '%@' anymore. What would you like to do?
      internal static func metadataWriteDenied(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync.metadata_write_denied", String(describing: p1), fallback: "You can't write to group '%@' anymore. What would you like to do?")
      }
      /// Reset Group Files and Sync
      internal static let resetGroupFiles = L10n.tr("Localizable", "errors.sync.reset_group_files", fallback: "Reset Group Files and Sync")
      /// Revert to original
      internal static let revertToOriginal = L10n.tr("Localizable", "errors.sync.revert_to_original", fallback: "Revert to original")
      /// Skip Group
      internal static let skipGroup = L10n.tr("Localizable", "errors.sync.skip_group", fallback: "Skip Group")
    }
    internal enum SyncToolbar {
      /// Unable to upload attachment: %@. Please try removing and re-adding the attachment.
      internal static func attachmentMissing(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.attachment_missing", String(describing: p1), fallback: "Unable to upload attachment: %@. Please try removing and re-adding the attachment.")
      }
      /// Remote sync in progress. Please try again in a few minutes.
      internal static let conflictRetryLimit = L10n.tr("Localizable", "errors.sync_toolbar.conflict_retry_limit", fallback: "Remote sync in progress. Please try again in a few minutes.")
      /// Plural format key: "%#@errors@"
      internal static func errors(_ p1: Int) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.errors", p1, fallback: "Plural format key: \"%#@errors@\"")
      }
      /// Finished sync (%@)
      internal static func finishedWithErrors(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.finished_with_errors", String(describing: p1), fallback: "Finished sync (%@)")
      }
      /// Invalid username or password
      internal static let forbidden = L10n.tr("Localizable", "errors.sync_toolbar.forbidden", fallback: "Invalid username or password")
      /// The Zotero sync server did not accept your username and password.
      /// 
      /// Please log out and log in with correct login information.
      internal static let forbiddenMessage = L10n.tr("Localizable", "errors.sync_toolbar.forbidden_message", fallback: "The Zotero sync server did not accept your username and password.\n\nPlease log out and log in with correct login information.")
      /// You don’t have permission to edit groups.
      internal static let groupPermissions = L10n.tr("Localizable", "errors.sync_toolbar.group_permissions", fallback: "You don’t have permission to edit groups.")
      /// The group “%@” has reached its Zotero File Storage quota. Some files were not uploaded. Other Zotero data will continue to sync to the server.
      /// The group owner can increase the group's storage capacity from the storage settings section on zotero.org.
      internal static func groupQuotaReached(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.group_quota_reached", String(describing: p1), fallback: "The group “%@” has reached its Zotero File Storage quota. Some files were not uploaded. Other Zotero data will continue to sync to the server.\nThe group owner can increase the group's storage capacity from the storage settings section on zotero.org.")
      }
      /// Could not sync groups. Please try again.
      internal static let groupsFailed = L10n.tr("Localizable", "errors.sync_toolbar.groups_failed", fallback: "Could not sync groups. Please try again.")
      /// You have insufficient space on your server. Some files were not uploaded. Other Zotero data will continue to sync to our server.
      internal static let insufficientSpace = L10n.tr("Localizable", "errors.sync_toolbar.insufficient_space", fallback: "You have insufficient space on your server. Some files were not uploaded. Other Zotero data will continue to sync to our server.")
      /// Unable to connect to the network. Please try again.
      internal static let internetConnection = L10n.tr("Localizable", "errors.sync_toolbar.internet_connection", fallback: "Unable to connect to the network. Please try again.")
      /// No libraries found. Please sign out and back in again.
      internal static let librariesMissing = L10n.tr("Localizable", "errors.sync_toolbar.libraries_missing", fallback: "No libraries found. Please sign out and back in again.")
      /// You have reached your Zotero File Storage quota. Some files were not uploaded. Other Zotero data will continue to sync to the server.
      /// See your zotero.org account settings for additional storage options.
      internal static let personalQuotaReached = L10n.tr("Localizable", "errors.sync_toolbar.personal_quota_reached", fallback: "You have reached your Zotero File Storage quota. Some files were not uploaded. Other Zotero data will continue to sync to the server.\nSee your zotero.org account settings for additional storage options.")
      /// Quota Reached.
      internal static let quotaReachedShort = L10n.tr("Localizable", "errors.sync_toolbar.quota_reached_short", fallback: "Quota Reached.")
      /// Show Item
      internal static let showItem = L10n.tr("Localizable", "errors.sync_toolbar.show_item", fallback: "Show Item")
      /// Show Items
      internal static let showItems = L10n.tr("Localizable", "errors.sync_toolbar.show_items", fallback: "Show Items")
      /// Zotero services are temporarily unavailable. Please try again in a few minutes.
      internal static let unavailable = L10n.tr("Localizable", "errors.sync_toolbar.unavailable", fallback: "Zotero services are temporarily unavailable. Please try again in a few minutes.")
      /// Could not delete files from your WebDAV server: "%@".
      internal static func webdavError(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.webdav_error", String(describing: p1), fallback: "Could not delete files from your WebDAV server: \"%@\".")
      }
      /// Plural format key: "%#@webdav_error2@"
      internal static func webdavError2(_ p1: Int) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.webdav_error2", p1, fallback: "Plural format key: \"%#@webdav_error2@\"")
      }
      /// Invalid prop file: %@
      internal static func webdavItemProp(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.webdav_item_prop", String(describing: p1), fallback: "Invalid prop file: %@")
      }
      /// Your WebDAV server returned an HTTP %d error for a %@ request.
      internal static func webdavRequestFailed(_ p1: Int, _ p2: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.webdav_request_failed", p1, String(describing: p2), fallback: "Your WebDAV server returned an HTTP %d error for a %@ request.")
      }
    }
    internal enum Translators {
      /// Could not update translators from bundle. Would you like to try again?
      internal static let bundleLoading = L10n.tr("Localizable", "errors.translators.bundle_loading", fallback: "Could not update translators from bundle. Would you like to try again?")
      /// Could not load bundled translators.
      internal static let bundleReset = L10n.tr("Localizable", "errors.translators.bundle_reset", fallback: "Could not load bundled translators.")
    }
  }
  internal enum ItemDetail {
    /// Add attachment
    internal static let addAttachment = L10n.tr("Localizable", "item_detail.add_attachment", fallback: "Add attachment")
    /// Add Creator
    internal static let addCreator = L10n.tr("Localizable", "item_detail.add_creator", fallback: "Add Creator")
    /// Add note
    internal static let addNote = L10n.tr("Localizable", "item_detail.add_note", fallback: "Add note")
    /// Add tag
    internal static let addTag = L10n.tr("Localizable", "item_detail.add_tag", fallback: "Add tag")
    /// Attachments
    internal static let attachments = L10n.tr("Localizable", "item_detail.attachments", fallback: "Attachments")
    /// This item has been changed remotely. It will now reload.
    internal static let dataReloaded = L10n.tr("Localizable", "item_detail.data_reloaded", fallback: "This item has been changed remotely. It will now reload.")
    /// Remove Download
    internal static let deleteAttachmentFile = L10n.tr("Localizable", "item_detail.delete_attachment_file", fallback: "Remove Download")
    /// This item has been deleted. Do you want to restore it?
    internal static let deletedMessage = L10n.tr("Localizable", "item_detail.deleted_message", fallback: "This item has been deleted. Do you want to restore it?")
    /// Deleted
    internal static let deletedTitle = L10n.tr("Localizable", "item_detail.deleted_title", fallback: "Deleted")
    /// Merge name
    internal static let mergeName = L10n.tr("Localizable", "item_detail.merge_name", fallback: "Merge name")
    /// Move to Standalone Attachment
    internal static let moveToStandaloneAttachment = L10n.tr("Localizable", "item_detail.move_to_standalone_attachment", fallback: "Move to Standalone Attachment")
    /// Notes
    internal static let notes = L10n.tr("Localizable", "item_detail.notes", fallback: "Notes")
    /// Show less
    internal static let showLess = L10n.tr("Localizable", "item_detail.show_less", fallback: "Show less")
    /// Show more
    internal static let showMore = L10n.tr("Localizable", "item_detail.show_more", fallback: "Show more")
    /// Split name
    internal static let splitName = L10n.tr("Localizable", "item_detail.split_name", fallback: "Split name")
    /// Tags
    internal static let tags = L10n.tr("Localizable", "item_detail.tags", fallback: "Tags")
    /// Untitled
    internal static let untitled = L10n.tr("Localizable", "item_detail.untitled", fallback: "Untitled")
    /// View PDF
    internal static let viewPdf = L10n.tr("Localizable", "item_detail.view_pdf", fallback: "View PDF")
  }
  internal enum Items {
    /// Ascending
    internal static let ascending = L10n.tr("Localizable", "items.ascending", fallback: "Ascending")
    /// Scan Barcode
    internal static let barcode = L10n.tr("Localizable", "items.barcode", fallback: "Scan Barcode")
    /// Plural format key: "%#@collections_selected@"
    internal static func collectionsSelected(_ p1: Int) -> String {
      return L10n.tr("Localizable", "items.collections_selected", p1, fallback: "Plural format key: \"%#@collections_selected@\"")
    }
    /// Plural format key: "%#@delete_question@"
    internal static func deleteQuestion(_ p1: Int) -> String {
      return L10n.tr("Localizable", "items.delete_question", p1, fallback: "Plural format key: \"%#@delete_question@\"")
    }
    /// Descending
    internal static let descending = L10n.tr("Localizable", "items.descending", fallback: "Descending")
    /// Deselect All
    internal static let deselectAll = L10n.tr("Localizable", "items.deselect_all", fallback: "Deselect All")
    /// Generating Bibliography
    internal static let generatingBib = L10n.tr("Localizable", "items.generating_bib", fallback: "Generating Bibliography")
    /// Add by Identifier
    internal static let lookup = L10n.tr("Localizable", "items.lookup", fallback: "Add by Identifier")
    /// Add Manually
    internal static let new = L10n.tr("Localizable", "items.new", fallback: "Add Manually")
    /// Add File
    internal static let newFile = L10n.tr("Localizable", "items.new_file", fallback: "Add File")
    /// New Standalone Note
    internal static let newNote = L10n.tr("Localizable", "items.new_note", fallback: "New Standalone Note")
    /// Plural format key: "%#@remove_from_collection_question@"
    internal static func removeFromCollectionQuestion(_ p1: Int) -> String {
      return L10n.tr("Localizable", "items.remove_from_collection_question", p1, fallback: "Plural format key: \"%#@remove_from_collection_question@\"")
    }
    /// Remove from Collection
    internal static let removeFromCollectionTitle = L10n.tr("Localizable", "items.remove_from_collection_title", fallback: "Remove from Collection")
    /// Restore Open Items
    internal static let restoreOpen = L10n.tr("Localizable", "items.restore_open", fallback: "Restore Open Items")
    /// Search Items
    internal static let searchTitle = L10n.tr("Localizable", "items.search_title", fallback: "Search Items")
    /// Select All
    internal static let selectAll = L10n.tr("Localizable", "items.select_all", fallback: "Select All")
    /// Sort By
    internal static let sortBy = L10n.tr("Localizable", "items.sort_by", fallback: "Sort By")
    /// Sort Order
    internal static let sortOrder = L10n.tr("Localizable", "items.sort_order", fallback: "Sort Order")
    /// Downloaded %d / %d
    internal static func toolbarDownloaded(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "items.toolbar_downloaded", p1, p2, fallback: "Downloaded %d / %d")
    }
    /// Plural format key: "%#@toolbar_filter@"
    internal static func toolbarFilter(_ p1: Int) -> String {
      return L10n.tr("Localizable", "items.toolbar_filter", p1, fallback: "Plural format key: \"%#@toolbar_filter@\"")
    }
    /// Saved %d / %d
    internal static func toolbarSaved(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "items.toolbar_saved", p1, p2, fallback: "Saved %d / %d")
    }
    internal enum Action {
      /// Add to Collection
      internal static let addToCollection = L10n.tr("Localizable", "items.action.add_to_collection", fallback: "Add to Collection")
      /// Create Parent Item
      internal static let createParent = L10n.tr("Localizable", "items.action.create_parent", fallback: "Create Parent Item")
      /// Download
      internal static let download = L10n.tr("Localizable", "items.action.download", fallback: "Download")
      /// Duplicate
      internal static let duplicate = L10n.tr("Localizable", "items.action.duplicate", fallback: "Duplicate")
      /// Remove Download
      internal static let removeDownload = L10n.tr("Localizable", "items.action.remove_download", fallback: "Remove Download")
      /// Remove from Collection
      internal static let removeFromCollection = L10n.tr("Localizable", "items.action.remove_from_collection", fallback: "Remove from Collection")
    }
    internal enum CreatorSummary {
      /// %@ and %@
      internal static func and(_ p1: Any, _ p2: Any) -> String {
        return L10n.tr("Localizable", "items.creator_summary.and", String(describing: p1), String(describing: p2), fallback: "%@ and %@")
      }
      /// %@ et al.
      internal static func etal(_ p1: Any) -> String {
        return L10n.tr("Localizable", "items.creator_summary.etal", String(describing: p1), fallback: "%@ et al.")
      }
    }
    internal enum Filters {
      /// Downloaded Files
      internal static let downloads = L10n.tr("Localizable", "items.filters.downloads", fallback: "Downloaded Files")
      /// Tags
      internal static let tags = L10n.tr("Localizable", "items.filters.tags", fallback: "Tags")
      /// Filters
      internal static let title = L10n.tr("Localizable", "items.filters.title", fallback: "Filters")
    }
  }
  internal enum Libraries {
    /// Do you really want to delete "%@"?
    internal static func deleteQuestion(_ p1: Any) -> String {
      return L10n.tr("Localizable", "libraries.delete_question", String(describing: p1), fallback: "Do you really want to delete \"%@\"?")
    }
    /// Group Libraries
    internal static let groupLibraries = L10n.tr("Localizable", "libraries.group_libraries", fallback: "Group Libraries")
    /// My Library
    internal static let myLibrary = L10n.tr("Localizable", "libraries.my_library", fallback: "My Library")
  }
  internal enum Login {
    /// Email
    internal static let email = L10n.tr("Localizable", "login.email", fallback: "Email")
    /// Forgot Password?
    internal static let forgotPassword = L10n.tr("Localizable", "login.forgot_password", fallback: "Forgot Password?")
    /// Password
    internal static let password = L10n.tr("Localizable", "login.password", fallback: "Password")
    /// Repeat password
    internal static let repeatPassword = L10n.tr("Localizable", "login.repeat_password", fallback: "Repeat password")
    /// Username
    internal static let username = L10n.tr("Localizable", "login.username", fallback: "Username")
  }
  internal enum Lookup {
    /// Enter ISBNs, DOls, PMIDs, arXiv IDs, or ADS Bibcodes to add to your library:
    internal static let title = L10n.tr("Localizable", "lookup.title", fallback: "Enter ISBNs, DOls, PMIDs, arXiv IDs, or ADS Bibcodes to add to your library:")
  }
  internal enum Onboarding {
    /// <b>Zotero organizes research</b> however you want. Sort your items into collections and tag them with keywords.
    internal static let access = L10n.tr("Localizable", "onboarding.access", fallback: "<b>Zotero organizes research</b> however you want. Sort your items into collections and tag them with keywords.")
    /// <b>Highlight and take notes</b> directly in your PDFs as you read them.
    internal static let annotate = L10n.tr("Localizable", "onboarding.annotate", fallback: "<b>Highlight and take notes</b> directly in your PDFs as you read them.")
    /// Sign Up
    internal static let createAccount = L10n.tr("Localizable", "onboarding.create_account", fallback: "Sign Up")
    /// <b>Tap to collect</b> articles and books directly from the web, including their PDFs and full metadata.
    internal static let share = L10n.tr("Localizable", "onboarding.share", fallback: "<b>Tap to collect</b> articles and books directly from the web, including their PDFs and full metadata.")
    /// Sign In
    internal static let signIn = L10n.tr("Localizable", "onboarding.sign_in", fallback: "Sign In")
    /// <b>Synchronize and collaborate</b> across devices, keeping your reading and notes seamlessly up to date.
    internal static let sync = L10n.tr("Localizable", "onboarding.sync", fallback: "<b>Synchronize and collaborate</b> across devices, keeping your reading and notes seamlessly up to date.")
  }
  internal enum Pdf {
    /// This document has been deleted. Do you want to restore it?
    internal static let deletedMessage = L10n.tr("Localizable", "pdf.deleted_message", fallback: "This document has been deleted. Do you want to restore it?")
    /// Deleted
    internal static let deletedTitle = L10n.tr("Localizable", "pdf.deleted_title", fallback: "Deleted")
    /// Highlight
    internal static let highlight = L10n.tr("Localizable", "pdf.highlight", fallback: "Highlight")
    /// %0.1f pt
    internal static func lineWidthPoint(_ p1: Float) -> String {
      return L10n.tr("Localizable", "pdf.line_width_point", p1, fallback: "%0.1f pt")
    }
    internal enum AnnotationPopover {
      /// Delete Annotation
      internal static let delete = L10n.tr("Localizable", "pdf.annotation_popover.delete", fallback: "Delete Annotation")
      /// Width
      internal static let lineWidth = L10n.tr("Localizable", "pdf.annotation_popover.line_width", fallback: "Width")
      /// No comment
      internal static let noComment = L10n.tr("Localizable", "pdf.annotation_popover.no_comment", fallback: "No comment")
      /// Edit Page Number
      internal static let pageLabelTitle = L10n.tr("Localizable", "pdf.annotation_popover.page_label_title", fallback: "Edit Page Number")
      /// Size
      internal static let size = L10n.tr("Localizable", "pdf.annotation_popover.size", fallback: "Size")
      /// Edit Annotation
      internal static let title = L10n.tr("Localizable", "pdf.annotation_popover.title", fallback: "Edit Annotation")
      /// Update subsequent pages
      internal static let updateSubsequentPages = L10n.tr("Localizable", "pdf.annotation_popover.update_subsequent_pages", fallback: "Update subsequent pages")
    }
    internal enum AnnotationShare {
      internal enum Image {
        /// Large
        internal static let large = L10n.tr("Localizable", "pdf.annotation_share.image.large", fallback: "Large")
        /// Medium
        internal static let medium = L10n.tr("Localizable", "pdf.annotation_share.image.medium", fallback: "Medium")
        /// Share image
        internal static let share = L10n.tr("Localizable", "pdf.annotation_share.image.share", fallback: "Share image")
      }
    }
    internal enum AnnotationToolbar {
      /// Eraser
      internal static let eraser = L10n.tr("Localizable", "pdf.annotation_toolbar.eraser", fallback: "Eraser")
      /// Highlight
      internal static let highlight = L10n.tr("Localizable", "pdf.annotation_toolbar.highlight", fallback: "Highlight")
      /// Image
      internal static let image = L10n.tr("Localizable", "pdf.annotation_toolbar.image", fallback: "Image")
      /// Ink
      internal static let ink = L10n.tr("Localizable", "pdf.annotation_toolbar.ink", fallback: "Ink")
      /// Note
      internal static let note = L10n.tr("Localizable", "pdf.annotation_toolbar.note", fallback: "Note")
    }
    internal enum AnnotationsSidebar {
      /// Add comment
      internal static let addComment = L10n.tr("Localizable", "pdf.annotations_sidebar.add_comment", fallback: "Add comment")
      /// Add tags
      internal static let addTags = L10n.tr("Localizable", "pdf.annotations_sidebar.add_tags", fallback: "Add tags")
      /// Merge
      internal static let merge = L10n.tr("Localizable", "pdf.annotations_sidebar.merge", fallback: "Merge")
      /// Search
      internal static let searchTitle = L10n.tr("Localizable", "pdf.annotations_sidebar.search_title", fallback: "Search")
      internal enum Filter {
        /// Select Tags…
        internal static let tagsPlaceholder = L10n.tr("Localizable", "pdf.annotations_sidebar.filter.tags_placeholder", fallback: "Select Tags…")
        /// Filter Annotations
        internal static let title = L10n.tr("Localizable", "pdf.annotations_sidebar.filter.title", fallback: "Filter Annotations")
      }
    }
    internal enum Export {
      /// Export
      internal static let export = L10n.tr("Localizable", "pdf.export.export", fallback: "Export")
      /// Include annotations
      internal static let includeAnnotations = L10n.tr("Localizable", "pdf.export.include_annotations", fallback: "Include annotations")
    }
    internal enum Locked {
      /// Please enter the password to open this PDF.
      internal static let enterPassword = L10n.tr("Localizable", "pdf.locked.enter_password", fallback: "Please enter the password to open this PDF.")
      /// Incorrect password. Please try again.
      internal static let failed = L10n.tr("Localizable", "pdf.locked.failed", fallback: "Incorrect password. Please try again.")
      /// Locked
      internal static let locked = L10n.tr("Localizable", "pdf.locked.locked", fallback: "Locked")
    }
    internal enum Search {
      /// Search failed
      internal static let failed = L10n.tr("Localizable", "pdf.search.failed", fallback: "Search failed")
      /// Plural format key: "%#@matches@"
      internal static func matches(_ p1: Int) -> String {
        return L10n.tr("Localizable", "pdf.search.matches", p1, fallback: "Plural format key: \"%#@matches@\"")
      }
      /// Search in Document
      internal static let title = L10n.tr("Localizable", "pdf.search.title", fallback: "Search in Document")
    }
    internal enum Settings {
      /// Allow device to sleep
      internal static let idleTimerTitle = L10n.tr("Localizable", "pdf.settings.idle_timer_title", fallback: "Allow device to sleep")
      internal enum Appearance {
        /// Automatic
        internal static let auto = L10n.tr("Localizable", "pdf.settings.appearance.auto", fallback: "Automatic")
        /// Dark
        internal static let darkMode = L10n.tr("Localizable", "pdf.settings.appearance.dark_mode", fallback: "Dark")
        /// Light
        internal static let lightMode = L10n.tr("Localizable", "pdf.settings.appearance.light_mode", fallback: "Light")
        /// Appearance
        internal static let title = L10n.tr("Localizable", "pdf.settings.appearance.title", fallback: "Appearance")
      }
      internal enum PageFitting {
        /// Automatic
        internal static let automatic = L10n.tr("Localizable", "pdf.settings.page_fitting.automatic", fallback: "Automatic")
        /// Fill
        internal static let fill = L10n.tr("Localizable", "pdf.settings.page_fitting.fill", fallback: "Fill")
        /// Fit
        internal static let fit = L10n.tr("Localizable", "pdf.settings.page_fitting.fit", fallback: "Fit")
        /// Page Fitting
        internal static let title = L10n.tr("Localizable", "pdf.settings.page_fitting.title", fallback: "Page Fitting")
      }
      internal enum PageMode {
        /// Automatic
        internal static let automatic = L10n.tr("Localizable", "pdf.settings.page_mode.automatic", fallback: "Automatic")
        /// Double
        internal static let double = L10n.tr("Localizable", "pdf.settings.page_mode.double", fallback: "Double")
        /// Single
        internal static let single = L10n.tr("Localizable", "pdf.settings.page_mode.single", fallback: "Single")
        /// Page Mode
        internal static let title = L10n.tr("Localizable", "pdf.settings.page_mode.title", fallback: "Page Mode")
      }
      internal enum PageTransition {
        /// Continuous
        internal static let continuous = L10n.tr("Localizable", "pdf.settings.page_transition.continuous", fallback: "Continuous")
        /// Jump
        internal static let jump = L10n.tr("Localizable", "pdf.settings.page_transition.jump", fallback: "Jump")
        /// Page Transition
        internal static let title = L10n.tr("Localizable", "pdf.settings.page_transition.title", fallback: "Page Transition")
      }
      internal enum ScrollDirection {
        /// Horizontal
        internal static let horizontal = L10n.tr("Localizable", "pdf.settings.scroll_direction.horizontal", fallback: "Horizontal")
        /// Scroll Direction
        internal static let title = L10n.tr("Localizable", "pdf.settings.scroll_direction.title", fallback: "Scroll Direction")
        /// Vertical
        internal static let vertical = L10n.tr("Localizable", "pdf.settings.scroll_direction.vertical", fallback: "Vertical")
      }
    }
    internal enum Sidebar {
      /// No Annotations
      internal static let noAnnotations = L10n.tr("Localizable", "pdf.sidebar.no_annotations", fallback: "No Annotations")
      /// No Outline
      internal static let noOutline = L10n.tr("Localizable", "pdf.sidebar.no_outline", fallback: "No Outline")
    }
  }
  internal enum Searchbar {
    /// Cancel Search
    internal static let accessibilityCancel = L10n.tr("Localizable", "searchbar.accessibility_cancel", fallback: "Cancel Search")
    /// Clear Search
    internal static let accessibilityClear = L10n.tr("Localizable", "searchbar.accessibility_clear", fallback: "Clear Search")
    /// Search
    internal static let placeholder = L10n.tr("Localizable", "searchbar.placeholder", fallback: "Search")
  }
  internal enum Settings {
    /// Cancel Logging
    internal static let cancelLogging = L10n.tr("Localizable", "settings.cancel_logging", fallback: "Cancel Logging")
    /// Clear Output
    internal static let clearOutput = L10n.tr("Localizable", "settings.clear_output", fallback: "Clear Output")
    /// Debug Output Logging
    internal static let debug = L10n.tr("Localizable", "settings.debug", fallback: "Debug Output Logging")
    /// Export Database File
    internal static let exportDb = L10n.tr("Localizable", "settings.export_db", fallback: "Export Database File")
    /// Item count
    internal static let itemCount = L10n.tr("Localizable", "settings.item_count", fallback: "Item count")
    /// Show item count for all collections.
    internal static let itemCountSubtitle = L10n.tr("Localizable", "settings.item_count_subtitle", fallback: "Show item count for all collections.")
    /// Plural format key: "%#@lines@"
    internal static func lines(_ p1: Int) -> String {
      return L10n.tr("Localizable", "settings.lines", p1, fallback: "Plural format key: \"%#@lines@\"")
    }
    /// Plural format key: "%#@lines_logged@"
    internal static func linesLogged(_ p1: Int) -> String {
      return L10n.tr("Localizable", "settings.lines_logged", p1, fallback: "Plural format key: \"%#@lines_logged@\"")
    }
    /// To debug a startup issue, force-quit the app and start it again.
    internal static let loggingDesc1 = L10n.tr("Localizable", "settings.logging_desc1", fallback: "To debug a startup issue, force-quit the app and start it again.")
    /// To debug a share extension issue, open the share extension.
    internal static let loggingDesc2 = L10n.tr("Localizable", "settings.logging_desc2", fallback: "To debug a share extension issue, open the share extension.")
    /// Logging
    internal static let loggingTitle = L10n.tr("Localizable", "settings.logging_title", fallback: "Logging")
    /// Sign Out
    internal static let logout = L10n.tr("Localizable", "settings.logout", fallback: "Sign Out")
    /// Any local data that was not synced will be deleted. Do you really want to sign out?
    internal static let logoutWarning = L10n.tr("Localizable", "settings.logout_warning", fallback: "Any local data that was not synced will be deleted. Do you really want to sign out?")
    /// User Permission
    internal static let permission = L10n.tr("Localizable", "settings.permission", fallback: "User Permission")
    /// Ask for user permission for each write action
    internal static let permissionSubtitle = L10n.tr("Localizable", "settings.permission_subtitle", fallback: "Ask for user permission for each write action")
    /// Reset to bundled
    internal static let resetToBundled = L10n.tr("Localizable", "settings.reset_to_bundled", fallback: "Reset to bundled")
    /// Send Manually
    internal static let sendManually = L10n.tr("Localizable", "settings.send_manually", fallback: "Send Manually")
    /// Start Logging
    internal static let startLogging = L10n.tr("Localizable", "settings.start_logging", fallback: "Start Logging")
    /// Start Logging on Next App Launch
    internal static let startLoggingOnLaunch = L10n.tr("Localizable", "settings.start_logging_on_launch", fallback: "Start Logging on Next App Launch")
    /// Stop Logging
    internal static let stopLogging = L10n.tr("Localizable", "settings.stop_logging", fallback: "Stop Logging")
    /// Local Storage
    internal static let storage = L10n.tr("Localizable", "settings.storage", fallback: "Local Storage")
    /// Settings
    internal static let title = L10n.tr("Localizable", "settings.title", fallback: "Settings")
    /// Translators
    internal static let translators = L10n.tr("Localizable", "settings.translators", fallback: "Translators")
    /// Update translators
    internal static let translatorsUpdate = L10n.tr("Localizable", "settings.translators_update", fallback: "Update translators")
    /// Updating…
    internal static let translatorsUpdating = L10n.tr("Localizable", "settings.translators_updating", fallback: "Updating…")
    /// Version %@ Build %@
    internal static func versionAndBuild(_ p1: Any, _ p2: Any) -> String {
      return L10n.tr("Localizable", "settings.versionAndBuild", String(describing: p1), String(describing: p2), fallback: "Version %@ Build %@")
    }
    /// View Output
    internal static let viewOutput = L10n.tr("Localizable", "settings.view_output", fallback: "View Output")
    /// Connect to Server
    internal static let websocketConnect = L10n.tr("Localizable", "settings.websocket_connect", fallback: "Connect to Server")
    /// Connected
    internal static let websocketConnected = L10n.tr("Localizable", "settings.websocket_connected", fallback: "Connected")
    /// Connecting
    internal static let websocketConnecting = L10n.tr("Localizable", "settings.websocket_connecting", fallback: "Connecting")
    /// Disconnect from Server
    internal static let websocketDisconnect = L10n.tr("Localizable", "settings.websocket_disconnect", fallback: "Disconnect from Server")
    /// Disconnected
    internal static let websocketDisconnected = L10n.tr("Localizable", "settings.websocket_disconnected", fallback: "Disconnected")
    /// Server Connection
    internal static let websocketTitle = L10n.tr("Localizable", "settings.websocket_title", fallback: "Server Connection")
    internal enum Cite {
      /// Get additional styles
      internal static let getMoreStyles = L10n.tr("Localizable", "settings.cite.get_more_styles", fallback: "Get additional styles")
      /// Citation Styles
      internal static let stylesTitle = L10n.tr("Localizable", "settings.cite.styles_title", fallback: "Citation Styles")
      /// Cite
      internal static let title = L10n.tr("Localizable", "settings.cite.title", fallback: "Cite")
    }
    internal enum CiteSearch {
      /// Search styles
      internal static let searchTitle = L10n.tr("Localizable", "settings.cite_search.search_title", fallback: "Search styles")
    }
    internal enum CrashAlert {
      /// Copy Report ID
      internal static let copyId = L10n.tr("Localizable", "settings.crash_alert.copy_id", fallback: "Copy Report ID")
      /// Copy and Export Database
      internal static let exportDb = L10n.tr("Localizable", "settings.crash_alert.export_db", fallback: "Copy and Export Database")
      /// Your Report ID is %@.
      /// 
      /// Please post a message to the Zotero Forums (forums.zotero.org) with this Report ID and any steps necessary to reproduce the crash.
      internal static func message(_ p1: Any) -> String {
        return L10n.tr("Localizable", "settings.crash_alert.message", String(describing: p1), fallback: "Your Report ID is %@.\n\nPlease post a message to the Zotero Forums (forums.zotero.org) with this Report ID and any steps necessary to reproduce the crash.")
      }
      /// Your Report ID is %@.
      /// 
      /// Please post a message to the Zotero Forums (forums.zotero.org) with this Report ID and any steps necessary to reproduce the crash.
      /// 
      /// If Zotero crashes repeatedly, please tap "Export Database" and send exported files to support@zotero.org.
      internal static func messageWithDb(_ p1: Any) -> String {
        return L10n.tr("Localizable", "settings.crash_alert.message_with_db", String(describing: p1), fallback: "Your Report ID is %@.\n\nPlease post a message to the Zotero Forums (forums.zotero.org) with this Report ID and any steps necessary to reproduce the crash.\n\nIf Zotero crashes repeatedly, please tap \"Export Database\" and send exported files to support@zotero.org.")
      }
      /// Crash Log Sent
      internal static let title = L10n.tr("Localizable", "settings.crash_alert.title", fallback: "Crash Log Sent")
    }
    internal enum Export {
      /// Copy as HTML
      internal static let copyAsHtml = L10n.tr("Localizable", "settings.export.copy_as_html", fallback: "Copy as HTML")
      /// Default Format
      internal static let defaultFormat = L10n.tr("Localizable", "settings.export.default_format", fallback: "Default Format")
      /// Language
      internal static let language = L10n.tr("Localizable", "settings.export.language", fallback: "Language")
      /// Quick Copy
      internal static let title = L10n.tr("Localizable", "settings.export.title", fallback: "Quick Copy")
    }
    internal enum General {
      /// Show collection sizes
      internal static let showCollectionItemCounts = L10n.tr("Localizable", "settings.general.show_collection_item_counts", fallback: "Show collection sizes")
      /// Show Items from Subcollections
      internal static let showSubcollectionsTitle = L10n.tr("Localizable", "settings.general.show_subcollections_title", fallback: "Show Items from Subcollections")
      /// General
      internal static let title = L10n.tr("Localizable", "settings.general.title", fallback: "General")
    }
    internal enum LogAlert {
      /// Your Debug ID is %@
      internal static func message(_ p1: Any) -> String {
        return L10n.tr("Localizable", "settings.log_alert.message", String(describing: p1), fallback: "Your Debug ID is %@")
      }
      /// Sending Logs
      internal static let progressTitle = L10n.tr("Localizable", "settings.log_alert.progress_title", fallback: "Sending Logs")
      /// Logs Sent
      internal static let title = L10n.tr("Localizable", "settings.log_alert.title", fallback: "Logs Sent")
    }
    internal enum Saving {
      /// Automatically attach associated PDFs and other files when saving items
      internal static let filesMessage = L10n.tr("Localizable", "settings.saving.files_message", fallback: "Automatically attach associated PDFs and other files when saving items")
      /// Save Files
      internal static let filesTitle = L10n.tr("Localizable", "settings.saving.files_title", fallback: "Save Files")
      /// Automatically tag items with keywords and subject headings
      internal static let tagsMessage = L10n.tr("Localizable", "settings.saving.tags_message", fallback: "Automatically tag items with keywords and subject headings")
      /// Save Automatic Tags
      internal static let tagsTitle = L10n.tr("Localizable", "settings.saving.tags_title", fallback: "Save Automatic Tags")
      /// Saving
      internal static let title = L10n.tr("Localizable", "settings.saving.title", fallback: "Saving")
    }
    internal enum Storage {
      /// Delete All Local Attachment Files
      internal static let deleteAll = L10n.tr("Localizable", "settings.storage.delete_all", fallback: "Delete All Local Attachment Files")
      /// Are you sure you want to delete all attachment files from this device?
      /// 
      /// Other synced devices will not be affected.
      internal static let deleteAllQuestion = L10n.tr("Localizable", "settings.storage.delete_all_question", fallback: "Are you sure you want to delete all attachment files from this device?\n\nOther synced devices will not be affected.")
      /// Are you sure you want to delete all attachment files in %@ from this device?
      /// 
      /// Other synced devices will not be affected.
      internal static func deleteLibraryQuestion(_ p1: Any) -> String {
        return L10n.tr("Localizable", "settings.storage.delete_library_question", String(describing: p1), fallback: "Are you sure you want to delete all attachment files in %@ from this device?\n\nOther synced devices will not be affected.")
      }
      /// Plural format key: "%#@files@ (%.2f %@)"
      internal static func filesSizeAndUnit(_ p1: Int, _ p2: Float, _ p3: Any) -> String {
        return L10n.tr("Localizable", "settings.storage.files_size_and_unit", p1, p2, String(describing: p3), fallback: "Plural format key: \"%#@files@ (%.2f %@)\"")
      }
    }
    internal enum Sync {
      /// Account
      internal static let account = L10n.tr("Localizable", "settings.sync.account", fallback: "Account")
      /// Data Syncing
      internal static let dataSyncing = L10n.tr("Localizable", "settings.sync.data_syncing", fallback: "Data Syncing")
      /// Delete Account
      internal static let deleteAccount = L10n.tr("Localizable", "settings.sync.delete_account", fallback: "Delete Account")
      /// File Syncing
      internal static let fileSyncing = L10n.tr("Localizable", "settings.sync.file_syncing", fallback: "File Syncing")
      /// Sync attachment files in My Library using
      internal static let fileSyncingTypeMessage = L10n.tr("Localizable", "settings.sync.file_syncing_type_message", fallback: "Sync attachment files in My Library using")
      /// Manage Account
      internal static let manageAccount = L10n.tr("Localizable", "settings.sync.manage_account", fallback: "Manage Account")
      /// Password
      internal static let password = L10n.tr("Localizable", "settings.sync.password", fallback: "Password")
      /// Account
      internal static let title = L10n.tr("Localizable", "settings.sync.title", fallback: "Account")
      /// Username
      internal static let username = L10n.tr("Localizable", "settings.sync.username", fallback: "Username")
      /// Verified
      internal static let verified = L10n.tr("Localizable", "settings.sync.verified", fallback: "Verified")
      /// Verify Server
      internal static let verify = L10n.tr("Localizable", "settings.sync.verify", fallback: "Verify Server")
      internal enum DirectoryNotFound {
        /// %@ does not exist.
        /// 
        /// Do you want to create it now?
        internal static func message(_ p1: Any) -> String {
          return L10n.tr("Localizable", "settings.sync.directory_not_found.message", String(describing: p1), fallback: "%@ does not exist.\n\nDo you want to create it now?")
        }
        /// Directory not found
        internal static let title = L10n.tr("Localizable", "settings.sync.directory_not_found.title", fallback: "Directory not found")
      }
    }
  }
  internal enum Shareext {
    /// More
    internal static let collectionOther = L10n.tr("Localizable", "shareext.collection_other", fallback: "More")
    /// Collection
    internal static let collectionTitle = L10n.tr("Localizable", "shareext.collection_title", fallback: "Collection")
    /// Searching for items
    internal static let decodingAttachment = L10n.tr("Localizable", "shareext.decoding_attachment", fallback: "Searching for items")
    /// Item
    internal static let itemTitle = L10n.tr("Localizable", "shareext.item_title", fallback: "Item")
    /// Loading Collections
    internal static let loadingCollections = L10n.tr("Localizable", "shareext.loading_collections", fallback: "Loading Collections")
    /// Save to Zotero
    internal static let save = L10n.tr("Localizable", "shareext.save", fallback: "Save to Zotero")
    /// Can't sync collections
    internal static let syncError = L10n.tr("Localizable", "shareext.sync_error", fallback: "Can't sync collections")
    /// Tags
    internal static let tagsTitle = L10n.tr("Localizable", "shareext.tags_title", fallback: "Tags")
    internal enum Translation {
      /// Choose an item
      internal static let itemSelection = L10n.tr("Localizable", "shareext.translation.item_selection", fallback: "Choose an item")
      /// Saving with %@
      internal static func translatingWith(_ p1: Any) -> String {
        return L10n.tr("Localizable", "shareext.translation.translating_with", String(describing: p1), fallback: "Saving with %@")
      }
    }
  }
  internal enum Sync {
    internal enum ConflictResolution {
      /// The item “%@” has been removed. Do you want to keep your changes?
      internal static func changedItemDeleted(_ p1: Any) -> String {
        return L10n.tr("Localizable", "sync.conflict_resolution.changed_item_deleted", String(describing: p1), fallback: "The item “%@” has been removed. Do you want to keep your changes?")
      }
    }
  }
  internal enum SyncToolbar {
    /// Sync failed (%@)
    internal static func aborted(_ p1: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.aborted", String(describing: p1), fallback: "Sync failed (%@)")
    }
    /// Applying remote deletions in %@
    internal static func deletion(_ p1: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.deletion", String(describing: p1), fallback: "Applying remote deletions in %@")
    }
    /// Finished sync
    internal static let finished = L10n.tr("Localizable", "sync_toolbar.finished", fallback: "Finished sync")
    /// Syncing groups
    internal static let groups = L10n.tr("Localizable", "sync_toolbar.groups", fallback: "Syncing groups")
    /// Syncing groups (%d / %d)
    internal static func groupsWithData(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "sync_toolbar.groups_with_data", p1, p2, fallback: "Syncing groups (%d / %d)")
    }
    /// Syncing %@
    internal static func library(_ p1: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.library", String(describing: p1), fallback: "Syncing %@")
    }
    /// Syncing %@ in %@
    internal static func object(_ p1: Any, _ p2: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.object", String(describing: p1), String(describing: p2), fallback: "Syncing %@ in %@")
    }
    /// Syncing %@ (%d / %d) in %@
    internal static func objectWithData(_ p1: Any, _ p2: Int, _ p3: Int, _ p4: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.object_with_data", String(describing: p1), p2, p3, String(describing: p4), fallback: "Syncing %@ (%d / %d) in %@")
    }
    /// Sync starting
    internal static let starting = L10n.tr("Localizable", "sync_toolbar.starting", fallback: "Sync starting")
    /// Uploading attachment (%d / %d)
    internal static func uploads(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "sync_toolbar.uploads", p1, p2, fallback: "Uploading attachment (%d / %d)")
    }
    /// Uploading changes (%d / %d)
    internal static func writes(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "sync_toolbar.writes", p1, p2, fallback: "Uploading changes (%d / %d)")
    }
    internal enum Object {
      /// collections
      internal static let collections = L10n.tr("Localizable", "sync_toolbar.object.collections", fallback: "collections")
      /// groups
      internal static let groups = L10n.tr("Localizable", "sync_toolbar.object.groups", fallback: "groups")
      /// items
      internal static let items = L10n.tr("Localizable", "sync_toolbar.object.items", fallback: "items")
      /// searches
      internal static let searches = L10n.tr("Localizable", "sync_toolbar.object.searches", fallback: "searches")
    }
  }
  internal enum TagPicker {
    /// Plural format key: "%#@confirm_deletion@"
    internal static func confirmDeletion(_ p1: Int) -> String {
      return L10n.tr("Localizable", "tag_picker.confirm_deletion", p1, fallback: "Plural format key: \"%#@confirm_deletion@\"")
    }
    /// Delete Automatic Tags
    internal static let confirmDeletionQuestion = L10n.tr("Localizable", "tag_picker.confirm_deletion_question", fallback: "Delete Automatic Tags")
    /// Create Tag “%@”
    internal static func createTag(_ p1: Any) -> String {
      return L10n.tr("Localizable", "tag_picker.create_tag", String(describing: p1), fallback: "Create Tag “%@”")
    }
    /// Delete Automatic Tags in This Library
    internal static let deleteAutomatic = L10n.tr("Localizable", "tag_picker.delete_automatic", fallback: "Delete Automatic Tags in This Library")
    /// Deselect All
    internal static let deselectAll = L10n.tr("Localizable", "tag_picker.deselect_all", fallback: "Deselect All")
    /// Tag name
    internal static let placeholder = L10n.tr("Localizable", "tag_picker.placeholder", fallback: "Tag name")
    /// Search Tags
    internal static let searchPlaceholder = L10n.tr("Localizable", "tag_picker.search_placeholder", fallback: "Search Tags")
    /// Display All Tags in This Library
    internal static let showAll = L10n.tr("Localizable", "tag_picker.show_all", fallback: "Display All Tags in This Library")
    /// Show Automatic Tags
    internal static let showAuto = L10n.tr("Localizable", "tag_picker.show_auto", fallback: "Show Automatic Tags")
    /// Plural format key: "%#@tags_selected@"
    internal static func tagsSelected(_ p1: Int) -> String {
      return L10n.tr("Localizable", "tag_picker.tags_selected", p1, fallback: "Plural format key: \"%#@tags_selected@\"")
    }
    /// %d selected
    internal static func title(_ p1: Int) -> String {
      return L10n.tr("Localizable", "tag_picker.title", p1, fallback: "%d selected")
    }
  }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

extension L10n {
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
