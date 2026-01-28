import SwiftUI

struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDismiss)
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
