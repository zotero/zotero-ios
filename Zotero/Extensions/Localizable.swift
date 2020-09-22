// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name
internal enum L10n {
  /// Abstract
  internal static let abstract = L10n.tr("Localizable", "abstract")
  /// Add
  internal static let add = L10n.tr("Localizable", "add")
  /// Cancel
  internal static let cancel = L10n.tr("Localizable", "cancel")
  /// Close
  internal static let close = L10n.tr("Localizable", "close")
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
  /// Name
  internal static let name = L10n.tr("Localizable", "name")
  /// No
  internal static let no = L10n.tr("Localizable", "no")
  /// Ok
  internal static let ok = L10n.tr("Localizable", "ok")
  /// Publication Title
  internal static let publicationTitle = L10n.tr("Localizable", "publication_title")
  /// Publisher
  internal static let publisher = L10n.tr("Localizable", "publisher")
  /// Save
  internal static let save = L10n.tr("Localizable", "save")
  /// Title
  internal static let title = L10n.tr("Localizable", "title")
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
    /// Create Collection
    internal static let createTitle = L10n.tr("Localizable", "collections.create_title")
    /// Delete Collection
    internal static let delete = L10n.tr("Localizable", "collections.delete")
    /// Delete Collection and Items
    internal static let deleteWithItems = L10n.tr("Localizable", "collections.delete_with_items")
    /// Edit Collection
    internal static let editTitle = L10n.tr("Localizable", "collections.edit_title")
    /// My Publications
    internal static let myPublications = L10n.tr("Localizable", "collections.my_publications")
    /// New Subcollection
    internal static let newSubcollection = L10n.tr("Localizable", "collections.new_subcollection")
    /// Pick Parent
    internal static let pickerTitle = L10n.tr("Localizable", "collections.picker_title")
    /// Search Collections
    internal static let searchTitle = L10n.tr("Localizable", "collections.search_title")
    /// Trash
    internal static let trash = L10n.tr("Localizable", "collections.trash")
    internal enum Error {
      /// You have to fill the name
      internal static let emptyName = L10n.tr("Localizable", "collections.error.empty_name")
      /// Could not save collection %@. Try again.
      internal static func saveFailed(_ p1: Any) -> String {
        return L10n.tr("Localizable", "collections.error.save_failed", String(describing: p1))
      }
    }
  }

  internal enum Errors {
    /// Failed API response: %@
    internal static func api(_ p1: Any) -> String {
      return L10n.tr("Localizable", "errors.api", String(describing: p1))
    }
    /// Could not connect to database. Device storage might be full.
    internal static let db = L10n.tr("Localizable", "errors.db")
    /// Could not parse some data. Other data will continue to sync.
    internal static let parsing = L10n.tr("Localizable", "errors.parsing")
    /// Some data in My Library could not be downloaded. It may have been saved with a newer version of Zotero.\n\nOther data will continue to sync.
    internal static let schema = L10n.tr("Localizable", "errors.schema")
    /// Unknown error
    internal static let unknown = L10n.tr("Localizable", "errors.unknown")
    /// Another sync has happened during sync
    internal static let versionMismatch = L10n.tr("Localizable", "errors.versionMismatch")
  }

  internal enum ItemDetail {
    /// Add attachment
    internal static let addAttachment = L10n.tr("Localizable", "item_detail.add_attachment")
    /// Add creator
    internal static let addCreator = L10n.tr("Localizable", "item_detail.add_creator")
    /// Add note
    internal static let addNote = L10n.tr("Localizable", "item_detail.add_note")
    /// Add tag
    internal static let addTag = L10n.tr("Localizable", "item_detail.add_tag")
    /// Attachments
    internal static let attachments = L10n.tr("Localizable", "item_detail.attachments")
    /// Merge name
    internal static let mergeName = L10n.tr("Localizable", "item_detail.merge_name")
    /// Notes
    internal static let notes = L10n.tr("Localizable", "item_detail.notes")
    /// Search Tags...
    internal static let searchTags = L10n.tr("Localizable", "item_detail.search_tags")
    /// Split name
    internal static let splitName = L10n.tr("Localizable", "item_detail.split_name")
    /// Tags
    internal static let tags = L10n.tr("Localizable", "item_detail.tags")
    internal enum Error {
      /// Are you sure you want to change the item type?\nThe following fields will be lost:\n%@
      internal static func droppedFieldsMessage(_ p1: Any) -> String {
        return L10n.tr("Localizable", "item_detail.error.dropped_fields_message", String(describing: p1))
      }
      /// Change Item Type
      internal static let droppedFieldsTitle = L10n.tr("Localizable", "item_detail.error.dropped_fields_title")
    }
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
    /// Are you sure you want to restore selected items?
    internal static let restoreMultipleQuestion = L10n.tr("Localizable", "items.restore_multiple_question")
    /// Are you sure you want to restore the selected item?
    internal static let restoreQuestion = L10n.tr("Localizable", "items.restore_question")
    /// Restore
    internal static let restoreTitle = L10n.tr("Localizable", "items.restore_title")
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
    /// Are you sure you want to move selected items to the Trash?
    internal static let trashMultipleQuestion = L10n.tr("Localizable", "items.trash_multiple_question")
    /// Are you sure you want to move the selected item to the Trash?
    internal static let trashQuestion = L10n.tr("Localizable", "items.trash_question")
    /// Move to Trash
    internal static let trashTitle = L10n.tr("Localizable", "items.trash_title")
    /// Select a Collection
    internal static let zeroCollectionsSelected = L10n.tr("Localizable", "items.zero_collections_selected")
    internal enum Error {
      /// Can't open item detail. Please try again.
      internal static let openDetail = L10n.tr("Localizable", "items.error.open_detail")
    }
  }

  internal enum Libraries {
    /// Group Libraries
    internal static let groupLibraries = L10n.tr("Localizable", "libraries.group_libraries")
    /// My Library
    internal static let myLibrary = L10n.tr("Localizable", "libraries.my_library")
    internal enum Error {
      /// Can't load libraries
      internal static let cantLoad = L10n.tr("Localizable", "libraries.error.cantLoad")
    }
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
    internal enum Error {
      /// Invalid password
      internal static let invalidPassword = L10n.tr("Localizable", "login.error.invalid_password")
      /// Invalid username
      internal static let invalidUsername = L10n.tr("Localizable", "login.error.invalid_username")
      /// Could not log in
      internal static let unknown = L10n.tr("Localizable", "login.error.unknown")
    }
  }

  internal enum Onboarding {
    /// <b>Zotero organizes research</b> however you want. Sort your items into collections and tag them with keywords.
    internal static let access = L10n.tr("Localizable", "onboarding.access")
    /// <b>Highlight and take notes</b> directly in your PDFs as you read them.
    internal static let annotate = L10n.tr("Localizable", "onboarding.annotate")
    /// Create Account
    internal static let createAccount = L10n.tr("Localizable", "onboarding.create_account")
    /// <b>Tap to collect</b> articles and books directly from the web, including their PDFs and full citations.
    internal static let share = L10n.tr("Localizable", "onboarding.share")
    /// Sign In
    internal static let signIn = L10n.tr("Localizable", "onboarding.sign_in")
    /// <b>Synchronize and collaborate</b> across devices, keeping your reading and notes seamlessly up to date.
    internal static let sync = L10n.tr("Localizable", "onboarding.sync")
  }

  internal enum Pdf {
    /// Page Transition: %@
    internal static func pageTransition(_ p1: Any) -> String {
      return L10n.tr("Localizable", "pdf.pageTransition", String(describing: p1))
    }
    /// Scroll Direction: %@
    internal static func scrollDirection(_ p1: Any) -> String {
      return L10n.tr("Localizable", "pdf.scrollDirection", String(describing: p1))
    }
    internal enum AnnotationsSidebar {
      /// Add comment
      internal static let addComment = L10n.tr("Localizable", "pdf.annotations_sidebar.add_comment")
      /// Add tags
      internal static let addTags = L10n.tr("Localizable", "pdf.annotations_sidebar.add_tags")
      /// Page
      internal static let page = L10n.tr("Localizable", "pdf.annotations_sidebar.page")
      /// Search Annotations
      internal static let searchTitle = L10n.tr("Localizable", "pdf.annotations_sidebar.search_title")
    }
    internal enum PageTransition {
      /// Continuous
      internal static let continuous = L10n.tr("Localizable", "pdf.pageTransition.continuous")
      /// Jump
      internal static let jump = L10n.tr("Localizable", "pdf.pageTransition.jump")
    }
    internal enum ScrollDirection {
      /// Horizontal
      internal static let horizontal = L10n.tr("Localizable", "pdf.scrollDirection.horizontal")
      /// Vertical
      internal static let vertical = L10n.tr("Localizable", "pdf.scrollDirection.vertical")
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

  internal enum Settings {
    /// Debug
    internal static let debug = L10n.tr("Localizable", "settings.debug")
    /// General
    internal static let general = L10n.tr("Localizable", "settings.general")
    /// Item count
    internal static let itemCount = L10n.tr("Localizable", "settings.item_count")
    /// Show item count for all collections.
    internal static let itemCountSubtitle = L10n.tr("Localizable", "settings.item_count_subtitle")
    /// If you want to debug an issue on launch, kill the app and start it again.
    internal static let loggingDesc1 = L10n.tr("Localizable", "settings.logging_desc1")
    /// If you want to debug share extension issue, open the share extension.
    internal static let loggingDesc2 = L10n.tr("Localizable", "settings.logging_desc2")
    /// Log out
    internal static let logout = L10n.tr("Localizable", "settings.logout")
    /// Your local data that were not synced will be deleted. Do you really want to log out?
    internal static let logoutWarning = L10n.tr("Localizable", "settings.logout_warning")
    /// User Permission
    internal static let permission = L10n.tr("Localizable", "settings.permission")
    /// Ask for user permission for each write action
    internal static let permissionSubtitle = L10n.tr("Localizable", "settings.permission_subtitle")
    /// Profile
    internal static let profile = L10n.tr("Localizable", "settings.profile")
    /// Reset to bundled
    internal static let resetToBundled = L10n.tr("Localizable", "settings.reset_to_bundled")
    /// Start logging
    internal static let startLogging = L10n.tr("Localizable", "settings.start_logging")
    /// Stop logging
    internal static let stopLogging = L10n.tr("Localizable", "settings.stop_logging")
    /// Storage
    internal static let storage = L10n.tr("Localizable", "settings.storage")
    /// Sync
    internal static let sync = L10n.tr("Localizable", "settings.sync")
    /// Cancel ongoing sync
    internal static let syncCancel = L10n.tr("Localizable", "settings.sync_cancel")
    /// Sync with zotero.org
    internal static let syncZotero = L10n.tr("Localizable", "settings.sync_zotero")
    /// Settings
    internal static let title = L10n.tr("Localizable", "settings.title")
    /// Translators
    internal static let translators = L10n.tr("Localizable", "settings.translators")
    /// Update translators
    internal static let translatorsUpdate = L10n.tr("Localizable", "settings.translators_update")
    /// Updating...
    internal static let translatorsUpdating = L10n.tr("Localizable", "settings.translators_updating")
    internal enum Storage {
      /// Delete All Attachments
      internal static let deleteAll = L10n.tr("Localizable", "settings.storage.delete_all")
      /// Do you really want to delete all attachments?
      internal static let deleteAllQuestion = L10n.tr("Localizable", "settings.storage.delete_all_question")
      /// Do you really want to delete all attachments in "%@"?
      internal static func deleteLibraryQuestion(_ p1: Any) -> String {
        return L10n.tr("Localizable", "settings.storage.delete_library_question", String(describing: p1))
      }
      /// Could not collect storage data
      internal static let error = L10n.tr("Localizable", "settings.storage.error")
      /// %d files
      internal static func multipleFiles(_ p1: Int) -> String {
        return L10n.tr("Localizable", "settings.storage.multiple_files", p1)
      }
      /// 1 file
      internal static let oneFile = L10n.tr("Localizable", "settings.storage.one_file")
    }
  }

  internal enum Shareext {
    /// Loading attachment
    internal static let decodingAttachment = L10n.tr("Localizable", "shareext.decoding_attachment")
    /// Save to Zotero
    internal static let save = L10n.tr("Localizable", "shareext.save")
    /// Unknown error occured
    internal static let unknownError = L10n.tr("Localizable", "shareext.unknown_error")
    internal enum Translation {
      /// Downloading
      internal static let downloading = L10n.tr("Localizable", "shareext.translation.downloading")
      /// Pick an item
      internal static let itemSelection = L10n.tr("Localizable", "shareext.translation.item_selection")
      /// Translating with: "%@"
      internal static func translatingWith(_ p1: Any) -> String {
        return L10n.tr("Localizable", "shareext.translation.translating_with", String(describing: p1))
      }
    }
  }

  internal enum SyncToolbar {
    /// Sync failed (%@)
    internal static func aborted(_ p1: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.aborted", String(describing: p1))
    }
    /// Removing unused objects in %@
    internal static func deletion(_ p1: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.deletion", String(describing: p1))
    }
    /// Finished sync
    internal static let finished = L10n.tr("Localizable", "sync_toolbar.finished")
    /// Finished sync (%@)
    internal static func finishedWithErrors(_ p1: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.finished_with_errors", String(describing: p1))
    }
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
    /// %d issues
    internal static func multipleErrors(_ p1: Int) -> String {
      return L10n.tr("Localizable", "sync_toolbar.multiple_errors", p1)
    }
    /// Syncing %@ in %@
    internal static func object(_ p1: Any, _ p2: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.object", String(describing: p1), String(describing: p2))
    }
    /// Syncing %@ (%d / %d) in %@
    internal static func objectWithData(_ p1: Any, _ p2: Int, _ p3: Int, _ p4: Any) -> String {
      return L10n.tr("Localizable", "sync_toolbar.object_with_data", String(describing: p1), p2, p3, String(describing: p4))
    }
    /// 1 issue
    internal static let oneError = L10n.tr("Localizable", "sync_toolbar.one_error")
    /// Sync starting
    internal static let starting = L10n.tr("Localizable", "sync_toolbar.starting")
    /// Uploading attachment (%d / %d)
    internal static func uploads(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "sync_toolbar.uploads", p1, p2)
    }
    /// Submitting changes (%d / %d)
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
// swiftlint:enable nesting type_body_length type_name

// MARK: - Implementation Details

extension L10n {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg...) -> String {
    let format = BundleToken.bundle.localizedString(forKey: key, value: nil, table: table)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}

// swiftlint:disable convenience_type
private final class BundleToken {
  static let bundle: Bundle = {
    Bundle(for: BundleToken.self)
  }()
}
// swiftlint:enable convenience_type
