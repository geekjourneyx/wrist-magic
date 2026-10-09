import SwiftUI
import UIKit

struct SharePresenter: UIViewControllerRepresentable {
  let url: URL
  let completed: @MainActor () -> Void
  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    controller.completionWithItemsHandler = { @Sendable _, _, _, _ in
      Task { @MainActor in completed() }
    }
    return controller
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
