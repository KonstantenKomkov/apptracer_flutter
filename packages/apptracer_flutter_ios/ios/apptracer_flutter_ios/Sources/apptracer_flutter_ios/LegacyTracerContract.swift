import Foundation

extension NativeOptions {
    var legacyArguments: [String: Any] {
        var arguments: [String: Any] = [
            "environment": environment,
            "isCollectionEnabled": isCollectionEnabled,
            "nativeInitialization": nativeInitialization,
            "preservePreviousReports": preservePreviousReports,
            "maxBreadcrumbs": maxBreadcrumbs,
            "attachRawStackTraceAsLog": attachRawStackTraceAsLog,
            "maxRawStackTraceLogBytes": maxRawStackTraceLogBytes,
            "maxStackFrames": maxStackFrames,
            "debug": debug,
            "initialCustomKeys": initialCustomKeys,
        ]
        if let appToken { arguments["appToken"] = appToken }
        if let dsn { arguments["dsn"] = dsn }
        if let release { arguments["release"] = release }
        if let dist { arguments["dist"] = dist }
        if let apiUrl { arguments["apiUrl"] = apiUrl }
        return arguments
    }
}

extension NativeStackFrame {
    var legacyArguments: [String: Any] {
        var arguments: [String: Any] = [
            "raw": raw,
            "asyncSuspension": isAsynchronousSuspension,
        ]
        if let index { arguments["index"] = index }
        if let member { arguments["member"] = member }
        if let uri { arguments["uri"] = uri }
        if let line { arguments["line"] = line }
        if let column { arguments["column"] = column }
        if let absoluteAddress { arguments["absAddress"] = absoluteAddress }
        if let virtualAddress { arguments["virtAddress"] = virtualAddress }
        if let symbol { arguments["symbol"] = symbol }
        return arguments
    }
}

extension NativeEvent {
    var legacyArguments: [String: Any] {
        var stack: [String: Any] = [
            "raw": stackTrace.raw,
            "frames": stackTrace.frames.map(\.legacyArguments),
            "needsSymbolication": stackTrace.needsSymbolication,
        ]
        if let buildId = stackTrace.buildId { stack["buildId"] = buildId }
        if let os = stackTrace.os { stack["os"] = os }
        if let architecture = stackTrace.architecture { stack["arch"] = architecture }
        if let base = stackTrace.isolateDsoBase { stack["isolateDsoBase"] = base }
        if let base = stackTrace.vmDsoBase { stack["vmDsoBase"] = base }
        if let instructions = stackTrace.isolateInstructions {
            stack["isolateInstructions"] = instructions
        }
        if let instructions = stackTrace.vmInstructions {
            stack["vmInstructions"] = instructions
        }

        var arguments: [String: Any] = [
            "exceptionType": exceptionType,
            "message": message,
            "severity": severity,
            "fatal": fatal,
            "timestamp": timestamp,
            "customKeys": customKeys,
            "stackTrace": stack,
            "breadcrumbs": breadcrumbs.map { crumb in
                var value: [String: Any] = [
                    "message": crumb.message,
                    "level": crumb.level,
                    "timestamp": crumb.timestamp,
                    "data": crumb.data,
                ]
                if let category = crumb.category { value["category"] = category }
                return value
            },
        ]
        if let issueKey { arguments["issueKey"] = issueKey }
        if let library { arguments["library"] = library }
        if let context { arguments["context"] = context }
        return arguments
    }
}

extension Dictionary where Key == String, Value == String {
    var collectionResult: NativeCollectionResult {
        NativeCollectionResult(state: self["state"] ?? "error", reason: self["reason"])
    }
}
