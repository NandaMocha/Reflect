import SwiftUI

enum ReflectionEditorMode: Equatable {
    case create
    case edit(Reflection)

    static func == (lhs: ReflectionEditorMode, rhs: ReflectionEditorMode) -> Bool {
        switch (lhs, rhs) {
        case (.create, .create): return true
        case let (.edit(r1), .edit(r2)): return r1.id == r2.id
        default: return false
        }
    }
}
