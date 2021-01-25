//
//  PdfDocumentExporter.swift
//  Zotero
//
//  Created by Michal Rentka on 25.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

#if PDFENABLED

import PSPDFKit

struct PdfDocumentExporter {
    enum Error: Swift.Error {
        case filenameMissing
        case fileError(Swift.Error)
        case pdfError(Swift.Error)
    }

    static func export(annotations: [PSPDFKit.Annotation], key: String, libraryId: LibraryIdentifier, url: URL,
                       fileStorage: FileStorage, dbStorage: DbStorage, completed: @escaping (Result<File, Error>) -> Void) {
        // Load proper filename for pdf
        guard let filename = try? dbStorage.createCoordinator().perform(request: ReadFilenameDbRequest(libraryId: libraryId, key: key)) else {
            completed(.failure(.filenameMissing))
            return
        }

        let toFile = Files.pdfToShare(filename: filename, key: key)

        do {
            // Create a copy of current pdf
            let fromFile = Files.file(from: url)
            try fileStorage.copy(from: fromFile, to: toFile)
        } catch let error {
            completed(.failure(.fileError(error)))
            return
        }

        // Create a PSPDFKit document and import all zotero annotations
        let document = Document(url: toFile.createUrl())
        document.add(annotations: annotations, options: nil)

        document.save { result in
            inMainThread {
                switch result {
                case .success: completed(.success(toFile))
                case .failure(let error): completed(.failure(.pdfError(error)))
                }
            }
        }
    }
}

#endif
