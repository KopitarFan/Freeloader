import SwiftUI

struct AddressBarRow: View {
    @EnvironmentObject private var browser: BrowserModel
    var showsPaneNavigation = false

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                if showsPaneNavigation {
                    Menu {
                        ForEach(browser.backHistory.reversed(), id: \.self) { url in
                            Button(url.path) { browser.navigateToHistory(url) }
                        }
                    } label: {
                        paneNavigationIcon("chevron.left")
                    } primaryAction: {
                        browser.goBack()
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(!browser.canGoBack)
                    .help("Back; open the menu for history")

                    Menu {
                        ForEach(browser.forwardHistory.reversed(), id: \.self) { url in
                            Button(url.path) { browser.navigateToHistory(url) }
                        }
                    } label: {
                        paneNavigationIcon("chevron.right")
                    } primaryAction: {
                        browser.goForward()
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(!browser.canGoForward)
                    .help("Forward; open the menu for history")

                    Button {
                        browser.goUp()
                    } label: {
                        paneNavigationIcon("arrow.up")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .help("Parent Folder")
                }
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

    private func paneNavigationIcon(_ systemName: String) -> some View {
        FreeloaderToolbarIcon(systemName: systemName)
    }
}
