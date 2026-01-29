import SwiftUI

// MARK: - Universal Form Navigation View

/// A reusable form container with standard navigation and toolbar setup
struct FormNavigationView<Content: View>: View {
    let title: String
    var showsCancelButton: Bool = true
    var showsDoneButton: Bool = false
    var showsSaveButton: Bool = false
    var isSaveDisabled: Bool = false
    var saveIcon: String? = nil
    var cancelAction: (() -> Void)?
    var saveAction: (() -> Void)?
    var doneAction: (() -> Void)?
    let content: Content

    init(
        title: String,
        showsCancelButton: Bool = true,
        showsDoneButton: Bool = false,
        showsSaveButton: Bool = false,
        isSaveDisabled: Bool = false,
        saveIcon: String? = nil,
        cancelAction: (() -> Void)? = nil,
        saveAction: (() -> Void)? = nil,
        doneAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.showsCancelButton = showsCancelButton
        self.showsDoneButton = showsDoneButton
        self.showsSaveButton = showsSaveButton
        self.isSaveDisabled = isSaveDisabled
        self.saveIcon = saveIcon
        self.cancelAction = cancelAction
        self.saveAction = saveAction
        self.doneAction = doneAction
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if showsCancelButton, let cancelAction = cancelAction {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    cancelAction()
                }
            }
        }

        if showsSaveButton, let saveAction = saveAction {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveAction()
                } label: {
                    if let icon = saveIcon {
                        Image(systemName: icon)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.primaryDefault)
                            .clipShape(Circle())
                    } else {
                        Text("Save")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isSaveDisabled)
            }
        }

        if showsDoneButton, let doneAction = doneAction {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    doneAction()
                }
            }
        }
    }
}

// MARK: - Editor Navigation View

/// Specialized form view for editors with cancel and checkmark save button
struct EditorNavigationView<Content: View>: View {
    let title: String
    var isSaving: Bool = false
    var isValid: Bool = true
    var onCancel: () -> Void
    var onSave: () -> Void
    let content: Content

    init(
        title: String,
        isSaving: Bool = false,
        isValid: Bool = true,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.isSaving = isSaving
        self.isValid = isValid
        self.onCancel = onCancel
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onCancel()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onSave()
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(isValid && !isSaving ? Color.primaryDefault : Color.secondary)
                                .clipShape(Circle())
                        }
                        .opacity(isValid && !isSaving ? 1.0 : 0.5)
                        .disabled(!isValid || isSaving)
                    }
                }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Wraps the view in a standard form navigation setup
    func formNavigation(
        title: String,
        showsCancelButton: Bool = true,
        showsDoneButton: Bool = false,
        cancelAction: (() -> Void)? = nil,
        doneAction: (() -> Void)? = nil
    ) -> some View {
        FormNavigationView(
            title: title,
            showsCancelButton: showsCancelButton,
            showsDoneButton: showsDoneButton,
            cancelAction: cancelAction,
            doneAction: doneAction
        ) {
            self
        }
    }
}
