import SwiftUI

struct AddressBarRow: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "location")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                AddressBarView()
                    .frame(maxWidth: .infinity)
                Button {
                    browser.navigateFromAddress()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Go to Path")
            }
            BreadcrumbView()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
