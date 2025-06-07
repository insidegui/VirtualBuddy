//
//  RestoreImageDownloadView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore
import Combine

struct RestoreImageDownloadView: View {
    @EnvironmentObject var viewModel: VMInstallationViewModel

    private var progress: Double? {
        switch viewModel.downloadState {
        case .idle: 0
        case .failed: nil
        case .downloading(let progress, _): progress ?? 0
        case .done: 1
        }
    }

    private var status: Text {
        switch viewModel.downloadState {
        case .idle: Text("Preparing Download")
        case .downloading(_, let eta): eta.flatMap { Text(formattedETA(from: $0)) } ?? Text("Downloading")
        case .done: Text("Done!")
        case .failed(let message): Text("Download failed: \(message)")
        }
    }

    private var style: VirtualBuddyMonoStyle {
        switch viewModel.downloadState {
        case .idle, .downloading: .default
        case .failed: .failure
        case .done: .success
        }
    }

    var body: some View {
        VirtualBuddyMonoProgressView(
            progress: progress,
            status: status,
            style: style
        )
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

#if DEBUG
#Preview {
    VMInstallationWizard.preview(step: .download)
}
#endif
