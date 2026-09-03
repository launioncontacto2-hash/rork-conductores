import Observation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Focused 15H workspace for a recruitment identity proved by Supabase. The rich
/// demonstration desk remains untouched; this screen shows only authoritative TEST rows.
@MainActor
@Observable
private final class BackendRecruitmentStore {
    let principal: SessionPrincipal

    var candidates: [SupabaseHiringService.CandidateRow] = []
    var documents: [SupabaseHiringService.DocumentRow] = []
    var hirings: [SupabaseHiringService.HiringRow] = []
    var isLoading = false
    var mutationCandidateId: UUID?
    var errorMessage: String?
    var successMessage: String?

    init(principal: SessionPrincipal) {
        self.principal = principal
    }

    func documents(for candidateId: UUID) -> [SupabaseHiringService.DocumentRow] {
        documents.filter { $0.candidate_id == candidateId && $0.status == "accepted" }
    }

    func hiring(for candidateId: UUID) -> SupabaseHiringService.HiringRow? {
        hirings.first { $0.candidate_id == candidateId }
    }

    func load() async {
        guard !isLoading else { return }
        guard let stationId = principal.stationId else {
            errorMessage = "La sesión de reclutamiento no contiene estación."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await SupabaseHiringService.loadSnapshot(stationId: stationId)
            candidates = snapshot.candidates
            documents = snapshot.documents
            hirings = snapshot.hirings
        } catch {
            errorMessage = SupabaseHiringService.userMessage(for: error)
        }
    }

    func upload(
        url: URL,
        kind: String,
        candidate: SupabaseHiringService.CandidateRow
    ) async {
        guard mutationCandidateId == nil else { return }
        mutationCandidateId = candidate.id
        errorMessage = nil
        successMessage = nil
        defer { mutationCandidateId = nil }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let values = try url.resourceValues(forKeys: [.contentTypeKey])
            guard let contentType = values.contentType?.preferredMIMEType else {
                throw SupabaseHiringService.ServiceError.unsupportedFile
            }
            let document = try await SupabaseHiringService.uploadDocument(
                data: data,
                filename: url.lastPathComponent,
                contentType: contentType,
                candidate: candidate,
                principal: principal,
                kind: kind
            )
            documents.removeAll { $0.candidate_id == candidate.id && $0.kind == kind }
            documents.insert(document, at: 0)
            successMessage = "\(Self.kindLabel(kind)) quedó guardado en el expediente."
            await load()
        } catch {
            errorMessage = SupabaseHiringService.userMessage(for: error)
        }
    }

    func complete(
        candidate: SupabaseHiringService.CandidateRow,
        employeeNumber: String,
        temporaryPassword: String
    ) async -> Bool {
        guard mutationCandidateId == nil else { return false }
        mutationCandidateId = candidate.id
        errorMessage = nil
        successMessage = nil
        defer { mutationCandidateId = nil }

        do {
            let response = try await SupabaseHiringService.completeHiring(
                candidateId: candidate.id,
                employeeNumber: employeeNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                temporaryPassword: temporaryPassword
            )
            if let index = hirings.firstIndex(where: { $0.id == response.hiring.id }) {
                hirings[index] = response.hiring
            } else {
                hirings.insert(response.hiring, at: 0)
            }
            successMessage = response.created
                ? "Alta completada. La identidad TEST ya puede iniciar sesión."
                : "Alta recuperada y confirmada sin duplicar la identidad."
            await load()
            return true
        } catch {
            errorMessage = SupabaseHiringService.userMessage(for: error)
            return false
        }
    }

    nonisolated static let documentKinds = [
        "officialId", "curp", "rfc", "license", "addressProof", "photo"
    ]

    nonisolated static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "officialId": "Identificación oficial"
        case "curp": "CURP"
        case "rfc": "RFC"
        case "license": "Licencia"
        case "addressProof": "Comprobante de domicilio"
        case "photo": "Fotografía"
        default: kind
        }
    }
}

struct BackendRecruitmentView: View {
    @Environment(FleetStore.self) private var fleet
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: BackendRecruitmentStore
    @State private var uploadCandidate: SupabaseHiringService.CandidateRow?
    @State private var hiringCandidate: SupabaseHiringService.CandidateRow?
    @State private var documentKind = "officialId"
    @State private var showsImporter = false

    init(principal: SessionPrincipal) {
        _model = State(initialValue: BackendRecruitmentStore(principal: principal))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identityCard
                    statusMessages
                    summaryCard
                    candidatesCard
                }
                .padding(18)
            }
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle("Reclutamiento")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar sesión") { fleet.signOut() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    DemoClockButton()
                    Button { Task { await model.load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.load() }
            }
            .fileImporter(
                isPresented: $showsImporter,
                allowedContentTypes: [.pdf, .jpeg, .png, .heic],
                allowsMultipleSelection: false
            ) { result in
                guard let candidate = uploadCandidate else { return }
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await model.upload(url: url, kind: documentKind, candidate: candidate) }
                case .failure(let error):
                    model.errorMessage = error.localizedDescription
                }
            }
            .sheet(item: $hiringCandidate) { candidate in
                BackendHiringSheet(model: model, candidate: candidate)
            }
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECLUTAMIENTO TEST")
                .font(.caption.weight(.black))
                .foregroundStyle(Palette.volt)
            Text(model.principal.name)
                .font(.title3.weight(.bold))
            Text("\(model.principal.stationName ?? "Estación") · \(model.principal.stationCode ?? "—")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var statusMessages: some View {
        if model.isLoading {
            ProgressView("Actualizando expedientes…")
        }
        if let message = model.successMessage {
            Label(message, systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        }
        if let message = model.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 10) {
            metric("Candidatos", model.candidates.count)
            metric("Listos", model.candidates.filter { $0.stage == "ready_to_hire" }.count)
            metric("Altas", model.hirings.filter { $0.status == "completed" }.count)
        }
        .padding(14)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.title2.weight(.black))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var candidatesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("EXPEDIENTES")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)

            if model.candidates.isEmpty, !model.isLoading {
                Text("No hay candidatos visibles en esta estación.")
                    .foregroundStyle(.secondary)
            }

            ForEach(model.candidates) { candidate in
                candidateRow(candidate)
                if candidate.id != model.candidates.last?.id { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private func candidateRow(_ candidate: SupabaseHiringService.CandidateRow) -> some View {
        let accepted = model.documents(for: candidate.id)
        let acceptedKinds = Set(accepted.map(\.kind))
        let missingKinds = BackendRecruitmentStore.documentKinds.filter {
            !acceptedKinds.contains($0)
        }
        let hiring = model.hiring(for: candidate.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.full_name).font(.headline)
                    Text("\(candidate.email) · \(candidate.curp)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(hiring?.status.uppercased() ?? candidate.stage.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(candidate.stage == "ready_to_hire" ? Palette.volt : .secondary)
            }

            Text("Documentos vigentes: \(accepted.count)/6 · \(candidate.requested_shift_group) / \(candidate.requested_shift_slot)")
                .font(.footnote)

            if !missingKinds.isEmpty {
                Text("Faltan: \(missingKinds.map(BackendRecruitmentStore.kindLabel).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hiring?.status != "completed" && candidate.stage != "lost" {
                Picker("Documento", selection: $documentKind) {
                    ForEach(BackendRecruitmentStore.documentKinds, id: \.self) { kind in
                        Text(BackendRecruitmentStore.kindLabel(kind)).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("Adjuntar") {
                        uploadCandidate = candidate
                        showsImporter = true
                    }
                    .buttonStyle(.bordered)

                    if candidate.stage == "ready_to_hire" {
                        Button("Completar alta") { hiringCandidate = candidate }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .disabled(model.mutationCandidateId != nil)
            }
        }
    }
}

private struct BackendHiringSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: BackendRecruitmentStore
    let candidate: SupabaseHiringService.CandidateRow

    @State private var employeeNumber = ""
    @State private var temporaryPassword = ""

    private var canSubmit: Bool {
        employeeNumber.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && temporaryPassword.count >= 8
            && model.mutationCandidateId == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Candidato") {
                    Text(candidate.full_name)
                    Text(candidate.email).foregroundStyle(.secondary)
                }
                Section("Identidad TEST") {
                    TextField("Número de empleado", text: $employeeNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    SecureField("Contraseña temporal", text: $temporaryPassword)
                    Text("La contraseña se envía directamente a Supabase Auth y no se guarda en el teléfono.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Completar alta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear acceso") {
                        Task {
                            let completed = await model.complete(
                                candidate: candidate,
                                employeeNumber: employeeNumber,
                                temporaryPassword: temporaryPassword
                            )
                            temporaryPassword = ""
                            if completed { dismiss() }
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }
}
