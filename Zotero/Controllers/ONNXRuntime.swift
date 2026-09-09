//
//  ONNXRuntime.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 13/6/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

#if MAINAPP
import Foundation

enum ONNXRuntimeError: Error {
    case apiUnavailable
    case invalidModelData
    case invalidTensorData
    case operationFailed(message: String)
    case unsupportedTensorElementType(ONNXTensorElementDataType)
}

final class ONNXRuntime {
    enum Tensor {
        case float32(name: String, values: [Float], dimensions: [Int64])
        case int64(name: String, values: [Int64], dimensions: [Int64])
        case bool(name: String, values: [UInt8], dimensions: [Int64])
    }

    struct TensorResult {
        let elementType: ONNXTensorElementDataType
        let dimensions: [Int64]
        let floatValues: [Float]?
    }

    final class Environment {
        fileprivate let env: OpaquePointer

        fileprivate init(env: OpaquePointer) {
            self.env = env
        }

        deinit {
            ONNXRuntime.api.pointee.ReleaseEnv(env)
        }
    }

    final class Session {
        private let environment: Environment
        private let session: OpaquePointer

        fileprivate init(environment: Environment, session: OpaquePointer) {
            self.environment = environment
            self.session = session
        }

        deinit {
            ONNXRuntime.api.pointee.ReleaseSession(session)
        }

        func inputNames() throws -> [String] {
            try names(count: ONNXRuntime.api.pointee.SessionGetInputCount, name: ONNXRuntime.api.pointee.SessionGetInputName)
        }

        func outputNames() throws -> [String] {
            try names(count: ONNXRuntime.api.pointee.SessionGetOutputCount, name: ONNXRuntime.api.pointee.SessionGetOutputName)
        }

        func run(inputs: [Tensor], outputNames: [String]) throws -> [String: TensorResult] {
            let inputNames = inputs.map(\.name)
            let inputNameStorage = inputNames.map { strdup($0) }
            defer {
                inputNameStorage.forEach { free($0) }
            }
            var inputNamePointers = inputNameStorage.map { pointer in
                pointer.map { UnsafePointer<CChar>($0) }
            }

            let outputNameStorage = outputNames.map { strdup($0) }
            defer {
                outputNameStorage.forEach { free($0) }
            }
            var outputNamePointers = outputNameStorage.map { pointer in
                pointer.map { UnsafePointer<CChar>($0) }
            }

            let ortInputs = try inputs.map { try OrtTensor(input: $0) }
            defer {
                ortInputs.forEach { $0.release() }
            }
            var inputValues = ortInputs.map(\.value)
            var outputValues = [OpaquePointer?](repeating: nil, count: outputNames.count)

            let status = inputNamePointers.withUnsafeMutableBufferPointer { inputNamePointers -> OrtStatusPtr? in
                inputValues.withUnsafeMutableBufferPointer { inputValues -> OrtStatusPtr? in
                    outputNamePointers.withUnsafeMutableBufferPointer { outputNamePointers -> OrtStatusPtr? in
                        outputValues.withUnsafeMutableBufferPointer { outputValues -> OrtStatusPtr? in
                            ONNXRuntime.api.pointee.Run(
                                session,
                                nil,
                                inputNamePointers.baseAddress,
                                inputValues.baseAddress,
                                inputs.count,
                                outputNamePointers.baseAddress,
                                outputNames.count,
                                outputValues.baseAddress
                            )
                        }
                    }
                }
            }
            try ONNXRuntime.check(status)

            defer {
                outputValues.forEach { value in
                    guard let value else { return }
                    ONNXRuntime.api.pointee.ReleaseValue(value)
                }
            }

            var results: [String: TensorResult] = [:]
            for (index, outputName) in outputNames.enumerated() {
                guard let value = outputValues[index] else { throw ONNXRuntimeError.apiUnavailable }
                results[outputName] = try TensorResult(value: value)
            }
            return results
        }

        private func names(
            count countFunction: (OpaquePointer?, UnsafeMutablePointer<Int>?) -> OrtStatusPtr?,
            name nameFunction: (OpaquePointer?, Int, UnsafeMutablePointer<OrtAllocator>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> OrtStatusPtr?
        ) throws -> [String] {
            var count = 0
            try ONNXRuntime.check(countFunction(session, &count))

            var allocator: UnsafeMutablePointer<OrtAllocator>?
            try ONNXRuntime.check(ONNXRuntime.api.pointee.GetAllocatorWithDefaultOptions(&allocator))
            guard let allocator else { throw ONNXRuntimeError.apiUnavailable }

            return try (0..<count).map { index in
                var name: UnsafeMutablePointer<CChar>?
                try ONNXRuntime.check(nameFunction(session, index, allocator, &name))
                guard let name else { throw ONNXRuntimeError.apiUnavailable }
                defer {
                    try? ONNXRuntime.check(ONNXRuntime.api.pointee.AllocatorFree(allocator, name))
                }
                return String(cString: name)
            }
        }
    }

    private final class OrtTensor {
        let value: OpaquePointer?

        init(input: Tensor) throws {
            let tensorData: Data
            let dimensions: [Int64]
            let elementType: ONNXTensorElementDataType
            switch input {
            case let .float32(_, values, dims):
                tensorData = values.withUnsafeBufferPointer { Data(buffer: $0) }
                dimensions = dims
                elementType = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT

            case let .int64(_, values, dims):
                tensorData = values.withUnsafeBufferPointer { Data(buffer: $0) }
                dimensions = dims
                elementType = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64

            case let .bool(_, values, dims):
                tensorData = Data(values)
                dimensions = dims
                elementType = ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL
            }
            guard dimensions.reduce(1, *) == tensorData.elementCount(for: elementType) else {
                throw ONNXRuntimeError.invalidTensorData
            }

            var allocator: UnsafeMutablePointer<OrtAllocator>?
            try ONNXRuntime.check(ONNXRuntime.api.pointee.GetAllocatorWithDefaultOptions(&allocator))
            guard let allocator else { throw ONNXRuntimeError.apiUnavailable }

            var value: OpaquePointer?
            var tensorDimensions = dimensions
            try tensorDimensions.withUnsafeMutableBufferPointer { dimensions in
                try ONNXRuntime.check(
                    ONNXRuntime.api.pointee.CreateTensorAsOrtValue(
                        allocator,
                        dimensions.baseAddress,
                        dimensions.count,
                        elementType,
                        &value
                    )
                )
            }
            guard let value else {
                throw ONNXRuntimeError.apiUnavailable
            }

            var dataPointer: UnsafeMutableRawPointer?
            do {
                try ONNXRuntime.check(ONNXRuntime.api.pointee.GetTensorMutableData(value, &dataPointer))
                guard let dataPointer else { throw ONNXRuntimeError.invalidTensorData }
                tensorData.withUnsafeBytes { bytes in
                    if let baseAddress = bytes.baseAddress, !tensorData.isEmpty {
                        dataPointer.copyMemory(from: baseAddress, byteCount: tensorData.count)
                    }
                }
            } catch {
                ONNXRuntime.api.pointee.ReleaseValue(value)
                throw error
            }

            self.value = value
        }

        func release() {
            if let value {
                ONNXRuntime.api.pointee.ReleaseValue(value)
            }
        }
    }

    static var versionString: String {
        guard let version = apiBase.pointee.GetVersionString() else { return "" }
        return String(cString: version)
    }

    static func createEnvironment(logId: String = "zotero") throws -> Environment {
        var env: OpaquePointer?
        let status = logId.withCString { logId in
            api.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, logId, &env)
        }
        try check(status)
        guard let env else { throw ONNXRuntimeError.apiUnavailable }
        return Environment(env: env)
    }

    static func createSession(modelData: Data, environment: Environment) throws -> Session {
        var sessionOptions: OpaquePointer?
        try check(api.pointee.CreateSessionOptions(&sessionOptions))
        guard let sessionOptions else { throw ONNXRuntimeError.apiUnavailable }
        defer {
            api.pointee.ReleaseSessionOptions(sessionOptions)
        }
        try check(api.pointee.SetSessionGraphOptimizationLevel(sessionOptions, ORT_ENABLE_ALL))
        try check(api.pointee.SetSessionExecutionMode(sessionOptions, ORT_SEQUENTIAL))
        try check(api.pointee.SetIntraOpNumThreads(sessionOptions, 1))
        try check(api.pointee.SetInterOpNumThreads(sessionOptions, 1))

        var session: OpaquePointer?
        let status = try modelData.withUnsafeBytes { modelBytes -> OrtStatusPtr? in
            guard let baseAddress = modelBytes.baseAddress else {
                throw ONNXRuntimeError.invalidModelData
            }
            return api.pointee.CreateSessionFromArray(environment.env, baseAddress, modelData.count, sessionOptions, &session)
        }
        try check(status)
        guard let session else { throw ONNXRuntimeError.apiUnavailable }
        return Session(environment: environment, session: session)
    }

    private static let apiBase: UnsafePointer<OrtApiBase> = {
        guard let apiBase = OrtGetApiBase() else {
            fatalError("ONNX Runtime API base is unavailable")
        }
        return apiBase
    }()

    fileprivate static let api: UnsafePointer<OrtApi> = {
        guard let api = apiBase.pointee.GetApi(UInt32(ORT_API_VERSION)) else {
            fatalError("ONNX Runtime C API v\(ORT_API_VERSION) is unavailable")
        }
        return api
    }()

    fileprivate static func check(_ status: OrtStatusPtr?) throws {
        guard let status else { return }
        defer {
            api.pointee.ReleaseStatus(status)
        }
        let message = api.pointee.GetErrorMessage(status).map(String.init(cString:)) ?? "unknown ONNX Runtime error"
        throw ONNXRuntimeError.operationFailed(message: message)
    }
}

private extension ONNXRuntime.Tensor {
    var name: String {
        switch self {
        case let .float32(name, _, _), let .int64(name, _, _), let .bool(name, _, _):
            return name
        }
    }
}

private extension ONNXRuntime.TensorResult {
    init(value: OpaquePointer) throws {
        var typeAndShape: OpaquePointer?
        try ONNXRuntime.check(ONNXRuntime.api.pointee.GetTensorTypeAndShape(value, &typeAndShape))
        guard let typeAndShape else { throw ONNXRuntimeError.apiUnavailable }
        defer {
            ONNXRuntime.api.pointee.ReleaseTensorTypeAndShapeInfo(typeAndShape)
        }

        var elementType = ONNXTensorElementDataType(0)
        try ONNXRuntime.check(ONNXRuntime.api.pointee.GetTensorElementType(typeAndShape, &elementType))

        var dimensionCount = 0
        try ONNXRuntime.check(ONNXRuntime.api.pointee.GetDimensionsCount(typeAndShape, &dimensionCount))
        var dimensions = [Int64](repeating: 0, count: dimensionCount)
        try dimensions.withUnsafeMutableBufferPointer { dimensions in
            try ONNXRuntime.check(ONNXRuntime.api.pointee.GetDimensions(typeAndShape, dimensions.baseAddress, dimensionCount))
        }

        self.elementType = elementType
        self.dimensions = dimensions

        switch elementType {
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT:
            var elementCount = 0
            try ONNXRuntime.check(ONNXRuntime.api.pointee.GetTensorShapeElementCount(typeAndShape, &elementCount))
            var dataPointer: UnsafeRawPointer?
            try ONNXRuntime.check(ONNXRuntime.api.pointee.GetTensorData(value, &dataPointer))
            guard let dataPointer else { throw ONNXRuntimeError.invalidTensorData }
            let buffer = dataPointer.bindMemory(to: Float.self, capacity: elementCount)
            floatValues = Array(UnsafeBufferPointer(start: buffer, count: elementCount))

        default:
            floatValues = nil
        }
    }
}

private extension Data {
    func elementCount(for elementType: ONNXTensorElementDataType) -> Int64 {
        switch elementType {
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT:
            return Int64(count / MemoryLayout<Float>.stride)

        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64:
            return Int64(count / MemoryLayout<Int64>.stride)

        case ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL:
            return Int64(count)

        default:
            return -1
        }
    }
}
#endif
