import Foundation
import JavaScriptCore
import Supabase

enum DORICopilotServiceError: LocalizedError {
    case resourceMissing
    case engineUnavailable
    case invalidInput(String)
    case invalidResult
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .resourceMissing: "No se encontró el motor de DORI Copiloto en la aplicación."
        case .engineUnavailable: "DORI Copiloto no pudo iniciar el análisis local."
        case .invalidInput: "Revisa los datos de la oferta."
        case .invalidResult: "DORI Copiloto devolvió una respuesta incompleta."
        case .notConfigured: "Supabase no está configurado en esta compilación."
        }
    }
}

@MainActor
struct DORILocalCopilotService {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func evaluate(_ input: DORIDecisionInput) throws -> DORIDecisionResult {
        guard let resourceURL = bundle.url(forResource: "dori-copilot", withExtension: "js"),
              let script = try? String(contentsOf: resourceURL, encoding: .utf8) else {
            throw DORICopilotServiceError.resourceMissing
        }
        guard let context = JSContext() else { throw DORICopilotServiceError.engineUnavailable }

        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        context.evaluateScript(script)
        guard exception == nil,
              let function = context.objectForKeyedSubscript("DoriCopilot")?.objectForKeyedSubscript("evaluateJSON"),
              !function.isUndefined else {
            throw DORICopilotServiceError.engineUnavailable
        }

        let encoded = try JSONEncoder().encode(input)
        guard let json = String(data: encoded, encoding: .utf8) else {
            throw DORICopilotServiceError.invalidInput("encoding")
        }
        let value = function.call(withArguments: [json])
        if let exception { throw DORICopilotServiceError.invalidInput(exception) }
        guard let resultJSON = value?.toString(),
              let resultData = resultJSON.data(using: .utf8),
              let result = try? JSONDecoder().decode(DORIDecisionResult.self, from: resultData),
              (1...3).contains(result.reasons.count) else {
            throw DORICopilotServiceError.invalidResult
        }
        return result
    }
}

@MainActor
enum DORIRemoteCopilotService {
    nonisolated struct DecisionRequest: Encodable, Sendable {
        let kind = "decision"
        let idempotencyKey: String
        let input: DORIDecisionInput
    }

    nonisolated struct DecisionResponse: Decodable, Sendable {
        let event: DORIDecisionEvent
    }

    static func evaluateAndPersist(
        _ input: DORIDecisionInput,
        idempotencyKey: String = "ios-dori-\(UUID().uuidString.lowercased())"
    ) async throws -> DORIDecisionEvent {
        guard let client = SupabaseBridge.client else {
            throw DORICopilotServiceError.notConfigured
        }
        let response: DecisionResponse = try await client.functions.invoke(
            "dori-copilot-events",
            options: FunctionInvokeOptions(
                body: DecisionRequest(idempotencyKey: idempotencyKey, input: input)
            )
        )
        return response.event
    }
}

/// TEST-only transport for cases created by the DORI Console laboratory.
/// It is deliberately separate from the live decision-event transport above.
@MainActor
enum DORISimulationCopilotService {
    struct SimulationCase: Decodable, Sendable {
        let id: UUID
        let testCaseId: String
        let status: String
        let inputPayload: DORIDecisionInput

        private enum CodingKeys: String, CodingKey { case id, testCaseId = "test_case_id", status, inputPayload = "input_payload" }
    }

    struct CaseResponse: Decodable, Sendable { let simulationCase: SimulationCase
        private enum CodingKeys: String, CodingKey { case simulationCase = "case" }
    }

    struct Evaluation: Decodable, Sendable {
        let id: UUID
        let resultPayload: DORIDecisionResult
        private enum CodingKeys: String, CodingKey { case id, resultPayload = "result_payload" }
    }

    struct EvaluationResponse: Decodable, Sendable { let evaluation: Evaluation }

    static func nextCase() async throws -> SimulationCase {
        guard let client = SupabaseBridge.client else { throw DORICopilotServiceError.notConfigured }
        let response: CaseResponse = try await client.functions.invoke(
            "dori-copilot-simulation",
            options: FunctionInvokeOptions(body: ["operation": "next"])
        )
        return response.simulationCase
    }

    static func evaluate(caseId: UUID, idempotencyKey: String) async throws -> Evaluation {
        guard let client = SupabaseBridge.client else { throw DORICopilotServiceError.notConfigured }
        let response: EvaluationResponse = try await client.functions.invoke(
            "dori-copilot-simulation",
            options: FunctionInvokeOptions(body: [
                "operation": "evaluate", "caseId": caseId.uuidString,
                "idempotencyKey": idempotencyKey
            ])
        )
        return response.evaluation
    }
}
