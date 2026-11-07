//
//  DocumentWorkerNativeONNXBridge.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 14/6/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

#if MAINAPP
import Foundation

final class DocumentWorkerNativeONNXBridge {
    typealias ModelDataProvider = (String) throws -> Data

    enum Error: Swift.Error {
        case invalidPayload(String)
        case modelDataProviderUnavailable
    }

    private let modelDataProvider: ModelDataProvider
    private var environment: ONNXRuntime.Environment?
    private var sessionsByModel: [String: ONNXRuntime.Session]

    init(modelDataProvider: @escaping ModelDataProvider) {
        self.modelDataProvider = modelDataProvider
        sessionsByModel = [:]
    }

    func run(payload: Any) throws -> [String: Any] {
        guard let body = payload as? [String: Any] else {
            throw Error.invalidPayload("invalid payload")
        }
        guard let model = body["model"] as? String else {
            throw Error.invalidPayload("missing model")
        }
        guard let inputPayloads = body["inputs"] as? [[String: Any]] else {
            throw Error.invalidPayload("missing inputs")
        }

        let session = try session(for: model)
        let outputNames: [String]
        if let requestedOutputNames = body["outputNames"] as? [String] {
            outputNames = requestedOutputNames
        } else {
            outputNames = try session.outputNames()
        }
        let outputs = try session.run(
            inputs: try inputPayloads.map { try tensor(from: $0) },
            outputNames: outputNames
        )

        var resultOutputs: [String: Any] = [:]
        for (name, output) in outputs {
            resultOutputs[name] = try bridgeOutput(output)
        }
        return ["outputs": resultOutputs]
    }

    private func session(for model: String) throws -> ONNXRuntime.Session {
        if let session = sessionsByModel[model] {
            return session
        }

        let resolvedEnvironment: ONNXRuntime.Environment
        if let environment {
            resolvedEnvironment = environment
        } else {
            resolvedEnvironment = try ONNXRuntime.createEnvironment(logId: "zotero-document-worker")
            environment = resolvedEnvironment
        }

        let session = try ONNXRuntime.createSession(modelData: try modelDataProvider(model), environment: resolvedEnvironment)
        sessionsByModel[model] = session
        return session
    }

    private func tensor(from payload: [String: Any]) throws -> ONNXRuntime.Tensor {
        guard let name = payload["name"] as? String else {
            throw Error.invalidPayload("missing input name")
        }
        guard let type = payload["type"] as? String else {
            throw Error.invalidPayload("missing input type")
        }
        let dimensions = try int64Array(from: payload["dims"])

        switch type {
        case "float32":
            return .float32(name: name, values: try floatArray(from: payload["values"]), dimensions: dimensions)

        case "int64":
            return .int64(name: name, values: try int64Array(from: payload["values"]), dimensions: dimensions)

        case "bool":
            return .bool(name: name, values: try boolArray(from: payload["values"]), dimensions: dimensions)

        default:
            throw Error.invalidPayload("unsupported input type \(type)")
        }
    }

    private func bridgeOutput(_ output: ONNXRuntime.TensorResult) throws -> [String: Any] {
        switch output.elementType {
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT:
            return [
                "type": "float32",
                "dims": output.dimensions.map { Int($0) },
                "values": output.floatValues?.map(Double.init) ?? []
            ]

        default:
            throw ONNXRuntimeError.unsupportedTensorElementType(output.elementType)
        }
    }

    private func floatArray(from value: Any?) throws -> [Float] {
        guard let values = value as? [Any] else {
            throw Error.invalidPayload("invalid float32 values")
        }
        return try values.map { value in
            if let value = value as? Float {
                return value
            }
            if let value = value as? Double {
                return Float(value)
            }
            if let value = value as? NSNumber {
                return value.floatValue
            }
            throw Error.invalidPayload("invalid float32 value")
        }
    }

    private func int64Array(from value: Any?) throws -> [Int64] {
        guard let values = value as? [Any] else {
            throw Error.invalidPayload("invalid int64 values")
        }
        return try values.map { value in
            if let value = value as? Int64 {
                return value
            }
            if let value = value as? Int {
                return Int64(value)
            }
            if let value = value as? NSNumber {
                return value.int64Value
            }
            throw Error.invalidPayload("invalid int64 value")
        }
    }

    private func boolArray(from value: Any?) throws -> [UInt8] {
        guard let values = value as? [Any] else {
            throw Error.invalidPayload("invalid bool values")
        }
        return try values.map { value in
            if let value = value as? Bool {
                return value ? 1 : 0
            }
            if let value = value as? NSNumber {
                return value.boolValue ? 1 : 0
            }
            throw Error.invalidPayload("invalid bool value")
        }
    }
}
#endif
