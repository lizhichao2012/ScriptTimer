import XCTest

final class ScriptTypeTests: XCTestCase {
    func testDetectByShebang() {
        XCTAssertEqual(ScriptType.detect(path: "/a/run", firstLine: "#!/usr/bin/env python3"), .python)
        XCTAssertEqual(ScriptType.detect(path: "/a/run.sh", firstLine: "#!/bin/bash"), .bash)
        XCTAssertEqual(ScriptType.detect(path: "/a/run.sh", firstLine: "#!/usr/bin/env bash"), .bash)
        XCTAssertEqual(ScriptType.detect(path: "/a/run.py", firstLine: "#!/bin/zsh"), .zsh)
        XCTAssertEqual(ScriptType.detect(path: "/a/run", firstLine: "#!/bin/sh"), .zsh)
    }

    func testDetectByExtension() {
        XCTAssertEqual(ScriptType.detect(path: "/a/job.py", firstLine: "import os"), .python)
        XCTAssertEqual(ScriptType.detect(path: "/a/job.PY", firstLine: nil), .python)
        XCTAssertEqual(ScriptType.detect(path: "/a/job.bash", firstLine: nil), .bash)
        XCTAssertEqual(ScriptType.detect(path: "/a/job.sh", firstLine: "echo hi"), .zsh)
        XCTAssertEqual(ScriptType.detect(path: "/a/job", firstLine: nil), .zsh)
    }

    func testScriptProblem() throws {
        var task = ScriptTask()
        XCTAssertNotNil(task.scriptProblem)
        task.scriptPath = "/nonexistent/x.sh"
        XCTAssertNotNil(task.scriptProblem)
        task.scriptPath = NSTemporaryDirectory()
        XCTAssertNotNil(task.scriptProblem, "目录不是脚本")
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("st-\(UUID()).sh")
        try "echo hi".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        task.scriptPath = file.path
        XCTAssertNil(task.scriptProblem)
    }

    func testDecodesLegacyTaskWithoutScriptPath() throws {
        let json = #"[{"id":"11111111-1111-1111-1111-111111111111","name":"old","schedule":{"daily":{"hour":9,"minute":0}}}]"#
        let tasks = try JSONDecoder().decode([ScriptTask].self, from: Data(json.utf8))
        XCTAssertEqual(tasks.first?.scriptPath, "")
        XCTAssertEqual(tasks.first?.name, "old")
    }
}
