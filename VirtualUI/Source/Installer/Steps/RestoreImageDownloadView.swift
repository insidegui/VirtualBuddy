//
//  RestoreImageDownloadView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore

struct RestoreImageDownloadView: View {
    @ObservedObject var downloader: VBDownloader

    var body: some View {
        VStack {
            switch downloader.state {
            case .idle:
                Text("Preparing Download…")
            case .downloading(let progress, let eta):
                progressBar(progress, eta: eta)
            case .done:
                Text("Done!")
            case .failed(let message):
                Text("The download failed: \(message)")
                    .foregroundColor(.red)
            }
        }
    }
    
    @ViewBuilder
    private func progressBar(_ progress: Double?, eta: Double?) -> some View {
        VStack {
            ProgressView(value: progress) { }
                .progressViewStyle(.linear)
                .labelsHidden()

            if let eta {
                Text(formattedETA(from: eta))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formattedETA(from eta: Double) -> String {
        let time = Int(eta)

        let seconds = time % 60
        let minutes = (time / 60) % 60
        let hours = (time / 3600)

        if hours >= 1 {
            return String(format: "%0.2d:%0.2d:%0.2d",hours,minutes,seconds)
        } else {
            return String(format: "%0.2d:%0.2d",minutes,seconds)
        }

    }
}
