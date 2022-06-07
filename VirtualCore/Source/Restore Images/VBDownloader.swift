//
//  VBDownloader.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 07/06/22.
//

import Foundation

public final class VBDownloader: NSObject {

    let library: VMLibraryController

    public init(with library: VMLibraryController) {
        self.library = library
    }

    private var downloadTask: Task<Void, Error>?

    public enum State: Hashable {
        case idle
        case downloading(_ progress: Double?, _ eta: Double?)
        case failed(_ error: String)
        case done(_ localURL: URL)
    }

    private var isInFailedState: Bool {
        guard case .failed = state else { return false }
        return true
    }

    @Published
    public private(set) var state = State.idle

    @MainActor
    private func getDownloadsBaseURL() throws -> URL {
        let baseURL = library.libraryURL.appendingPathComponent("_Downloads")
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }

        return baseURL
    }

    @MainActor
    public func startDownload(with url: URL) {
        resetProgress()

        state = .downloading(nil, nil)

        let filename = url.lastPathComponent
        guard let destinationURL = (try? getDownloadsBaseURL())?.appendingPathComponent(filename) else {
            state = .failed("Failed to create directory for downloads at \(library.libraryURL.path)")
            return
        }

        downloadTask = Task {
            do {
                let (localURL, response) = try await URLSession.shared.download(from: url, delegate: self)

                guard !isInFailedState else { return }

                let code = (response as! HTTPURLResponse).statusCode

                guard code == 200 else {
                    state = .failed("HTTP \(code)")
                    return
                }

                try FileManager.default.moveItem(at: localURL, to: destinationURL)

                state = .done(destinationURL)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    @MainActor
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    private let minElapsedProgressForETA: Double = 0.03
    private var elapsedTime: Double = 0
    private var ppsObservations: [Double] = []
    private let ppsObservationsLimit = 500
    private var ppsAverage: Double {
        guard !ppsObservations.isEmpty else { return -1 }
        return ppsObservations.reduce(Double(0), +) / Double(ppsObservations.count)
    }

    private var pps: Double = -1

    private var eta: Double = -1

    private var lastProgressDate = Date()

    private var progress: Double = 0

    private func resetProgress() {
        elapsedTime = 0
        eta = -1
        pps = -1
        ppsObservations = []
    }

}

extension VBDownloader: URLSessionTaskDelegate, URLSessionDownloadDelegate {

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        if request.url?.absoluteString.lowercased().contains("unauthorized") == true {
            DispatchQueue.main.async {
                self.state = .failed("The download failed due to missing authentication credentials. To fix this, visit the developer portal downloads page, then come back here and try again.")
            }
            return nil
        } else {
            return request
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {

    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async { [self] in
            let interval = Date().timeIntervalSince(lastProgressDate)
            lastProgressDate = Date()

            let percent = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

            updateProgress(with: percent, interval: interval)
        }
    }

    private func updateProgress(with progress: Double, interval: Double) {
        let currentPPS = progress / elapsedTime

        if currentPPS.isFinite && !currentPPS.isZero && !currentPPS.isNaN {
            ppsObservations.append(currentPPS)
            if ppsObservations.count >= ppsObservationsLimit {
                ppsObservations.removeFirst()
            }
        }

        elapsedTime += interval

        if self.progress > self.minElapsedProgressForETA {
            if pps < 0 {
                pps = progress / elapsedTime
            }

            eta = (1/ppsAverage) - elapsedTime

            self.state = .downloading(progress, eta)
        } else {
            self.state = .downloading(progress, nil)
        }
    }

}
