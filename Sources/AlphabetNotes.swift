import Foundation
import AppKit

enum AlphabetNotesScript {
    static let source = #"""
    on bookSnapshot(accountKey, folderKey, pageTitle)
        with timeout of 20 seconds
            set f to my targetFolder(accountKey, folderKey)
            tell application id "com.apple.Notes"
                set matches to notes of f whose name is pageTitle
                if (count of matches) > 1 then error "Multiple category pages have the same name. Resolve the duplicates first." number -2704
                if (count of matches) is 0 then return {"", "", "0"}
                set n to item 1 of matches
                if password protected of n then error "The category page is locked. Unlock it first." number -2704
                return {id of n as text, body of n as text, (count of attachments of n) as text}
            end tell
        end timeout
    end bookSnapshot

    on bookPages(accountKey, folderKey, testMode)
        with timeout of 25 seconds
            set f to my targetFolder(accountKey, folderKey)
            set rows to {}
            tell application id "com.apple.Notes"
                repeat with n in (get notes of f)
                    set pageTitle to name of n as text
                    set wanted to false
                    if testMode is "yes" then
                        if pageTitle starts with \#(LegacyNotesText.appleScriptLiteral("Alphabet test page prefix")) then set wanted to true
                    else
                        if (length of pageTitle) is 1 and "ABCDEFGHIJKLMNOPQRSTUVWXYZ" contains pageTitle then set wanted to true
                        if pageTitle is in {\#(LegacyNotesText.appleScriptLiteral("Han characters")), \#(LegacyNotesText.appleScriptLiteral("Kana")), \#(LegacyNotesText.appleScriptLiteral("Hangul")), \#(LegacyNotesText.appleScriptLiteral("Cyrillic")), \#(LegacyNotesText.appleScriptLiteral("Greek")), \#(LegacyNotesText.appleScriptLiteral("Arabic script category")), \#(LegacyNotesText.appleScriptLiteral("Thai script category")), \#(LegacyNotesText.appleScriptLiteral("Other scripts"))} then set wanted to true
                    end if
                    if wanted then
                        if password protected of n then
                            set end of rows to {pageTitle, id of n as text, "", "-1"}
                        else
                            set end of rows to {pageTitle, id of n as text, body of n as text, (count of attachments of n) as text}
                        end if
                    end if
                end repeat
            end tell
            return rows
        end timeout
    end bookPages

    on putBook(accountKey, folderKey, pageTitle, expectedID, expectedHTML, newHTML, expectedAttachments)
        set writingStarted to false
        set writePhase to ""
        try
            with timeout of 20 seconds
                set f to my targetFolder(accountKey, folderKey)
                tell application id "com.apple.Notes"
                    set matches to notes of f whose name is pageTitle
                    if expectedID is "" then
                        if (count of matches) is not 0 then error "The category page was created elsewhere. Refresh and try again." number -2704
                        set writePhase to "create"
                        set writingStarted to true
                        set n to make new note at f with properties {body:newHTML}
                    else
                        if (count of matches) is not 1 then error "The category page changed. Refresh and try again." number -2704
                        set n to item 1 of matches
                        if (id of n as text) is not expectedID then error "The category page identity changed." number -2704
                        if password protected of n then error "The category page is locked." number -2704
                        if shared of n then error "Shared category pages cannot be updated." number -2704
                        if (body of n as text) is not expectedHTML then error "The note changed before writing. Refresh and try again." number -2704
                        if (count of attachments of n) is not (expectedAttachments as integer) then error "The category page attachments changed. Nothing was updated." number -2704
                        set writePhase to "update"
                        set writingStarted to true
                        set body of n to newHTML
                    end if
                    return {"saved", id of n as text, body of n as text, (count of attachments of n) as text}
                end tell
            end timeout
        on error messageText number errorCode
            -- A thrown write call may still have written data. Preserve the error code and stage for conservative classification.
            if writingStarted then return {"writeError", errorCode as text, messageText, writePhase}
            return {"failed", errorCode as text, messageText}
        end try
    end putBook
    """#
}

extension AppleNotesClient {
    private func bookSnapshot(_ destination: NotesDestination, letter: String, isTest: Bool) throws -> (id: String, html: String, page: AlphabetPage) {
        let empty = AlphabetPage(letter: letter, isTest: isTest, rows: [])
        let row = try call("bookSnapshot", [destination.accountID, destination.folderID, empty.title])
        guard let id = row.atIndex(1)?.stringValue, let html = row.atIndex(2)?.stringValue,
              let attachments = row.atIndex(3)?.stringValue.flatMap(Int.init) else { throw NotesFailure.invalidResponse }
        if id.isEmpty { return ("", "", empty) }
        return (id, html, try AlphabetPage.parse(html: html, letter: letter, isTest: isTest, attachmentCount: attachments))
    }

    private func destinationKey(_ destination: NotesDestination) -> String { destination.accountID + "\n" + destination.folderID }

    func saveAlphabet(_ entry: VocabularyEntry, to destination: NotesDestination) throws -> VocabularyReceipt {
        let letter = try BookRow.letter(entry.word)
        let journal = writeJournal
        return try journal.locked { events in
            // This is not a confirmed non-write: native Notes may create a page before rejecting smart-folder assignment.
            // Block the target even for new queries, and retain the original event for manual reconciliation.
            if events.contains(where: { $0.destinationKey == destinationKey(destination) && $0.destinationRejected == true }) {
                throw NotesFailure.smartFolderReadOnly
            }
            let current = try bookSnapshot(destination, letter: letter, isTest: entry.isTestEntry)
            if let index = events.firstIndex(where: { $0.entryID == entry.id && $0.destinationKey == destinationKey(destination) }) {
                return try confirmEvent(index, events: &events, snapshot: current, entry: entry, journal: journal)
            }
            // Reconcile a pending write to this page first; never increment an uncertain count.
            for index in events.indices where events[index].destinationKey == destinationKey(destination)
                && events[index].letter == letter && events[index].isTest == entry.isTestEntry && !events[index].confirmed {
                guard current.page.digest == events[index].expectedDigest, !current.id.isEmpty else {
                    throw NotesFailure.uncertain(L("Page \(letter) has an unconfirmed collection. Refresh the notebook to reconcile it first."))
                }
                events[index].confirmed = true
                events[index].noteID = current.id
            }
            guard current.page.editable else {
                throw BookError.format(L("Page \(letter) contains additional content or is not a managed table, so it will not be updated. You can read it or choose an empty folder for collecting."))
            }
            var updated = current.page
            let count = try updated.collect(entry)
            let operation = NotesWriteEvent(entryID: entry.id, destinationKey: destinationKey(destination), letter: letter,
                isTest: entry.isTestEntry, expectedDigest: updated.digest, expectedCount: count, noteID: nil, confirmed: false)
            events.append(operation)
            // Persist before writing so a restart cannot make a retry increment the count again.
            try journal.persist(events)
            let result: NSAppleEventDescriptor
            do { result = try call("putBook", [destination.accountID, destination.folderID, updated.title, current.id, current.html, updated.html, String(current.page.tableCount)]) }
            catch { throw NotesFailure.uncertain(error.localizedDescription) }
            let status = result.atIndex(1)?.stringValue
            let rejectedSmartCreation = status == "writeError" && Self.isSmartFolderRejection(result)
            if rejectedSmartCreation {
                if let index = events.firstIndex(where: { $0.entryID == entry.id && $0.destinationKey == destinationKey(destination) }) {
                    events[index].destinationRejected = true
                }
                try journal.persist(events)
                throw NotesFailure.smartFolderReadOnly
            }
            if status == "failed" {
                events.removeAll { $0.entryID == entry.id && $0.destinationKey == destinationKey(destination) }
                try journal.persist(events)
                let code = result.atIndex(2)?.stringValue.flatMap(Int.init) ?? -1
                if code == -1743 { throw NotesFailure.permissionDenied }
                throw NotesFailure.automation(code, result.atIndex(3)?.stringValue ?? L("Pre-write checks failed"))
            }
            if status == "writeError" {
                throw NotesFailure.uncertain(result.atIndex(3)?.stringValue ?? L("The system did not confirm the write result"))
            }
            guard status == "saved", let id = result.atIndex(2)?.stringValue, !id.isEmpty,
                  let html = result.atIndex(3)?.stringValue, let attachments = result.atIndex(4)?.stringValue.flatMap(Int.init) else {
                throw NotesFailure.uncertain(result.atIndex(2)?.stringValue ?? L("No table-save result was returned"))
            }
            let readBack: AlphabetPage
            do { readBack = try AlphabetPage.parse(html: html, letter: letter, isTest: entry.isTestEntry, attachmentCount: attachments) }
            catch { throw NotesFailure.uncertain(L("The table could not be read completely after writing: ") + error.localizedDescription) }
            guard readBack.digest == updated.digest else { throw NotesFailure.uncertain(L("The table readback does not match the submitted content or collection count.")) }
            if let index = events.firstIndex(where: { $0.entryID == entry.id && $0.destinationKey == destinationKey(destination) }) {
                events[index].noteID = id
                events[index].confirmed = true
            }
            try journal.persist(events)
            return VocabularyReceipt(noteID: id, collectionCount: count)
        }
    }

    /// -10000 is generic. Recognize only known create-stage smart-folder rejections to block subsequent target writes.
    /// Unknown localized text, update-stage errors, and timeouts remain pending to avoid duplicate increments.
    private static func isSmartFolderRejection(_ result: NSAppleEventDescriptor) -> Bool {
        guard result.atIndex(2)?.stringValue == "-10000", result.atIndex(4)?.stringValue == "create",
              let message = result.atIndex(3)?.stringValue?.lowercased() else { return false }
        return message.contains(LegacyNotesText.value("Native smart folder rejection fragment"))
            || message.contains("this method cannot be used to assign notes to a smart folder")
            || message.contains("this method can’t be used to assign notes to a smart folder")
            || message.contains("this method can't be used to assign notes to a smart folder")
    }

    private func confirmEvent(_ index: Int, events: inout [NotesWriteEvent],
        snapshot: (id: String, html: String, page: AlphabetPage), entry: VocabularyEntry, journal: NotesWriteJournal) throws -> VocabularyReceipt {
        let event = events[index]
        guard !snapshot.id.isEmpty, let row = snapshot.page.rows.first(where: { $0.key == BookRow.key(entry.word) }), row.count >= event.expectedCount else {
            throw NotesFailure.uncertain(L("The original collection has not been read back or has changed. The count was not increased."))
        }
        if !event.confirmed && snapshot.page.digest != event.expectedDigest {
            throw NotesFailure.uncertain(L("The category page has other changes, so the original collection cannot yet be confirmed. The count was not increased."))
        }
        if event.confirmed, let noteID = event.noteID, noteID != snapshot.id { throw NotesFailure.uncertain(L("The category page identity changed. Check it in Notes.")) }
        events[index].confirmed = true
        events[index].noteID = snapshot.id
        try journal.persist(events)
        return VocabularyReceipt(noteID: snapshot.id, collectionCount: row.count)
    }

    func findAlphabet(_ entry: VocabularyEntry, in destination: NotesDestination) throws -> VocabularyReceipt? {
        let journal = writeJournal
        return try journal.locked { events in
            guard let index = events.firstIndex(where: { $0.entryID == entry.id && $0.destinationKey == destinationKey(destination) }) else { return nil }
            let event = events[index]
            let snapshot = try bookSnapshot(destination, letter: event.letter, isTest: event.isTest)
            return try confirmEvent(index, events: &events, snapshot: snapshot, entry: entry, journal: journal)
        }
    }

    func readVocabulary(from destination: NotesDestination, isTest: Bool = false) throws -> VocabularyLibrary {
        let result = try call("bookPages", [destination.accountID, destination.folderID, isTest ? "yes" : "no"])
        var library = VocabularyLibrary()
        var seen = Set<String>()
        for index in 1..<(result.numberOfItems + 1) {
            guard let item = result.atIndex(index), let title = item.atIndex(1)?.stringValue,
                  let html = item.atIndex(3)?.stringValue, let attachments = item.atIndex(4)?.stringValue.flatMap(Int.init) else { throw NotesFailure.invalidResponse }
            let letter = isTest ? String(title.dropFirst(LegacyNotesText.value("Alphabet test page prefix").count)) : title
            guard BookRow.pageNames.contains(letter) else { continue }
            guard seen.insert(letter).inserted else { library.warnings.append(L("Page \(letter) has a duplicate. Duplicate pages were excluded from statistics.")); continue }
            if attachments < 0 { library.warnings.append(L("Page \(letter) is locked and was not read.")); continue }
            do {
                let page = try AlphabetPage.parse(html: html, letter: letter, isTest: isTest, attachmentCount: attachments)
                library.rows += page.rows
                if !page.editable { library.warnings.append(L("Page \(letter) is read-only because it has additional content or does not use the managed format.")) }
            } catch { library.warnings.append(L("Page \(letter): \(error.localizedDescription)")) }
        }
        library.rows.sort { $0.key < $1.key }
        return library
    }

    func existingWord(_ word: String, in destination: NotesDestination, isTest: Bool = false) throws -> BookRow? {
        let snapshot = try bookSnapshot(destination, letter: BookRow.letter(word), isTest: isTest)
        return snapshot.page.rows.first { $0.key == BookRow.key(word) }
    }
}
