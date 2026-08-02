import SwiftUI

struct TabBarView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(browser.tabs) { tab in
                    HStack(spacing: 6) {
                        Image(systemName: tab.isPinned ? "pin.fill" : "folder")
                            .foregroundStyle(.secondary)
                        Text(tab.title).lineLimit(1)
                        if browser.tabs.count > 1 && !tab.isPinned {
                            Button {
                                browser.closeTab(tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        tab.id == browser.activeTabID ? Color.accentColor.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { browser.selectTab(tab.id) }
                    .contextMenu {
                        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                            browser.togglePinnedTab(tab.id)
                        }
                        Button("Duplicate Tab") {
                            browser.duplicateTab(tab.id)
                        }
                        Divider()
                        Button("Close Tab") {
                            browser.closeTab(tab.id)
                        }
                        .disabled(tab.isPinned || browser.tabs.count == 1)
                    }
                }
                Button {
                    browser.newTab()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .padding(7)
                .help("New Tab")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(.bar)
        .simultaneousGesture(
            TapGesture().onEnded { browser.clearSelection() }
        )
    }
}
