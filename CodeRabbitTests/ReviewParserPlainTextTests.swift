import XCTest
@testable import CodeRabbit

final class ReviewParserPlainTextTests: XCTestCase {
    func testParsePlainTextFindingWithCommentDiffAndPrompt() throws {
        let input = """
        Starting CodeRabbit review in plain text mode...

        =============================================================================
        File: CodeRabbit/ReviewRunner.swift
        Line: 165 to 199
        Type: potential_issue

        Comment:
        Data race: accessing @MainActor method from background queue.

        🔧 Proposed fix

        -            environment[\"PATH\"] = self.buildPortablePath(basePath: environment[\"PATH\"])
        +            environment[\"PATH\"] = portablePath

        Prompt for AI Agent:
        Verify each finding against the current code and only fix it if needed.
        Keep lookupUsingWhich behavior unchanged.


        Review completed: 1 finding ✔
        """

        let findings = ReviewParser.parse(from: input)
        XCTAssertEqual(findings.count, 1)

        let finding = try XCTUnwrap(findings.first)
        XCTAssertEqual(finding.file, "CodeRabbit/ReviewRunner.swift")
        XCTAssertEqual(finding.line, 165)
        XCTAssertEqual(finding.lineEnd, 199)
        XCTAssertEqual(finding.typeRaw, "potential_issue")
        XCTAssertEqual(finding.typeDisplay, "potential_issue")
        XCTAssertEqual(finding.commentText, "Data race: accessing @MainActor method from background queue.")
        XCTAssertEqual(finding.aiPrompt, "Verify each finding against the current code and only fix it if needed.\nKeep lookupUsingWhich behavior unchanged.")

        let diff = try XCTUnwrap(finding.proposedFix)
        XCTAssertEqual(diff.lines.count, 2)
        XCTAssertEqual(diff.lines[0].kind, .removed)
        XCTAssertEqual(diff.lines[0].text, "-            environment[\"PATH\"] = self.buildPortablePath(basePath: environment[\"PATH\"])")
        XCTAssertEqual(diff.lines[1].kind, .added)
        XCTAssertEqual(diff.lines[1].text, "+            environment[\"PATH\"] = portablePath")
    }

    func testParsePhasesIncludesComplete() {
        let input = """
        Starting CodeRabbit review in plain text mode...
        Connecting to review service
        Setting up
        Analyzing
        Reviewing
        Review completed: 3 findings ✔
        """

        let phases = ReviewParser.parsePhases(from: input)
        XCTAssertEqual(phases, [.starting, .connecting, .settingUp, .analyzing, .reviewing, .complete])
    }

    func testLegacyGitHubStyleParsingStillWorks() {
        let findings = ReviewParser.parse(from: "SettingsView.swift:13: warning: hardcoded path")
        XCTAssertEqual(findings.count, 1)

        let finding = try? XCTUnwrap(findings.first)
        XCTAssertEqual(finding?.file, "SettingsView.swift")
        XCTAssertEqual(finding?.line, 13)
        XCTAssertEqual(finding?.severity, .warning)
        XCTAssertEqual(finding?.typeRaw?.lowercased(), "warning")
        XCTAssertEqual(finding?.commentText, "hardcoded path")
    }

    func testParseRunFailureMessageForRateLimit() {
        let input = """
        Starting CodeRabbit review in plain text mode...
        Connecting to review service
        Setting up
        [2026-03-03T14:41:33.445Z] ❌ ERROR: Error: Rate limit exceeded, please try after 1 minutes and 52 seconds
        Failed to start review: Review failed
        [error] stopping cli
        """

        let failure = ReviewParser.parseRunFailureMessage(from: input)
        XCTAssertEqual(failure, "Rate limit exceeded, please try after 1 minutes and 52 seconds")
    }

    func testParseRunErrorInfoPrefersDetailedNoFilesReviewError() {
        let input = """
        Starting CodeRabbit review in plain text mode...
        Connecting to review service
        Setting up
        [2026-03-12T19:45:52.522Z] ❌ REVIEW ERROR: Review failed: No files found for review
        Failed to start review: Review failed
        [error] stopping cli
        """

        let info = ReviewParser.parseRunErrorInfo(from: input)
        XCTAssertEqual(info?.isRateLimit, false)
        XCTAssertEqual(
            info?.message,
            "No files found for review. Make a code change or choose a different comparison base, then run again."
        )
        XCTAssertEqual(
            ReviewParser.parseRunFailureMessage(from: input),
            "No files found for review. Make a code change or choose a different comparison base, then run again."
        )
    }

    func testTimestampedRateLimitErrorWinsOverStoppingCliLine() {
        let input = """
        Starting CodeRabbit review in plain text mode...
        Connecting to review service
        Setting up
        [2026-03-03T15:40:01.764Z] ❌ ERROR: Error: Rate limit exceeded, please try after 3 minutes and 24 seconds
        Failed to start review: Review failed
        [error] stopping cli
        """

        let info = ReviewParser.parseRunErrorInfo(from: input)
        XCTAssertEqual(info?.isRateLimit, true)
        XCTAssertEqual(info?.message, "Rate limit exceeded, please try after 3 minutes and 24 seconds")
    }

    func testParsePhasesIncludesCompleteOnStartupFailure() {
        let input = """
        Starting CodeRabbit review in plain text mode...
        Connecting to review service
        Setting up
        Failed to start review: Review failed
        """

        let phases = ReviewParser.parsePhases(from: input)
        XCTAssertEqual(phases, [.starting, .connecting, .settingUp, .complete])
    }

    func testRateLimitMentionInFindingBodyIsNotRuntimeRateLimitError() {
        let input = """
        Starting CodeRabbit review in plain text mode...
        Connecting to review service
        Setting up
        Analyzing
        Reviewing

        ============================================================================
        File: CodeRabbit/ReviewParser.swift
        Line: 132 to 143
        Type: potential_issue

        Comment:
        This text mentions rate limit exceeded, but it is part of a finding.

        Prompt for AI Agent:
        Keep the phrase \"Rate limit exceeded\" in this prompt as plain content.

        Review completed: 1 finding ✔
        """

        XCTAssertNil(ReviewParser.parseRunErrorInfo(from: input))
        XCTAssertNil(ReviewParser.parseRunFailureMessage(from: input))
    }

    func testSuggestedFixHeaderParsesAsProposedFixBlock() {
        let input = """
        Starting CodeRabbit review in plain text mode...

        ============================================================================
        File: CodeRabbit/ReviewParser.swift
        Line: 132 to 143
        Type: potential_issue

        Comment:
        isOperationalLogLine mixes case-sensitive and case-insensitive checks.

        🔧 Suggested fix for consistent case handling

         private static func isOperationalLogLine(_ line: String) -> Bool {
             let lowered = line.lowercased()
        -    return line.hasPrefix("Starting CodeRabbit review")
        +    return lowered.hasPrefix("starting coderabbit review")
         }

        Review completed: 1 finding ✔
        """

        let findings = ReviewParser.parse(from: input)
        let finding = try? XCTUnwrap(findings.first)
        let diff = try? XCTUnwrap(finding?.proposedFix)

        XCTAssertEqual(findings.count, 1)
        XCTAssertNotNil(diff)
        XCTAssertEqual(finding?.proposedFixEmoji, "🔧")
        XCTAssertEqual(finding?.proposedFixTitle, "Suggested fix for consistent case handling")
        XCTAssertTrue(diff?.lines.contains(where: { $0.kind == .removed }) == true)
        XCTAssertTrue(diff?.lines.contains(where: { $0.kind == .added }) == true)
    }

    func testEmojiSuggestedNamingConventionParsesAsProposedFixBlock() {
        let input = """
        Starting CodeRabbit review in plain text mode...

        ============================================================================
        File: CodeRabbit/Assets.xcassets/Contents.json
        Line: 1 to 20
        Type: potential_issue

        Comment:
        Asset names are inconsistent.

        📁 Suggested naming convention

        -      "filename" : "coderabbitai_logo (1) (1) (1) 1.jpeg",
        +      "filename" : "icon_128x128@2x.png",
               "idiom" : "mac",
               "scale" : "2x",
               "size" : "128x128"

        -      "filename" : "coderabbitai_logo (1) (1) (1).jpeg",
        +      "filename" : "icon_256x256@1x.png",
               "idiom" : "mac",
               "scale" : "1x",
               "size" : "256x256"

        Review completed: 1 finding ✔
        """

        let findings = ReviewParser.parse(from: input)
        let finding = try? XCTUnwrap(findings.first)
        let diff = try? XCTUnwrap(finding?.proposedFix)

        XCTAssertEqual(findings.count, 1)
        XCTAssertNotNil(diff)
        XCTAssertEqual(finding?.proposedFixEmoji, "📁")
        XCTAssertEqual(finding?.proposedFixTitle, "Suggested naming convention")
        XCTAssertTrue(diff?.lines.contains(where: { $0.kind == .removed }) == true)
        XCTAssertTrue(diff?.lines.contains(where: { $0.kind == .added }) == true)
    }

    func testRateLimitPhraseInsideSuggestedCodeLineDoesNotTriggerRunError() {
        let input = """
        Starting CodeRabbit review in plain text mode...
        Connecting to review service
        Setting up
        Analyzing
        Reviewing

        ============================================================================
        File: CodeRabbit/ReviewParser.swift
        Line: 132 to 143
        Type: potential_issue

        Comment:
        isOperationalLogLine mixes case-sensitive and case-insensitive checks.

        🔧 Suggested fix for consistent case handling

         private static func isOperationalLogLine(_ line: String) -> Bool {
             let lowered = line.lowercased()
        +    return lowered.hasPrefix("failed to start review:")
        +        || lowered.contains("rate limit exceeded")
         }

        Review completed: 1 finding ✔
        """

        XCTAssertNil(ReviewParser.parseRunErrorInfo(from: input))
        XCTAssertNil(ReviewParser.parseRunFailureMessage(from: input))
    }

    func testEmojiAlternativeHeaderParsesAsProposedFixBlock() {
        let input = """
        Starting CodeRabbit review in plain text mode...

        ============================================================================
        File: CrashMyiOS/ContentView.swift
        Line: 19
        Type: potential_issue

        Comment:
        Timer runs indefinitely and cannot be stopped.

        ♻️ Alternative using conditional timer

        -    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
        +    @State private var timerCancellable: AnyCancellable?

        Review completed: 1 finding ✔
        """

        let findings = ReviewParser.parse(from: input)
        let finding = try? XCTUnwrap(findings.first)
        let diff = try? XCTUnwrap(finding?.proposedFix)

        XCTAssertEqual(findings.count, 1)
        XCTAssertNotNil(diff)
        XCTAssertEqual(finding?.proposedFixEmoji, "♻")
        XCTAssertEqual(finding?.proposedFixTitle, "Alternative using conditional timer")
        XCTAssertTrue(diff?.lines.contains(where: { $0.kind == .removed }) == true)
        XCTAssertTrue(diff?.lines.contains(where: { $0.kind == .added }) == true)
    }

    func testEmojiRecommendedApproachParsesAsProposedFixBlock() {
        let input = """
        Starting CodeRabbit review in plain text mode...

        ============================================================================
        File: Packages/MarginalenNetwork/Sources/MarginalenNetwork/Utilities/UserDefaults/UserDefaults+extensions.swift
        Line: 8 to 21
        Type: potential_issue

        Comment:
        Security risk: storing SSN in UserDefaults is insecure.

        🔒 Recommended approach: Use Keychain storage instead

        import Security

        enum KeychainHelper {
            static func save(_ value: String, forKey key: String) -> Bool {
                true
            }
        }

        Then use this helper instead of UserDefaults for the SSN.

        Review completed: 1 finding ✔
        """

        let findings = ReviewParser.parse(from: input)
        let finding = try? XCTUnwrap(findings.first)
        let diff = try? XCTUnwrap(finding?.proposedFix)

        XCTAssertEqual(findings.count, 1)
        XCTAssertNotNil(diff)
        XCTAssertEqual(finding?.proposedFixEmoji, "🔒")
        XCTAssertEqual(finding?.proposedFixTitle, "Recommended approach: Use Keychain storage instead")
        XCTAssertTrue(diff?.lines.contains(where: { $0.text.contains("import Security") }) == true)
    }

    func testProposedFixTrimsTrailingNarrativeBeforePrompt() {
        let input = """
        Starting CodeRabbit review in plain text mode...

        ============================================================================
        File: Example/ContentView.swift
        Line: 10 to 20
        Type: potential_issue

        Comment:
        This finding includes extra explanation after the diff.

        🔧 Proposed fix

        -    let value = oldValue
        +    let value = newValue

        Then keep using the helper in call sites.

        Prompt for AI Agent:
        Verify each finding against the current code and only fix it if needed.

        Review completed: 1 finding ✔
        """

        let findings = ReviewParser.parse(from: input)
        let finding = try? XCTUnwrap(findings.first)
        let diff = try? XCTUnwrap(finding?.proposedFix)

        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(diff?.lines.contains(where: { $0.kind == .removed }) == true)
        XCTAssertTrue(diff?.lines.contains(where: { $0.kind == .added }) == true)
        XCTAssertFalse(diff?.lines.contains(where: { $0.text.contains("Then keep using the helper in call sites.") }) == true)
    }

    func testInlineDiffInCommentWithoutHeaderParsesAsProposedFixBlock() {
        let input = """
        Starting CodeRabbit review in plain text mode...

        ============================================================================
        File: Marginalen/Repositories/PaymentRepository.swift
        Line: 181 to 194
        Type: potential_issue

        Comment:
        Potential state inconsistency if mapService.map throws.

        Consider whether you want to set partial state on failure or ensure consistent error handling:

         @discardableResult
         func retrieveSignedPaymentsWithRecipientsAndErrors() async throws -> SignedPaymentsFetchAggregator {
             let signedPaymentViewModels = signedPayments.payments.map(SignedPaymentViewModel.init(payment:))
        -    let mappedSignedPayments = try await mapService.map(signedPaymentViewModels, with: paymentRecipients)
        -    self.signedPayments = .success(mappedSignedPayments)
        +    do {
        +        let mappedSignedPayments = try await mapService.map(signedPaymentViewModels, with: paymentRecipients)
        +        self.signedPayments = .success(mappedSignedPayments)
        +    } catch {
        +        self.signedPayments = .failure(error)
        +        throw error
        +    }
         }

        Prompt for AI Agent:
        Verify each finding against the current code and only fix it if needed.

        Review completed: 1 finding ✔
        """

        let findings = ReviewParser.parse(from: input)
        let finding = try? XCTUnwrap(findings.first)
        let diff = try? XCTUnwrap(finding?.proposedFix)

        XCTAssertEqual(findings.count, 1)
        XCTAssertNotNil(diff)
        XCTAssertTrue(finding?.commentText.contains("Potential state inconsistency") == true)
        XCTAssertTrue(diff?.lines.contains(where: { $0.kind == .removed }) == true)
        XCTAssertTrue(diff?.lines.contains(where: { $0.kind == .added }) == true)
    }

    func testInlineExampleCodeInCommentWithoutHeaderParsesAsProposedFixBlock() {
        let input = """
        Starting CodeRabbit review in plain text mode...

        ============================================================================
        File: Marginalen BankTests/Tests/ViewModels/HomeViewModelTests.swift
        Line: 369 to 375
        Type: potential_issue

        Comment:
        Potential test flakiness: Fixed-duration sleep may be unreliable.

        // Example: wait for specific event condition instead of fixed sleep
        let eventPublisher = sut.$events.first { $0.contains(.quickBalance) }
        let events = try awaitPublisher(eventPublisher, timeout: 2.0)
        XCTAssertTrue(events.contains(.quickBalance))

        Prompt for AI Agent:
        Verify each finding against the current code and only fix it if needed.

        Review completed: 1 finding ✔
        """

        let findings = ReviewParser.parse(from: input)
        let finding = try? XCTUnwrap(findings.first)
        let diff = try? XCTUnwrap(finding?.proposedFix)

        XCTAssertEqual(findings.count, 1)
        XCTAssertNotNil(diff)
        XCTAssertTrue(finding?.commentText.contains("Potential test flakiness") == true)
        XCTAssertTrue(diff?.lines.contains(where: { $0.text.contains("let eventPublisher = sut.$events.first") }) == true)
        XCTAssertTrue(diff?.lines.contains(where: { $0.text.contains("XCTAssertTrue(events.contains(.quickBalance))") }) == true)
    }

    func testCombinedAIAgentPromptCollapsesSharedVerificationLine() {
        let promptA = """
        Verify each finding against the current code and only fix it if needed.

        In @FileA.swift around lines 10 - 20, apply fix A.
        """
        let promptB = """
        Verify each finding against the current code and only fix it if needed.

        In @FileB.swift around lines 30 - 40, apply fix B.
        """

        let combined = ReviewParser.combinedAIAgentPrompt(from: [
            makeFinding(prompt: promptA),
            makeFinding(prompt: promptB),
        ])

        XCTAssertEqual(
            combined,
            """
            Verify each finding against the current code and only fix it if needed.

            In @FileA.swift around lines 10 - 20, apply fix A.

            In @FileB.swift around lines 30 - 40, apply fix B.
            """
        )
    }

    func testCombinedAIAgentPromptReturnsPrefixWhenOnlySharedLineExists() {
        let combined = ReviewParser.combinedAIAgentPrompt(from: [
            makeFinding(prompt: ReviewParser.aiAgentVerificationPrefix)
        ])

        XCTAssertEqual(combined, ReviewParser.aiAgentVerificationPrefix)
    }

    func testCombinedAIAgentPromptIsNilWithoutPrompts() {
        let combined = ReviewParser.combinedAIAgentPrompt(from: [makeFinding(prompt: nil)])
        XCTAssertNil(combined)
    }

    private func makeFinding(prompt: String?) -> ReviewFinding {
        ReviewFinding(
            severity: .warning,
            file: "Example.swift",
            line: 1,
            lineEnd: 2,
            typeRaw: "potential_issue",
            typeDisplay: "potential_issue",
            appliesTo: nil,
            commentText: "Example finding",
            proposedFix: nil,
            aiPrompt: prompt
        )
    }
}
