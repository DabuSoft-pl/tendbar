import Foundation
import TendbarDomain

/// A socket message translated into the domain's language.
public enum InboundMessage: Sendable, Equatable {
    case hook(HookEvent)
    case usage(UsageReading)
}

extension HookEnvelope {
    /// Nil for input Tendbar does not use, such as a status line before the first reply (no `rate_limits`).
    public func message() -> InboundMessage? {
        if isStatusLine {
            guard let input = try? JSONDecoder().decode(StatusLineInput.self, from: Data(raw.utf8)),
                  let limits = input.rateLimits
            else { return nil }
            return .usage(UsageReading(
                configDirectory: terminal.configDirectory,
                fiveHour: limits.fiveHour?.window,
                sevenDay: limits.sevenDay?.window,
                readAt: sentAt
            ))
        }
        guard let payload = try? payload() else { return nil }
        return .hook(HookEvent(
            sessionID: payload.sessionID,
            kind: HookEvent.Kind(name: payload.event),
            cwd: payload.cwd,
            transcriptPath: payload.transcriptPath,
            message: payload.message ?? payload.failureMessage,
            notificationType: payload.notificationType,
            agentID: payload.agentID,
            terminal: terminal.context,
            sentAt: sentAt
        ))
    }
}

struct StatusLineInput: Decodable {
    struct Limits: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    struct Window: Decodable {
        let usedPercentage: Double?
        let resetsAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }

        var window: LimitWindow? {
            guard let usedPercentage, let resetsAt else { return nil }
            return LimitWindow(usedPercentage: usedPercentage, resetsAt: Date(timeIntervalSince1970: resetsAt))
        }
    }

    let rateLimits: Limits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}
