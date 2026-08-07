import SwiftUI

struct SearchSidebarView: View {
    @Bindable var model: BrowseViewModel
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FocusState private var searchFocused: Bool

    @State private var showSaveDialog = false
    @State private var saveSetName = ""
    @State private var showSavedSetsSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchInputSection
                .padding()

            Divider()

            sidebarTagsScrollArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .toolbar {
#if os(iOS)
            if horizontalSizeClass == .compact {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        preferredCompactColumn = .detail
                    } label: {
                        Label("Posts", systemImage: "photo.on.rectangle.angled")
                    }
                }
            }
#endif
        }
        .sheet(isPresented: $showSavedSetsSheet) {
            SavedTagSetsSheet(model: model)
        }
        .alert("Save Tag Set", isPresented: $showSaveDialog) {
            TextField("Name", text: $saveSetName)
            Button("Save") {
                model.saveCurrentTagSet(named: saveSetName)
                saveSetName = ""
            }
            Button("Cancel", role: .cancel) {
                saveSetName = ""
            }
        } message: {
            Text("Save the current \(model.tagQuery.tags.count) tags as a preset.")
        }
    }

    private var searchInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    TextField("Add tag…", text: $model.inputFragment)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFocused)
                        .onSubmit {
                            Task { await model.commitInput() }
                        }
                        .onChange(of: model.inputFragment) { _, newValue in
                            model.onInputChanged(newValue)
                        }
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.none)
                        .keyboardType(.asciiCapable)
#endif

                    Button("Add") {
                        Task { await model.commitInput() }
                    }
                    .disabled(model.inputFragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if model.isSearchingSuggestions {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 8)
                } else if !model.suggestions.isEmpty {
                    List {
                        ForEach(model.suggestions) { tag in
                            Button {
                                Task { await model.addTag(tag.name) }
                            } label: {
                                TagSuggestionRow(tag: tag)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: 200)
                    .padding(.top, 4)
                }
            }

            searchSummaryRow
        }
    }

    private var sidebarTagsScrollArea: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    selectedTagsSectionBody
                        .padding(.horizontal)
                } header: {
                    selectedTagsSectionHeader
                        .padding(.horizontal)
                }

                Section {
                    pageTagsSectionBody
                        .padding(.horizontal)
                } header: {
                    pageTagsSectionHeader
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
#if os(iOS)
        .scrollDismissesKeyboard(.interactively)
#endif
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(CompactSidebarDismissGesture(preferredCompactColumn: $preferredCompactColumn))
    }

    private var selectedTagsSectionHeader: some View {
        VStack(spacing: 0) {
            searchHeader
                .padding(.vertical, 8)

            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
    }

    private var pageTagsSectionHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Tags on this page")
                    .font(.headline)

                if model.isResolvingPageTagColors {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if !model.pageTags.isEmpty {
                    Text("\(model.pageTags.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)

            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
    }

    @ViewBuilder
    private var selectedTagsSectionBody: some View {
        if model.tagQuery.tags.isEmpty {
            Text("No tags selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
        } else {
            TagChipFlow(model: model) { tag in
                Task { await model.removeTag(tag) }
            }
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var pageTagsSectionBody: some View {
        if model.pageTags.isEmpty {
            Text(model.isLoading ? "Loading…" : "No tags yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.pageTagGroups) { group in
                    PageTagGroupSection(group: group) { tag in
                        Task { await model.addTag(tag.name) }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Text("Selected Tags")
                .font(.headline)

            Spacer()

            Button {
                Task { await model.clearTags() }
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.medium))
            }
            .buttonStyle(.plain)
            .disabled(model.tagQuery.isEmpty)
            .help("Clear selected tags")

            Button {
                saveSetName = defaultSaveName()
                showSaveDialog = true
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.title3.weight(.medium))
            }
            .buttonStyle(.plain)
            .disabled(model.tagQuery.isEmpty)
            .help("Save current tags")

            Button {
                showSavedSetsSheet = true
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title3.weight(.medium))
            }
            .buttonStyle(.plain)
            .help("Saved tag sets")
        }
    }

    private var summaryLabel: String {
        model.tagQuery.searchString.isEmpty ? "All posts" : model.tagQuery.searchString
    }

    private var searchSummaryRow: some View {
        HStack {
            Spacer()

            if !model.tagQuery.isEmpty {
                Text(summaryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func defaultSaveName() -> String {
        let tags = model.tagQuery.tags
        guard !tags.isEmpty else { return "" }
        if tags.count <= 2 {
            return tags.joined(separator: " ")
        }
        return "\(tags.prefix(2).joined(separator: " ")) +\(tags.count - 2)"
    }
}

private struct TagChipFlow: View {
    @Bindable var model: BrowseViewModel
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(model.tagQuery.tags, id: \.self) { tag in
                TagChip(
                    text: tag,
                    style: .page,
                    tint: model.tagType(for: tag).color
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    onRemove(tag)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            model.resolveTagNames(model.tagQuery.tags)
        }
        .onChange(of: model.tagQuery.tags) { _, tags in
            model.resolveTagNames(tags)
        }
    }
}

private struct PageTagGroupSection: View {
    let group: BooruTagGroup
    let onAdd: (BooruTag) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.type.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(group.type.color)
                .padding(.top, 2)

            FlowLayout(spacing: 7) {
                ForEach(group.tags) { tag in
                    Button {
                        onAdd(tag)
                    } label: {
                        TagChip(
                            text: tag.name,
                            style: .page,
                            tint: tag.type.color,
                            count: tag.postCount
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    @Previewable @State var column: NavigationSplitViewColumn = .sidebar

    NavigationStack {
        SearchSidebarView(
            model: BrowseViewModel(site: BooruSiteFactory.previewSite),
            preferredCompactColumn: $column
        )
        .navigationTitle("yande.re")
    }
}
