import SwiftUI

// MARK: - Universal Swipe Actions Modifier

/// A reusable swipe actions modifier for list items with standard edit and delete actions
struct StandardSwipeActions: ViewModifier {
    var onDelete: () -> Void
    var onEdit: (() -> Void)?
    var allowsFullSwipe: Bool = false
    var editButtonColor: Color? = Color.orangeWarm

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                if let onEdit = onEdit {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(editButtonColor)
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Adds standard swipe actions (delete and optionally edit) to a list item
    func standardSwipeActions(
        onDelete: @escaping () -> Void,
        onEdit: (() -> Void)? = nil,
        allowsFullSwipe: Bool = false
    ) -> some View {
        self.modifier(StandardSwipeActions(
            onDelete: onDelete,
            onEdit: onEdit,
            allowsFullSwipe: allowsFullSwipe
        ))
    }

    /// Adds delete-only swipe action
    func deleteSwipeAction(
        allowsFullSwipe: Bool = true,
        onDelete: @escaping () -> Void
    ) -> some View {
        self.swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Context Menu Modifier

struct StandardContextMenu: ViewModifier {
    var onEdit: (() -> Void)?
    var onDelete: () -> Void
    var additionalActions: [MenuAction] = []

    struct MenuAction: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let role: ButtonRole?
        let action: () -> Void

        init(title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.role = role
            self.action = action
        }
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let onEdit = onEdit {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }

                ForEach(additionalActions) { action in
                    if let role = action.role {
                        Button(role: role) {
                            action.action()
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    } else {
                        Button {
                            action.action()
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

// MARK: - Context Menu View Extension

extension View {
    /// Adds a standard context menu with edit and delete options
    func standardContextMenu(
        onEdit: (() -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) -> some View {
        self.modifier(StandardContextMenu(
            onEdit: onEdit,
            onDelete: onDelete
        ))
    }

    /// Adds a customizable context menu
    func customizableContextMenu(
        onEdit: (() -> Void)? = nil,
        onDelete: @escaping () -> Void,
        additionalActions: [StandardContextMenu.MenuAction] = []
    ) -> some View {
        self.modifier(StandardContextMenu(
            onEdit: onEdit,
            onDelete: onDelete,
            additionalActions: additionalActions
        ))
    }
}
