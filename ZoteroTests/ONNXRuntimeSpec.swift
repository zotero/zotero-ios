//
//  ONNXRuntimeSpec.swift
//  ZoteroTests
//
//  Created by Miltiadis Vasilakis on 13/6/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import XCTest

@testable import Zotero

import Nimble
import Quick

final class ONNXRuntimeSpec: QuickSpec {
    override class func spec() {
        describe("ONNX Runtime") {
            func session(forModelResource resource: String) throws -> ONNXRuntime.Session {
                let url = Bundle(for: ONNXRuntimeSpec.self).url(forResource: resource, withExtension: "onnx")
                let modelData = try Data(contentsOf: try XCTUnwrap(url))
                let environment = try ONNXRuntime.createEnvironment()
                return try ONNXRuntime.createSession(modelData: modelData, environment: environment)
            }

            it("loads the C runtime and creates an environment") {
                expect(ONNXRuntime.versionString).toNot(beEmpty())
                expect { try ONNXRuntime.createEnvironment() }.toNot(throwError())
            }

            it("loads the document worker block classifier model") {
                let session = try session(forModelResource: "block_seg_classifier_model")

                expect(try session.inputNames()).to(equal([
                    "regular_features",
                    "rich_features",
                    "hash_slots",
                    "char_slots",
                    "pad_mask"
                ]))
                expect(try session.outputNames()).to(equal([
                    "type_logits",
                    "flow_logits"
                ]))
            }

            it("runs the document worker block classifier model") {
                let session = try session(forModelResource: "block_seg_classifier_model")

                let outputs = try session.run(
                    inputs: [
                        .float32(
                            name: "regular_features",
                            values: Array(repeating: 0, count: 196),
                            dimensions: [1, 1, 196]
                        ),
                        .float32(
                            name: "rich_features",
                            values: Array(repeating: 0, count: 306),
                            dimensions: [1, 1, 306]
                        ),
                        .int64(
                            name: "hash_slots",
                            values: Array(repeating: 0, count: 36),
                            dimensions: [1, 1, 36]
                        ),
                        .int64(
                            name: "char_slots",
                            values: Array(repeating: 0, count: 4),
                            dimensions: [1, 1, 4]
                        ),
                        .bool(
                            name: "pad_mask",
                            values: [0],
                            dimensions: [1, 1]
                        )
                    ],
                    outputNames: [
                        "type_logits",
                        "flow_logits"
                    ]
                )

                expect(outputs["type_logits"]?.elementType).to(equal(ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT))
                expect(outputs["type_logits"]?.dimensions).to(equal([1, 1, 7]))
                expect(outputs["type_logits"]?.floatValues?.count).to(equal(7))

                expect(outputs["flow_logits"]?.elementType).to(equal(ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT))
                expect(outputs["flow_logits"]?.dimensions).to(equal([1, 1, 3]))
                expect(outputs["flow_logits"]?.floatValues?.count).to(equal(3))
            }

            it("loads the document worker block clusterer model") {
                let session = try session(forModelResource: "block_seg_clusterer_model")

                expect(try session.inputNames()).to(equal([
                    "line_features",
                    "line_pad_mask",
                    "object_features",
                    "object_pad_mask"
                ]))
                expect(try session.outputNames()).to(equal([
                    "emissions",
                    "object_rule_logits"
                ]))
            }

            it("runs the document worker block clusterer model") {
                let session = try session(forModelResource: "block_seg_clusterer_model")

                let outputs = try session.run(
                    inputs: [
                        .float32(
                            name: "line_features",
                            values: Array(repeating: 0, count: 22),
                            dimensions: [1, 1, 22]
                        ),
                        .bool(
                            name: "line_pad_mask",
                            values: [0],
                            dimensions: [1, 1]
                        ),
                        .float32(
                            name: "object_features",
                            values: Array(repeating: 0, count: 22),
                            dimensions: [1, 1, 22]
                        ),
                        .bool(
                            name: "object_pad_mask",
                            values: [0],
                            dimensions: [1, 1]
                        )
                    ],
                    outputNames: [
                        "emissions",
                        "object_rule_logits"
                    ]
                )

                expect(outputs["emissions"]?.elementType).to(equal(ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT))
                expect(outputs["emissions"]?.dimensions).to(equal([1, 1, 18]))
                expect(outputs["emissions"]?.floatValues?.count).to(equal(18))

                expect(outputs["object_rule_logits"]?.elementType).to(equal(ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT))
                expect(outputs["object_rule_logits"]?.dimensions).to(equal([1, 1, 2]))
                expect(outputs["object_rule_logits"]?.floatValues?.count).to(equal(2))
            }

            it("loads the document worker block clusterer repair model") {
                let session = try session(forModelResource: "block_seg_clusterer_repair_model")

                expect(try session.inputNames()).to(equal([
                    "features"
                ]))
                expect(try session.outputNames()).to(equal([
                    "logits"
                ]))
            }

            it("runs the document worker block clusterer repair model") {
                let session = try session(forModelResource: "block_seg_clusterer_repair_model")

                let outputs = try session.run(
                    inputs: [
                        .float32(
                            name: "features",
                            values: Array(repeating: 0, count: 219),
                            dimensions: [1, 219]
                        )
                    ],
                    outputNames: [
                        "logits"
                    ]
                )

                expect(outputs["logits"]?.elementType).to(equal(ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT))
                expect(outputs["logits"]?.dimensions).to(equal([1]))
                expect(outputs["logits"]?.floatValues?.count).to(equal(1))
            }
        }
    }
}
