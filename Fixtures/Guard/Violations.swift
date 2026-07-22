import SwiftUI
import UIKit

struct FixtureView: View {
    let title: String

    var body: some View {
        Text(title)
            .navigationTitle(title)
    }
}

func configure(_ label: UILabel, title: String) {
    label.text = title
}
