//
//  FileMonitor.swift
//  Zotero
//
//  Created by Michal Rentka on 01.02.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

final class FileMonitor {
    private let url: URL
    private let fileHandle: FileHandle
    private let source: DispatchSourceFileSystemObject

    let observable: PublishSubject<Data>

    init(url: URL) throws {
        let fileHandle = try FileHandle(forReadingFrom: url)
        self.url = url
        self.fileHandle = fileHandle
        self.source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileHandle.fileDescriptor, eventMask: .extend, queue: .main)
        self.observable = PublishSubject()

        self.source.setEventHandler { [weak self] in
            guard let `self` = self else { return }
            self.process(event: self.source.data)
        }

        self.source.setCancelHandler { [weak self] in
            try? self?.fileHandle.close()
        }

        self.fileHandle.seekToEndOfFile()
        self.source.resume()
    }

    deinit {
        self.source.cancel()
    }

    func process(event: DispatchSource.FileSystemEvent) {
        guard event.contains(.extend) else { return }
        let newData = self.fileHandle.readDataToEndOfFile()
        self.observable.on(.next(newData))
    }
}
