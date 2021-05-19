// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal enum L10n {
  /// About the Zotero for iOS Beta
  internal static let aboutBeta = L10n.tr("Localizable", "about_beta")
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
  /// Close
  internal static let close = L10n.tr("Localizable", "close")
  /// Copy
  internal static let copy = L10n.tr("Localizable", "copy")
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
  /// Look Up
  internal static let lookup = L10n.tr("Localizable", "lookup")
  /// Name
  internal static let name = L10n.tr("Localizable", "name")
  /// No
  internal static let no = L10n.tr("Localizable", "no")
  /// Not Found
  internal static let notFound = L10n.tr("Localizable", "not_found")
  /// Ok
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

  internal enum Collections {
    /// All Items
    internal static let allItems = L10n.tr("Localizable", "collections.all_items")
    /// Collapse All
    internal static let collapseAll = L10n.tr("Localizable", "collections.collapse_all")
    /// Create Collection
    internal static let createTitle = L10n.tr("Localizable", "collections.create_title")
    /// Delete Collection
    internal static let delete = L10n.tr("Localizable", "collections.delete")
    /// Delete Collection and Items
    internal static let deleteWithItems = L10n.tr("Localizable", "collections.delete_with_items")
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
    /// Could not connect to database. The device storage might be full.
    internal static let db = L10n.tr("Localizable", "errors.db")
    /// Error creating database. Please try logging in again.
    internal static let dbFailure = L10n.tr("Localizable", "errors.db_failure")
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
    }
    internal enum Collections {
      /// Please enter a collection name
      internal static let emptyName = L10n.tr("Localizable", "errors.collections.empty_name")
      /// Unable to save collection
      internal static let saveFailed = L10n.tr("Localizable", "errors.collections.save_failed")
    }
    internal enum ItemDetail {
      /// Could not load data. Please try again.
      internal static let cantLoadData = L10n.tr("Localizable", "errors.item_detail.cant_load_data")
      /// Are you sure you want to change the item type?\n\nThe following fields will be lost:\n\n%@
      internal static func droppedFieldsMessage(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.item_detail.dropped_fields_message", String(describing: p1))
      }
      /// Change Item Type
      internal static let droppedFieldsTitle = L10n.tr("Localizable", "errors.item_detail.dropped_fields_title")
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
      internal static let quotaReached = L10n.tr("Localizable", "errors.shareext.quota_reached")
      /// An error occurred. Please try again.
      internal static let responseMissingData = L10n.tr("Localizable", "errors.shareext.response_missing_data")
      /// Some data could not be downloaded. It may have been saved with a newer version of Zotero.
      internal static let schemaError = L10n.tr("Localizable", "errors.shareext.schema_error")
      /// Saving failed
      internal static let translationFailed = L10n.tr("Localizable", "errors.shareext.translation_failed")
      /// An unknown error occurred.
      internal static let unknown = L10n.tr("Localizable", "errors.shareext.unknown")
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
      /// You don’t have permission to edit groups.
      internal static let groupPermissions = L10n.tr("Localizable", "errors.sync_toolbar.group_permissions")
      /// The group '%@' has reached its Zotero File Storage quota. Some files were not uploaded. Other Zotero data will continue to sync to the server.\nThe group owner can increase the group's storage capacity from the storage settings section on zotero.org.
      internal static func groupQuotaReached(_ p1: Any) -> String {
        return L10n.tr("Localizable", "errors.sync_toolbar.group_quota_reached", String(describing: p1))
      }
      /// Could not sync groups. Please try again.
      internal static let groupsFailed = L10n.tr("Localizable", "errors.sync_toolbar.groups_failed")
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
    /// Notes
    internal static let notes = L10n.tr("Localizable", "item_detail.notes")
    /// Search Tags...
    internal static let searchTags = L10n.tr("Localizable", "item_detail.search_tags")
    /// Show less
    internal static let showLess = L10n.tr("Localizable", "item_detail.show_less")
    /// Show more
    internal static let showMore = L10n.tr("Localizable", "item_detail.show_more")
    /// Split name
    internal static let splitName = L10n.tr("Localizable", "item_detail.split_name")
    /// Tags
    internal static let tags = L10n.tr("Localizable", "item_detail.tags")
    /// Move to Trash
    internal static let trashAttachment = L10n.tr("Localizable", "item_detail.trash_attachment")
    /// Are you sure you want to move this attachment to the trash?
    internal static let trashAttachmentQuestion = L10n.tr("Localizable", "item_detail.trash_attachment_question")
    /// Untitled
    internal static let untitled = L10n.tr("Localizable", "item_detail.untitled")
    /// View PDF
    internal static let viewPdf = L10n.tr("Localizable", "item_detail.view_pdf")
  }

  internal enum Items {
    /// Ascending
    internal static let ascending = L10n.tr("Localizable", "items.ascending")
    /// Are you sure you want to delete selected items?
    internal static let deleteMultipleQuestion = L10n.tr("Localizable", "items.delete_multiple_question")
    /// Are you sure you want to delete the selected item?
    internal static let deleteQuestion = L10n.tr("Localizable", "items.delete_question")
    /// Descending
    internal static let descending = L10n.tr("Localizable", "items.descending")
    /// Deselect All
    internal static let deselectAll = L10n.tr("Localizable", "items.deselect_all")
    /// %d Collections Selected
    internal static func manyCollectionsSelected(_ p1: Int) -> String {
      return L10n.tr("Localizable", "items.many_collections_selected", p1)
    }
    /// New Item
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
    /// Select
    internal static let select = L10n.tr("Localizable", "items.select")
    /// Select All
    internal static let selectAll = L10n.tr("Localizable", "items.select_all")
    /// Sort By
    internal static let sortBy = L10n.tr("Localizable", "items.sort_by")
    /// Sort Order
    internal static let sortOrder = L10n.tr("Localizable", "items.sort_order")
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
      /// Duplicate
      internal static let duplicate = L10n.tr("Localizable", "items.action.duplicate")
      /// Remove from Collection
      internal static let removeFromCollection = L10n.tr("Localizable", "items.action.remove_from_collection")
      /// Move to Trash
      internal static let trash = L10n.tr("Localizable", "items.action.trash")
    }
    internal enum Filters {
      /// Downloaded Files
      internal static let downloads = L10n.tr("Localizable", "items.filters.downloads")
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

  internal enum Onboarding {
    /// <b>Zotero organizes research</b> however you want. Sort your items into collections and tag them with keywords.
    internal static let access = L10n.tr("Localizable", "onboarding.access")
    /// <b>Highlight and take notes</b> directly in your PDFs as you read them.
    internal static let annotate = L10n.tr("Localizable", "onboarding.annotate")
    /// Create Account
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
    internal enum AnnotationPopover {
      /// Delete Annotation
      internal static let delete = L10n.tr("Localizable", "pdf.annotation_popover.delete")
      /// Do you really want to delete this annotation?
      internal static let deleteConfirm = L10n.tr("Localizable", "pdf.annotation_popover.delete_confirm")
      /// No comment
      internal static let noComment = L10n.tr("Localizable", "pdf.annotation_popover.no_comment")
      /// Edit Page Number
      internal static let pageLabelTitle = L10n.tr("Localizable", "pdf.annotation_popover.page_label_title")
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
      /// Search
      internal static let searchTitle = L10n.tr("Localizable", "pdf.annotations_sidebar.search_title")
    }
    internal enum Appearance {
      /// Automatic
      internal static let auto = L10n.tr("Localizable", "pdf.appearance.auto")
      /// Dark Mode
      internal static let darkMode = L10n.tr("Localizable", "pdf.appearance.dark_mode")
      /// Light Mode
      internal static let lightMode = L10n.tr("Localizable", "pdf.appearance.light_mode")
      /// Appearance: %@
      internal static func title(_ p1: Any) -> String {
        return L10n.tr("Localizable", "pdf.appearance.title", String(describing: p1))
      }
    }
    internal enum PageTransition {
      /// Continuous
      internal static let continuous = L10n.tr("Localizable", "pdf.page_transition.continuous")
      /// Jump
      internal static let jump = L10n.tr("Localizable", "pdf.page_transition.jump")
      /// Page Transition: %@
      internal static func title(_ p1: Any) -> String {
        return L10n.tr("Localizable", "pdf.page_transition.title", String(describing: p1))
      }
    }
    internal enum ScrollDirection {
      /// Horizontal
      internal static let horizontal = L10n.tr("Localizable", "pdf.scroll_direction.horizontal")
      /// Scroll Direction: %@
      internal static func title(_ p1: Any) -> String {
        return L10n.tr("Localizable", "pdf.scroll_direction.title", String(describing: p1))
      }
      /// Vertical
      internal static let vertical = L10n.tr("Localizable", "pdf.scroll_direction.vertical")
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
  }

  internal enum Searchbar {
    /// Search
    internal static let placeholder = L10n.tr("Localizable", "searchbar.placeholder")
  }

  internal enum Settings {
    /// Account
    internal static let account = L10n.tr("Localizable", "settings.account")
    /// Debug Output Logging
    internal static let debug = L10n.tr("Localizable", "settings.debug")
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
    /// Sync
    internal static let sync = L10n.tr("Localizable", "settings.sync")
    /// Cancel sync
    internal static let syncCancel = L10n.tr("Localizable", "settings.sync_cancel")
    /// Sync with zotero.org
    internal static let syncZotero = L10n.tr("Localizable", "settings.sync_zotero")
    /// Settings
    internal static let title = L10n.tr("Localizable", "settings.title")
    /// Translators
    internal static let translators = L10n.tr("Localizable", "settings.translators")
    /// Update translators
    internal static let translatorsUpdate = L10n.tr("Localizable", "settings.translators_update")
    /// Updating…
    internal static let translatorsUpdating = L10n.tr("Localizable", "settings.translators_updating")
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
    internal enum CrashAlert {
      /// Your Report ID is %@
      internal static func message(_ p1: Any) -> String {
        return L10n.tr("Localizable", "settings.crash_alert.message", String(describing: p1))
      }
      /// Crash Log Sent
      internal static let title = L10n.tr("Localizable", "settings.crash_alert.title")
    }
    internal enum General {
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
      /// Downloading
      internal static let downloading = L10n.tr("Localizable", "shareext.translation.downloading")
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
