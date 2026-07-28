import Foundation

struct FileTemplate: Identifiable, Sendable {
    let name: String
    let suggestedFilename: String
    let contents: Data
    var id: String { name }
}

enum TemplateService {
    static let templates: [FileTemplate] = [
        FileTemplate(name: "Plain Text", suggestedFilename: "Untitled.txt", contents: Data()),
        FileTemplate(
            name: "Markdown",
            suggestedFilename: "README.md",
            contents: Data("# Title\n\n".utf8)
        ),
        FileTemplate(
            name: "Swift File",
            suggestedFilename: "Untitled.swift",
            contents: Data("import Foundation\n\n".utf8)
        ),
        FileTemplate(
            name: "JSON",
            suggestedFilename: "Untitled.json",
            contents: Data("{\n  \n}\n".utf8)
        )
    ]
}
