import SwiftUI

// MARK: - 메인 관리 시트

struct CategoryManagementSheet: View {
    @ObservedObject private var store: CategoryStore = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var editingCategory: TimerCategory? = nil
    @State private var showAddEditor = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.categories) { cat in
                    CategoryRow(category: cat) { editingCategory = cat }
                }
                .onDelete { store.delete(at: $0) }
            }
            .navigationTitle("카테고리 관리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddEditor = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editingCategory) { cat in
            CategoryEditorSheet(category: cat)
        }
        .sheet(isPresented: $showAddEditor) {
            CategoryEditorSheet(category: nil)
        }
    }
}

// MARK: - 목록 행

private struct CategoryRow: View {
    let category: TimerCategory
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 14) {
                Circle()
                    .fill(category.color)
                    .frame(width: 24, height: 24)
                Text(category.name)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 추가 / 편집 시트

struct CategoryEditorSheet: View {
    let category: TimerCategory?

    @ObservedObject private var store: CategoryStore = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var pickedColor: Color = Color(hex: "#FF9500") ?? .orange

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("이름") {
                    TextField("카테고리 이름", text: $name)
                }
                Section("색상") {
                    ColorPicker("색상 선택", selection: $pickedColor, supportsOpacity: false)
                }
            }
            .navigationTitle(category == nil ? "새 카테고리" : "카테고리 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save(); dismiss() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            if let cat = category {
                name = cat.name
                pickedColor = cat.color
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let hex = pickedColor.toHex()
        if let existing = category {
            store.update(TimerCategory(id: existing.id, name: trimmed, colorHex: hex))
        } else {
            store.add(TimerCategory(name: trimmed, colorHex: hex))
        }
    }
}
