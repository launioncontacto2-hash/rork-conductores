import SwiftUI

/// The only desk in the network that can move the cash deposit account. Whatever is
/// signed here is what every driver reads at the counter of the convenience store, so
/// the sheet shows exactly the card the driver will see before it is published.
struct CashAccountEditorView: View {
    let national: NationalStore
    var onPublished: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var bank: String = ""
    @State private var holder: String = ""
    @State private var accountNumber: String = ""
    @State private var clabe: String = ""
    @State private var reference: String = ""
    @State private var instructions: String = ""
    @State private var note: String = ""
    @State private var loaded: Bool = false

    private var current: CashDepositAccount { national.cashAccount }

    private var digitsOnlyClabe: String { clabe.filter(\.isNumber) }

    private var canPublish: Bool {
        bank.trimmingCharacters(in: .whitespaces).count >= 3
            && holder.trimmingCharacters(in: .whitespaces).count >= 3
            && digitsOnlyClabe.count == 18
            && !reference.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasChanges: Bool {
        bank != current.bank
            || holder != current.holder
            || accountNumber != current.accountNumber
            || digitsOnlyClabe != current.clabe
            || reference != current.reference
            || instructions != current.instructions
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NationalBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        NoticeBanner(
                            symbol: "banknote.fill",
                            title: "Destino del efectivo de emergencia",
                            message: "El cobro en efectivo no está autorizado en ninguna estación. Esta cuenta solo existe para que el dinero recibido en una emergencia salga de las manos del conductor el mismo día.",
                            tone: .amber
                        )

                        field(label: "Banco", text: $bank, hint: "Institución receptora")
                        field(label: "Titular", text: $holder, hint: "Razón social de la red")
                        field(label: "Número de cuenta", text: $accountNumber, hint: "Como aparece en el estado de cuenta")

                        VStack(alignment: .leading, spacing: 6) {
                            CapsLabel(text: "CLABE interbancaria")
                            TextField("18 dígitos", text: $clabe)
                                .keyboardType(.numberPad)
                                .font(.system(.body, weight: .bold))
                                .monospacedDigit()
                                .padding(13)
                                .panelFlat()
                            Text("\(digitsOnlyClabe.count) de 18 dígitos")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(digitsOnlyClabe.count == 18 ? Palette.volt : Palette.amber)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        field(label: "Referencia", text: $reference, hint: "Concepto obligatorio del depósito")

                        VStack(alignment: .leading, spacing: 6) {
                            CapsLabel(text: "Instrucciones para el conductor")
                            TextField("Dónde y cuándo depositar", text: $instructions, axis: .vertical)
                                .font(.system(.footnote, weight: .semibold))
                                .lineLimit(2...5)
                                .padding(13)
                                .panelFlat()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        preview

                        VStack(alignment: .leading, spacing: 6) {
                            CapsLabel(text: "Motivo del cambio")
                            TextField("Queda en el historial de la red", text: $note, axis: .vertical)
                                .font(.system(.footnote, weight: .semibold))
                                .lineLimit(2...4)
                                .padding(13)
                                .panelFlat()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        BigButton(
                            title: "Publicar a toda la red",
                            symbol: "checkmark.seal.fill",
                            isEnabled: canPublish && hasChanges
                        ) {
                            publish()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Cuenta para depósitos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationContentInteraction(.scrolls)
        .preferredColorScheme(.dark)
        .onAppear(perform: loadCurrent)
    }

    private func field(label: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CapsLabel(text: label)
            TextField(hint, text: text)
                .font(.system(.body, weight: .semibold))
                .padding(13)
                .panelFlat()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the driver will read on his screen, before anything is signed.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: "Así lo verá el conductor")
            previewRow(label: "Banco", value: bank)
            previewRow(label: "Titular", value: holder)
            previewRow(label: "CLABE", value: grouped(digitsOnlyClabe))
            previewRow(label: "Cuenta", value: accountNumber)
            previewRow(label: "Referencia", value: reference)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(0.8)
                .foregroundStyle(Palette.textMuted)
                .frame(width: 74, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(.footnote, weight: .bold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func grouped(_ digits: String) -> String {
        stride(from: 0, to: digits.count, by: 4).map { index -> String in
            let start = digits.index(digits.startIndex, offsetBy: index)
            let end = digits.index(start, offsetBy: min(4, digits.count - index))
            return String(digits[start..<end])
        }.joined(separator: " ")
    }

    private func loadCurrent() {
        guard !loaded else { return }
        loaded = true
        let account = current
        bank = account.bank
        holder = account.holder
        accountNumber = account.accountNumber
        clabe = account.clabe
        reference = account.reference
        instructions = account.instructions
    }

    private func publish() {
        national.publishCashAccount(
            CashDepositAccount(
                bank: bank.trimmingCharacters(in: .whitespacesAndNewlines),
                holder: holder.trimmingCharacters(in: .whitespacesAndNewlines),
                accountNumber: accountNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                clabe: digitsOnlyClabe,
                reference: reference.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                version: current.version,
                updatedAt: national.now,
                updatedBy: ""
            ),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onPublished?()
        dismiss()
    }
}
