import SwiftUI

/// One Mac: what it has, and what can be done with it.
struct MacSettingsView: View {
    @ObservedObject private var machines = Machines.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mac: VirtualMac
    @State private var confirmDelete = false
    @State private var movingExport = false
    @State private var confirmExpand = false
    @State private var expansionResult: String?
    @State private var targetGiB: Int
    @AppStorage("henge.cpus") private var cpus = 4

    init(mac: VirtualMac) {
        _mac = State(initialValue: mac)
        _targetGiB = State(initialValue: [128, 256, 512].first(where: { (Int64($0) << 30) > mac.diskBytes }) ?? 512)
    }

    private var biggerCapacities: [Int] {
        [128, 256, 512].filter { (Int64($0) << 30) > mac.diskBytes }
    }

    private var iPadAvailable: Int64? {
        (try? mac.disk.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                DeskHeading("Name")
                TextField("Name", text: $mac.name)
                    .font(.system(size: 16))
                    .submitLabel(.done)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 14)
                    .deskCard()
                    .onSubmit(save)

                DeskHeading("Memory")
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(mac.ramMB / 1024) GB").font(.system(size: 26, weight: .bold))
                        Spacer()
                        Text(Entitlements.increasedMemory ? "Outside the app's limit once JIT is on" : "Used from free storage if needed")
                            .font(.system(size: 13)).foregroundStyle(Desk.dim).multilineTextAlignment(.trailing)
                    }
                    Picker("Memory", selection: Binding(get: { mac.ramMB / 1024 }, set: { mac.ramMB = $0 * 1024; save() })) {
                        ForEach([4, 6, 8], id: \.self) { Text("\($0) GB").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(17)
                .deskCard()

                DeskHeading("Processors")
                Stepper(value: $cpus, in: 1...6) {
                    HStack {
                        Text("CPUs").font(.system(size: 16))
                        Spacer()
                        Text("\(cpus)").font(.system(size: 16, weight: .semibold))
                    }
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 10)
                .deskCard()

                if Device.fittingScreen.height != 1080 {
                    DeskHeading("Screen")
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Screen", selection: Binding(get: { mac.screen.height == 1080 }, set: { wide in
                            (mac.screenWidth, mac.screenHeight) = wide ? (1920, 1080) : Device.fittingScreen
                            save()
                        })) {
                            Text("Fit this \(Device.name)").tag(false)
                            Text("16:9").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Text("\(mac.screen.width) × \(mac.screen.height). Changes apply the next time this Mac starts.")
                            .font(.system(size: 13)).foregroundStyle(Desk.dim)
                    }
                    .padding(17)
                    .deskCard()
                }

                DeskHeading("Storage")
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Virtual disk capacity").font(.system(size: 16))
                        Spacer()
                        Text(ByteText.string(UInt64(max(mac.diskBytes, 0))))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    HStack {
                        Text("VM image on iPad").font(.system(size: 14)).foregroundStyle(Desk.dim)
                        Spacer()
                        Text(ByteText.string(UInt64(max(mac.bytesUsed, 0))))
                            .font(.system(size: 14)).foregroundStyle(Desk.dim)
                    }
                    if let available = iPadAvailable, available >= 0 {
                        HStack {
                            Text("Free iPad storage").font(.system(size: 14)).foregroundStyle(Desk.dim)
                            Spacer()
                            Text(ByteText.string(UInt64(available)))
                                .font(.system(size: 14)).foregroundStyle(Desk.dim)
                        }
                    }
                    Text("This is a sparse image: the virtual capacity is a limit, not preallocated iPad storage. macOS free space is different; check it inside the Mac.")
                        .font(.system(size: 13)).foregroundStyle(Desk.dim)

                    if !biggerCapacities.isEmpty {
                        Divider().overlay(Desk.hairline)
                        Picker("Expand to", selection: $targetGiB) {
                            ForEach(biggerCapacities, id: \.self) { size in
                                Text("\(size) GiB").tag(size)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("Shut down macOS fully before expanding. An external backup is recommended but optional; resizing a disk or its partitions can risk data loss.")
                            .font(.system(size: 13)).foregroundStyle(Desk.warn)
                        Button("Expand virtual disk") { confirmExpand = true }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Desk.accentLight)
                            .disabled(henge_vm_state() != 0 || machines.exporting != nil || machines.importing != nil || Installer.shared.busy)
                        Text("Only the disk image grows here. macOS GPT partitions and APFS must be expanded separately after boot; no existing data is intentionally rewritten.")
                            .font(.system(size: 13)).foregroundStyle(Desk.dim)
                    }
                    if let expansionResult {
                        Text(expansionResult)
                            .font(.system(size: 13)).foregroundStyle(Desk.good)
                    }
                }
                .padding(17)
                .deskCard()

                DeskHeading("Manage")
                manage
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .deskColumn()
        }
        .background(Desk.page)
        .navigationTitle(mac.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: save)
        .fileMover(isPresented: $movingExport, file: machines.lastExport) { result in
            switch result {
            case .success: machines.lastExport = nil
            case .failure(let error): machines.lastError = error.localizedDescription
            }
        }
        .confirmationDialog("Expand \(mac.name)'s virtual disk?", isPresented: $confirmExpand, titleVisibility: .visible) {
            Button("Expand to \(targetGiB) GiB") {
                do {
                    mac = try machines.expandDisk(mac.id, toGiB: targetGiB)
                    expansionResult = "Disk image expanded to \(targetGiB) GiB. Quit and reopen Henge, then expand the partition and APFS container inside macOS; the new space is NOT yet usable by macOS."
                    targetGiB = biggerCapacities.first ?? targetGiB
                } catch {
                    machines.lastError = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No backup is required to proceed, but continuing without one risks permanent data loss if the disk or partition update fails. This only grows the offline sparse image. The guest GPT partition map and APFS container still require separate expansion.")
        }
        .confirmationDialog("Delete \(mac.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                machines.delete(mac.id)
                dismiss()
            }
        } message: {
            Text("Its disk is removed from this \(Device.name).")
        }
    }

    private var manage: some View {
        VStack(spacing: 0) {
            if let name = machines.exporting {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Exporting \(name)… keep Henge open").font(.system(size: 15))
                    DeskBar(fraction: machines.exported)
                }
                .padding(17)
            } else {
                row("Export", symbol: "square.and.arrow.up", tint: Desk.accentLight) { machines.export(mac) }
            }
            if let folder = machines.lastExport {
                divider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved in Files, under Henge, Exports, \(folder.lastPathComponent). Deleting Henge deletes it too, so move it somewhere else first.")
                        .font(.system(size: 13)).foregroundStyle(Desk.dim)
                    Button("Move Out of Henge…") { movingExport = true }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Desk.accentLight)
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            divider
            row("Delete this Mac", symbol: nil, tint: Desk.bad) { confirmDelete = true }
        }
        .deskCard()
    }

    private var divider: some View { Rectangle().fill(Desk.hairline).frame(height: 0.5) }

    private func row(_ title: String, symbol: String?, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 16)).foregroundStyle(tint)
                Spacer()
                if let symbol { Image(systemName: symbol).foregroundStyle(tint) }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }

    private func save() {
        if mac.name.isEmpty { mac.name = "Mac" }
        machines.update(mac)
    }
}
