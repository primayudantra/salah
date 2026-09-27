import SalahCore
import SwiftUI

/// Manual location entry: city search (Apple geocoder) or coordinates. Works without location permission.
struct LocationSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable { case search = "Search city", coordinates = "Coordinates" }

    @State private var mode: Mode = .search
    @State private var query = ""
    @State private var results: [SavedLocation] = []
    @State private var searching = false
    @State private var error: String?

    @State private var name = ""
    @State private var lat = ""
    @State private var lon = ""
    @State private var tzID = TimeZone.current.identifier

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Location").font(.system(size: 17, weight: .semibold))
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .search { searchView } else { coordinatesView }

            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Palette.accent)
            }

            Divider()
            HStack {
                Button {
                    model.locationProvider.requestLocation()
                    dismiss()
                } label: { Label("Use my location", systemImage: "location") }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if mode == .coordinates {
                    Button("Save") { saveCoordinates() }.keyboardShortcut(.defaultAction)
                }
            }
            Text("City search uses Apple's geocoder, so your query is sent to Apple. Coordinates are never sent anywhere else.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if let loc = model.location {
                name = loc.name
                lat = String(loc.latitude)
                lon = String(loc.longitude)
                tzID = loc.timeZone
            }
        }
    }

    private var searchView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("City, e.g. Singapore or Jakarta", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button("Search", action: search)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }
            if searching { ProgressView().controlSize(.small) }
            ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                Button {
                    model.setLocation(r)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).fontWeight(.medium)
                        Text("\(r.timeZone) · \(r.coordinateDescription)")
                            .font(.system(size: 11.5)).foregroundStyle(Palette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Palette.display.opacity(0.6)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var coordinatesView: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow { Text("Name"); TextField("e.g. Home", text: $name).textFieldStyle(.roundedBorder) }
            GridRow { Text("Latitude"); TextField("-90 to 90, e.g. 1.3521", text: $lat).textFieldStyle(.roundedBorder) }
            GridRow { Text("Longitude"); TextField("-180 to 180, e.g. 103.8198", text: $lon).textFieldStyle(.roundedBorder) }
            GridRow {
                Text("Time zone")
                Picker("", selection: $tzID) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        error = nil
        Task {
            do {
                results = try await LocationSearch.search(q)
            } catch {
                results = []
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            searching = false
        }
    }

    private func saveCoordinates() {
        guard let la = Double(lat.trimmingCharacters(in: .whitespaces)), (-90...90).contains(la) else {
            error = "Latitude must be a number from -90 to 90."
            return
        }
        guard let lo = Double(lon.trimmingCharacters(in: .whitespaces)), (-180...180).contains(lo) else {
            error = "Longitude must be a number from -180 to 180."
            return
        }
        let n = name.trimmingCharacters(in: .whitespaces)
        model.setLocation(SavedLocation(
            name: n.isEmpty ? String(format: "%.4f, %.4f", la, lo) : n,
            latitude: la, longitude: lo, timeZone: tzID, source: .manual
        ))
        dismiss()
    }
}
