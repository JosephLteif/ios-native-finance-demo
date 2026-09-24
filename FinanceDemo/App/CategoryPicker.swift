import SwiftUI

struct CategoryPickerContent: View {
    let categories: [LedgerCategory]
    let includeUncategorized: Bool

    init(categories: [LedgerCategory], includeUncategorized: Bool = true) {
        self.categories = categories
        self.includeUncategorized = includeUncategorized
    }

    var body: some View {
        if includeUncategorized {
            Text("Uncategorized").tag(nil as UUID?)
        }

        ForEach(sections) { section in
            Section {
                ForEach(section.entries) { entry in
                    Text(entry.label)
                        .tag(Optional(entry.category.id))
                }
            } header: {
                Text(section.title)
            }
        }
    }

    private var sections: [CategoryPickerSection] {
        CategoryPickerSection.make(from: categories)
    }
}

private struct CategoryPickerSection: Identifiable {
    struct Entry: Identifiable {
        let category: LedgerCategory
        let depth: Int

        var id: UUID { category.id }

        var label: String {
            guard depth > 0 else { return category.name }
            return "\(String(repeating: "  ", count: depth))\(category.name)"
        }
    }

    let title: String
    let entries: [Entry]

    var id: UUID { entries[0].category.id }

    static func make(from categories: [LedgerCategory]) -> [CategoryPickerSection] {
        var uniqueCategories: [LedgerCategory] = []
        var seenIDs: Set<UUID> = []
        for category in categories where seenIDs.insert(category.id).inserted {
            uniqueCategories.append(category)
        }

        let categoriesByID = Dictionary(uniqueKeysWithValues: uniqueCategories.map { ($0.id, $0) })
        let childrenByParentID = Dictionary(grouping: uniqueCategories) { $0.parentID }
        let roots = uniqueCategories.filter { category in
            guard let parentID = category.parentID else { return true }
            return categoriesByID[parentID] == nil
        }

        return sorted(roots).map { root in
            var entries: [Entry] = []
            var visited: Set<UUID> = []

            append(
                root,
                depth: 0,
                childrenByParentID: childrenByParentID,
                entries: &entries,
                visited: &visited
            )

            return CategoryPickerSection(title: root.name, entries: entries)
        }
    }

    private static func append(
        _ category: LedgerCategory,
        depth: Int,
        childrenByParentID: [UUID?: [LedgerCategory]],
        entries: inout [Entry],
        visited: inout Set<UUID>
    ) {
        guard visited.insert(category.id).inserted else { return }
        entries.append(Entry(category: category, depth: depth))

        for child in sorted(childrenByParentID[category.id] ?? []) {
            append(
                child,
                depth: depth + 1,
                childrenByParentID: childrenByParentID,
                entries: &entries,
                visited: &visited
            )
        }
    }

    private static func sorted(_ categories: [LedgerCategory]) -> [LedgerCategory] {
        categories.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame
                ? $0.id.uuidString < $1.id.uuidString
                : comparison == .orderedAscending
        }
    }
}
