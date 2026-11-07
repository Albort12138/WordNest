import AppKit
import Carbon

/// Use the Notes object interface, never simulated clicks or the private Notes database.
/// Run synchronous scripts inside an actor to serialize this process without blocking the AppKit main thread.
actor AppleNotesClient: NotesSaving {
    // Inject the system boundary and journal directory so regressions can replay Notes errors without user notes or journals.
    private let transport: ((String, [String]) throws -> NSAppleEventDescriptor)?
    let writeJournal: NotesWriteJournal

    init(journal: NotesWriteJournal = NotesWriteJournal(),
         transport: ((String, [String]) throws -> NSAppleEventDescriptor)? = nil) {
        self.writeJournal = journal
        self.transport = transport
    }

    static let scriptSource = #"""
    on folderRows(parentObject, parentPath)
        set rows to {}
        tell application id "com.apple.Notes"
            repeat with f in (get folders of parentObject)
                set folderPath to parentPath & (name of f as text)
                set isShared to false
                try
                    set isShared to shared of f
                end try
                if not isShared then
                    set end of rows to {id of f as text, folderPath}
                    set rows to rows & my folderRows(f, folderPath & " / ")
                end if
            end repeat
        end tell
        return rows
    end folderRows

    on listTargets()
        with timeout of 20 seconds
            set rows to {}
            tell application id "com.apple.Notes"
                repeat with a in (get accounts)
                    set end of rows to {id of a as text, name of a as text, my folderRows(a, "")}
                end repeat
            end tell
            return rows
        end timeout
    end listTargets

    on findFolder(parentObject, folderKey)
        tell application id "com.apple.Notes"
            repeat with f in (get folders of parentObject)
                if (id of f as text) is folderKey then return contents of f
                set nested to my findFolder(f, folderKey)
                if nested is not missing value then return nested
            end repeat
        end tell
        return missing value
    end findFolder

    on targetFolder(accountKey, folderKey)
        tell application id "com.apple.Notes"
            set matches to accounts whose id is accountKey
            if (count of matches) is not 1 then error "The selected Notes account does not exist." number -2701
            set f to my findFolder(item 1 of matches, folderKey)
            if f is missing value then error "The selected Notes folder does not exist." number -2701
            if shared of f then error "Choose a folder that is not shared." number -2702
            return f
        end tell
    end targetFolder

    on createFolder(accountKey)
        with timeout of 20 seconds
            tell application id "com.apple.Notes"
                set matches to accounts whose id is accountKey
                if (count of matches) is not 1 then error "The selected Notes account does not exist." number -2701
                set a to item 1 of matches
                set candidates to folders of a whose name is \#(LegacyNotesText.appleScriptLiteral("Default vocabulary folder"))
                if (count of candidates) > 1 then error "Multiple folders have the same name. Choose one manually." number -2702
                if (count of candidates) is 1 then
                    set f to item 1 of candidates
                else
                    set f to make new folder at a with properties {name:\#(LegacyNotesText.appleScriptLiteral("Default vocabulary folder"))}
                end if
                if shared of f then error "Choose a folder that is not shared." number -2702
                return {id of f as text, name of f as text}
            end tell
        end timeout
    end createFolder

    on findSaved(accountKey, folderKey, entryMarker)
        with timeout of 20 seconds
            set f to my targetFolder(accountKey, folderKey)
            tell application id "com.apple.Notes"
                set matches to notes of f whose plaintext contains entryMarker
                if (count of matches) > 1 then error "Multiple notes have the same collection identifier. Inspect them in Notes." number -2702
                if (count of matches) is 0 then return ""
                return id of item 1 of matches as text
            end tell
        end timeout
    end findSaved

    on readSaved(accountKey, folderKey, noteKey)
        with timeout of 20 seconds
            set f to my targetFolder(accountKey, folderKey)
            tell application id "com.apple.Notes"
                set matches to notes of f whose id is noteKey
                if (count of matches) is not 1 then error "The note left the selected folder during reconciliation." number -2703
                return plaintext of item 1 of matches as text
            end tell
        end timeout
    end readSaved

    on saveEntry(accountKey, folderKey, entryMarker, htmlText)
        set writingStarted to false
        try
            with timeout of 20 seconds
                set existingID to my findSaved(accountKey, folderKey, entryMarker)
                set f to my targetFolder(accountKey, folderKey)
                tell application id "com.apple.Notes"
                    if existingID is not "" then
                        set n to first note of f whose id is existingID
                        return {"saved", existingID, plaintext of n as text}
                    end if
                    set writingStarted to true
                    set n to make new note at f with properties {body:htmlText}
                    set noteKey to id of n as text
                    -- Creation alone does not prove completeness; read back body and destination before reporting success.
                    if (plaintext of n) does not contain entryMarker then error "The readback is missing the collection identifier." number -2703
                    if (id of container of n as text) is not folderKey then error "The readback is not in the selected folder." number -2703
                    return {"saved", noteKey, plaintext of n as text}
                end tell
            end timeout
        on error messageText number errorCode
            if writingStarted then return {"uncertain", messageText & " (" & errorCode & ")"}
            error messageText number errorCode
        end try
    end saveEntry
    """#

    /// Initialize only the scripting runtime, not Notes; warm it on the main thread when the user first connects.
    @MainActor static func prepare() {
        var error: NSDictionary?
        _ = NSAppleScript(source: "return 1")?.executeAndReturnError(&error)
    }

    /// Pass parameters as Apple Event string descriptors; never interpolate vocabulary or note bodies into script source.
    /// Test this pure constructor with quotes/newlines without requiring Notes permission.
    nonisolated static func event(handler: String, arguments: [String]) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: handler.lowercased()), forKeyword: AEKeyword(keyASSubroutineName))
        let list = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            list.insert(NSAppleEventDescriptor(string: argument), at: index + 1)
        }
        event.setParam(list, forKeyword: AEKeyword(keyDirectObject))
        return event
    }

    func call(_ handler: String, _ arguments: [String] = []) throws -> NSAppleEventDescriptor {
        if let transport { return try transport(handler, arguments) }
        guard let script = NSAppleScript(source: Self.scriptSource + "\n" + AlphabetNotesScript.source) else { throw NotesFailure.invalidResponse }
        var error: NSDictionary?
        let result = script.executeAppleEvent(Self.event(handler: handler, arguments: arguments), error: &error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
            if code == -1743 { throw NotesFailure.permissionDenied }
            if code == -2701 { throw NotesFailure.targetMissing }
            let message = error[NSAppleScript.errorMessage] as? String ?? L("The system did not provide error details")
            throw NotesFailure.automation(code, message)
        }
        return result
    }

    func targets() throws -> [NotesAccount] {
        let result = try call("listTargets")
        var accounts: [NotesAccount] = []
        for i in 1..<(result.numberOfItems + 1) {
            guard let row = result.atIndex(i), let id = row.atIndex(1)?.stringValue,
                  let name = row.atIndex(2)?.stringValue, let folders = row.atIndex(3) else { throw NotesFailure.invalidResponse }
            var destinations: [NotesDestination] = []
            var seen = Set<String>()
            for j in 1..<(folders.numberOfItems + 1) {
                guard let folder = folders.atIndex(j), let folderID = folder.atIndex(1)?.stringValue,
                      let folderName = folder.atIndex(2)?.stringValue else { throw NotesFailure.invalidResponse }
                if seen.insert(folderID).inserted {
                    destinations.append(NotesDestination(accountID: id, accountName: name, folderID: folderID, folderName: folderName))
                }
            }
            accounts.append(NotesAccount(id: id, name: name, folders: destinations))
        }
        return accounts
    }

    func createVocabularyFolder(in account: NotesAccount) throws -> NotesDestination {
        let row = try call("createFolder", [account.id])
        guard let id = row.atIndex(1)?.stringValue, let name = row.atIndex(2)?.stringValue else { throw NotesFailure.invalidResponse }
        return NotesDestination(accountID: account.id, accountName: account.name, folderID: id, folderName: name)
    }

    func save(_ entry: VocabularyEntry, to destination: NotesDestination) throws -> VocabularyReceipt {
        try saveAlphabet(entry, to: destination)
    }

    func find(_ entry: VocabularyEntry, in destination: NotesDestination) throws -> VocabularyReceipt? {
        try findAlphabet(entry, in: destination)
    }

    func legacySave(_ entry: VocabularyEntry, to destination: NotesDestination) throws -> VocabularyReceipt {
        let result: NSAppleEventDescriptor
        do {
            result = try call("saveEntry", [destination.accountID, destination.folderID, entry.marker, entry.notesHTML])
        } catch NotesFailure.automation(let code, let message) where code == -1712 {
            // An outer execution timeout may occur after a write; conservatively treat the outcome as unknown.
            throw NotesFailure.uncertain(message)
        }
        guard result.atIndex(1)?.stringValue == "saved",
              let id = result.atIndex(2)?.stringValue, !id.isEmpty,
              let readBack = result.atIndex(3)?.stringValue else {
            throw NotesFailure.uncertain(result.atIndex(2)?.stringValue ?? L("The system did not return a note identifier"))
        }
        // Notes may normalize paragraph breaks. Compare every field by paragraph; an ID alone is not proof of success.
        guard entry.isPresent(in: readBack) else {
            throw NotesFailure.uncertain(L("The note was created, but its readback does not fully match the submitted content."))
        }
        return VocabularyReceipt(noteID: id)
    }

    func legacyFind(_ entry: VocabularyEntry, in destination: NotesDestination) throws -> VocabularyReceipt? {
        guard let id = try call("findSaved", [destination.accountID, destination.folderID, entry.marker]).stringValue else { throw NotesFailure.invalidResponse }
        if id.isEmpty { return nil }
        guard let readBack = try call("readSaved", [destination.accountID, destination.folderID, id]).stringValue,
              entry.isPresent(in: readBack) else {
            throw NotesFailure.uncertain(L("The matching note was found, but its content is incomplete or changed. Inspect it in Notes."))
        }
        return VocabularyReceipt(noteID: id)
    }
}
