import SwiftUI

struct CollectMediaView: View {
    @State private var viewModel = CollectMediaViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                sourceSection(viewModel: viewModel)
                optionsSection(viewModel: viewModel)
                progressSection(viewModel: viewModel)
                logSection(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: Binding(
            get: { viewModel.summary != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissSummary()
                }
            }
        )) {
            if let result = viewModel.summary {
                CollectMediaSummaryView(
                    result: result,
                    onOpenDestination: { viewModel.openDestination(result) },
                    onRevealReport: { viewModel.revealReport(result) },
                    onRevealMissing: { viewModel.revealMissing(result) }
                )
            }
        }
        .alert("Collect Media", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Collect Media", systemImage: "shippingbox")
                .font(.largeTitle.weight(.semibold))
            Text("Collect media referenced by Premiere FCP XML into a single destination, with optional smart relink and report generation.")
                .foregroundStyle(.secondary)
        }
    }

    private func sourceSection(viewModel: CollectMediaViewModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sources")
                .font(.headline)

            selectorRow(
                title: "Premiere FCP XML",
                value: viewModel.xmlURL?.path,
                buttonTitle: "Select XML",
                action: { viewModel.selectXML() }
            )

            selectorRow(
                title: "EDL (optional placeholder)",
                value: viewModel.edlURL?.path ?? "Not selected",
                buttonTitle: "Select EDL",
                action: { viewModel.selectEDL() }
            )

            selectorRow(
                title: "Destination Folder",
                value: viewModel.destinationURL?.path,
                buttonTitle: "Select Destination",
                action: { viewModel.selectDestination() }
            )

            HStack(alignment: .top, spacing: 16) {
                selectorRow(
                    title: "Search Root",
                    value: viewModel.options.searchRoot?.path ?? "Optional",
                    buttonTitle: "Select Search Root",
                    action: { viewModel.selectSearchRoot() }
                )
                if viewModel.options.searchRoot != nil {
                    Button("Clear") {
                        viewModel.clearSearchRoot()
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 26)
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private func optionsSection(viewModel: CollectMediaViewModel) -> some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 16) {
            Text("Options")
                .font(.headline)

            Toggle("Preserve folder structure", isOn: $viewModel.options.preserveStructure)
            Toggle("Skip duplicates", isOn: $viewModel.options.skipDuplicates)
            Toggle("Smart relink missing files using Search Root", isOn: $viewModel.options.smartRelink)
            Toggle("Use ffprobe for duration/timecode matching", isOn: $viewModel.options.useFFProbe)
                .disabled(!viewModel.ffProbeAvailable)

            Picker("Preserve mode", selection: $viewModel.options.preserveMode) {
                ForEach(CollectPreserveMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.options.preserveStructure)

            HStack {
                Stepper(value: $viewModel.options.tailN, in: 1...20) {
                    Text("Tail N folders: \(viewModel.options.tailN)")
                }
                .disabled(!viewModel.options.preserveStructure || viewModel.options.preserveMode != .tailN)

                Spacer()

                if !viewModel.ffProbeAvailable {
                    Label("ffprobe unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Collect") {
                    viewModel.startCollect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canCollect)

                Button("Stop") {
                    viewModel.stopCollect()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isCollecting)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private func progressSection(viewModel: CollectMediaViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Progress")
                .font(.headline)

            if viewModel.isCollecting, viewModel.progress.totalUnitCount > 0 {
                ProgressView(
                    value: Double(viewModel.progress.completedUnitCount),
                    total: Double(viewModel.progress.totalUnitCount)
                )
            } else if viewModel.isCollecting {
                ProgressView()
            }

            Text(viewModel.progress.message)
                .font(.subheadline)
            if let currentItem = viewModel.progress.currentItem, !currentItem.isEmpty {
                Text(currentItem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 12) {
                counterCard(title: "Found", value: viewModel.progress.counts.found)
                counterCard(title: "Copied", value: viewModel.progress.counts.copied)
                counterCard(title: "Missing", value: viewModel.progress.counts.missing)
                counterCard(title: "Skipped", value: viewModel.progress.counts.skipped)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private func logSection(viewModel: CollectMediaViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Log")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
            }
            .frame(minHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .padding(20)
        .background(cardBackground)
    }

    private func selectorRow(title: String, value: String?, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .top, spacing: 12) {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                Text(value ?? "Not selected")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private func counterCard(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.accentColor.opacity(0.05))
    }
}
