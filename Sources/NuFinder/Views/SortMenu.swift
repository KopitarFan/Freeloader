import SwiftUI

struct SortMenu: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        Menu {
            ForEach(Array(browser.sortCriteria.enumerated()), id: \.element.id) { index, criterion in
                Menu("\(index + 1). \(criterion.field.rawValue)") {
                    Picker("Field", selection: fieldBinding(index)) {
                        ForEach(SortField.allCases) { field in
                            Text(field.rawValue).tag(field)
                        }
                    }
                    Divider()
                    Button(criterion.ascending ? "Descending" : "Ascending") {
                        browser.sortCriteria[index].ascending.toggle()
                        browser.sortedAgain()
                    }
                    if browser.sortCriteria.count > 1 {
                        Button("Remove Criterion", role: .destructive) {
                            browser.sortCriteria.remove(at: index)
                            browser.sortedAgain()
                        }
                    }
                }
            }
            Divider()
            Menu("Add Criterion") {
                ForEach(SortField.allCases) { field in
                    Button(field.rawValue) {
                        browser.sortCriteria.append(SortCriterion(field: field, ascending: true))
                        browser.sortedAgain()
                    }
                    .disabled(browser.sortCriteria.contains { $0.field == field })
                }
            }
        } label: {
            FreeloaderToolbarIcon(
                systemName: "arrow.up.arrow.down",
                isActive: browser.sortCriteria.count > 1
            )
        }
        .help("Multi-Criteria Sort")
    }

    private func fieldBinding(_ index: Int) -> Binding<SortField> {
        Binding(
            get: { browser.sortCriteria[index].field },
            set: {
                browser.sortCriteria[index].field = $0
                browser.sortedAgain()
            }
        )
    }
}
