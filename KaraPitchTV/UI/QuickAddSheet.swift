import SwiftUI

/// Who's singing and in which key, with as few remote presses as possible: Select on a singer,
/// Select on Add. "New name" opens the keyboard for a singer who isn't in the list yet.
struct QuickAddSheet: View {
    let result: SearchResult
    let singers: [String]
    /// A name typed with "New name", so the session can offer it again later.
    let onNewName: (String) -> Void
    let onAdd: (_ singer: String, _ key: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var singer = ""
    /// Names typed in this sheet, shown first so the new one is easy to see and pick again.
    @State private var typed: [String] = []
    @State private var draft = ""
    @State private var key = 0
    @State private var adding = false

    private enum Focus: Hashable { case singer(String), newName, key, add }
    @FocusState private var focus: Focus?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ADD TO QUEUE").font(.system(size: 28, weight: .bold)).kerning(4).foregroundStyle(Theme.pink)
            Text(result.title).font(.system(size: 44, weight: .bold)).foregroundStyle(Theme.text).lineLimit(2).padding(.top, 12)

            Text("Who's singing?").font(.system(size: 30)).foregroundStyle(Theme.textDim).padding(.top, 48)
            ScrollView(.horizontal) {
                HStack(spacing: 24) {
                    ForEach(names + [""], id: \.self) { name in
                        Button {
                            singer = name
                            focus = .add
                        } label: {
                            Text(name.isEmpty ? "No name" : name)
                                .padding(.horizontal, 8)
                                .overlay(alignment: .bottom) {
                                    if singer == name { Capsule().fill(Theme.pink).frame(height: 4).offset(y: 12) }
                                }
                        }
                        .focused($focus, equals: .singer(name))
                    }
                    // Select opens the tvOS keyboard; submitting picks the name.
                    TextField("New name", text: $draft)
                        .frame(width: 360)
                        .submitLabel(.done)
                        .onSubmit(saveDraft)
                        .focused($focus, equals: .newName)
                }
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()

            Text("Key").font(.system(size: 30)).foregroundStyle(Theme.textDim).padding(.top, 24)
            KeyStepper(key: $key, isFocused: focus == .key)
                .focused($focus, equals: .key)
                .padding(.top, 16)

            HStack(spacing: 32) {
                Button(adding ? "Adding…" : "Add") {
                    adding = true
                    onAdd(singer, key)
                }
                .disabled(adding)
                .focused($focus, equals: .add)
                Button("Cancel", role: .cancel) { dismiss() }
            }
            .padding(.top, 56)
        }
        .padding(64)
        .frame(width: 1200, alignment: .leading)
        .defaultFocus($focus, .singer(singers.first ?? ""))
    }

    private var names: [String] {
        typed + singers.filter { !typed.contains($0) }
    }

    private func saveDraft() {
        let name = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(QueueStore.maxSinger))
        draft = ""
        guard !name.isEmpty else { return }
        typed.removeAll { $0 == name }
        typed.insert(name, at: 0)
        singer = name
        focus = .add
        onNewName(name)
    }
}

/// ◀ Key +2 ▶ — Left/Right change it while focused. It sits alone on its row, so those clicks
/// change the key instead of moving the focus.
private struct KeyStepper: View {
    @Binding var key: Int
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 32) {
            Image(systemName: "chevron.left").opacity(key > Key.range.lowerBound ? 1 : 0.25)
            Text(Key.label(key)).font(.system(size: 40, weight: .bold)).frame(minWidth: 280)
            Image(systemName: "chevron.right").opacity(key < Key.range.upperBound ? 1 : 0.25)
            if isFocused { Text("← → to change").font(.system(size: 26)).foregroundStyle(Theme.textDim) }
        }
        .font(.system(size: 36, weight: .bold))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .background(isFocused ? Theme.surfaceHigh : Theme.surface, in: Capsule())
        .overlay { if isFocused { Capsule().strokeBorder(Theme.accent, lineWidth: 4) } }
        .scaleEffect(isFocused ? 1.05 : 1)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left: key = Key.clamp(key - 1)
            case .right: key = Key.clamp(key + 1)
            default: break
            }
        }
    }
}
