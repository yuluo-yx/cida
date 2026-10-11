import XCTest

@testable import Cida

/// The target-language picker shown after 翻译 (`Design/spec/panel.md` §三).
@MainActor
final class ForeignLanguageTests: XCTestCase {
  func testTranslateShowsTheTargetPickerForAnyNonEmptySource() {
    XCTAssertTrue(AppModel(inputText: "我们的系统采用了全新的存储引擎").showsForeignLanguage)
    XCTAssertTrue(AppModel(inputText: "The new storage engine keeps every write.").showsForeignLanguage)
    XCTAssertFalse(AppModel(inputText: "  ").showsForeignLanguage)
    XCTAssertFalse(
      AppModel(mode: .improve, inputText: "我们的系统采用了全新的存储引擎").showsForeignLanguage)
  }

  func testChineseAndEnglishSourcesChooseTheOppositeTargetAutomatically() async throws {
    let model = AppModel(inputText: "我们的系统")
    XCTAssertEqual(model.foreignLanguageOption, .english)
    XCTAssertEqual(model.foreignLanguage, "English")

    model.inputText = "The new storage engine"
    try await waitUntil { model.foreignLanguageOption == .chinese }
    XCTAssertEqual(model.foreignLanguage, "简体中文")
  }

  func testExplicitKoreanOrJapaneseTargetIsNotOverwrittenByDetection() async throws {
    let model = AppModel(inputText: "我们的系统", service: ImmediateStreamingService())
    model.selectForeignLanguage(.korean)
    model.inputText = "The new storage engine"
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertEqual(model.foreignLanguageOption, .korean)

    model.selectForeignLanguage(.japanese)
    model.inputText = "我们的系统"
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertEqual(model.foreignLanguageOption, .japanese)
  }

  func testAWordingThisMacCannotRecognizeKeepsTheForeignLanguageReachable() {
    var settings = CidaSettings()
    settings.myLanguage = "克林贡语"
    let model = AppModel(inputText: "The new storage engine", settings: settings)
    XCTAssertTrue(model.showsForeignLanguage)
  }

  func testTypingIsJudgedOnceItPauses() async throws {
    let model = AppModel()
    model.sourceLanguageSettleDelay = .milliseconds(50)

    model.inputText = "我们的系统"
    XCTAssertTrue(model.showsForeignLanguage, "The picker is visible as soon as input exists")

    try await waitUntil { model.foreignLanguageOption == .english }
    XCTAssertTrue(model.animatesForeignLanguageChange, "A pause settles the source language")

    model.inputText = "The new storage engine"
    try await waitUntil { model.foreignLanguageOption == .chinese }
    XCTAssertTrue(model.showsForeignLanguage)
  }

  func testChangingMyLanguageDecidesAgainAtOnce() {
    let model = AppModel(inputText: "The new storage engine")
    XCTAssertTrue(model.showsForeignLanguage)
    XCTAssertEqual(model.foreignLanguageOption, .chinese)

    model.settings.myLanguage = "English"

    XCTAssertTrue(model.showsForeignLanguage)
    XCTAssertEqual(model.foreignLanguageOption, .chinese)
    XCTAssertFalse(model.animatesForeignLanguageChange)
  }

  func testTabWritesTheLanguageOutAndInButShowingThePanelDoesNot() {
    let model = AppModel(inputText: "我们的系统")

    model.toggleMode()
    XCTAssertFalse(model.showsForeignLanguage)
    XCTAssertTrue(model.animatesForeignLanguageChange)

    model.resetModeToDefault()
    XCTAssertTrue(model.showsForeignLanguage)
    XCTAssertFalse(model.animatesForeignLanguageChange)
  }

  func testABroughtInSelectionIsDecidedBeforeThePanelAppears() {
    let service = RecordingStreamingService()
    let model = AppModel(inputText: "The old source", service: service)
    model.sourceLanguageSettleDelay = .seconds(60)

    XCTAssertTrue(model.importSelection("我们的系统采用了全新的存储引擎"))

    XCTAssertTrue(model.showsForeignLanguage)
    XCTAssertFalse(model.animatesForeignLanguageChange)
  }

  func testANewLanguageIsKeptAndTranslatesTheSourceAgain() async throws {
    let service = RecordingStreamingService()
    var saved: [CidaSettings] = []
    let model = AppModel(
      inputText: "我们的系统采用了全新的存储引擎", service: service,
      saveSettings: { saved.append($0) })

    model.selectForeignLanguage(.japanese)

    XCTAssertFalse(model.isEditingForeignLanguage)
    XCTAssertEqual(model.foreignLanguage, "日本語")
    try await waitUntil { !model.isProcessing && service.requests.count == 1 }
    XCTAssertEqual(service.requests.first?.foreignLanguage, "日本語")
    XCTAssertEqual(service.requests.first?.text, "我们的系统采用了全新的存储引擎")
    try await waitUntil { saved.last?.foreignLanguage == "日本語" }
  }

  func testBlankOrTheSameLanguageChangesNothing() async throws {
    let service = RecordingStreamingService()
    let model = AppModel(inputText: "我们的系统", service: service)
    let revision = model.foreignLanguageRewriteRevision

    model.selectForeignLanguage(.english)
    XCTAssertEqual(model.foreignLanguage, "English")
    XCTAssertEqual(model.foreignLanguageRewriteRevision, revision)

    model.selectForeignLanguage(.english)

    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(service.requests.isEmpty)
  }

  func testConfirmationHintOnlyPromisesARequestForAChangedNonblankLanguage() {
    let model = AppModel(inputText: "我们的系统")
    model.beginEditingForeignLanguage()
    XCTAssertEqual(model.foreignLanguageDraft, "English")
    XCTAssertFalse(model.foreignLanguageEditWillSubmit)
    model.foreignLanguageDraft = "  English  "
    XCTAssertFalse(model.foreignLanguageEditWillSubmit)
    model.foreignLanguageDraft = "  "
    XCTAssertFalse(model.foreignLanguageEditWillSubmit)
    model.foreignLanguageDraft = "日本語"
    XCTAssertTrue(model.foreignLanguageEditWillSubmit)
    model.cancelForeignLanguageEditing()
    model.beginEditingForeignLanguage()
    XCTAssertEqual(model.foreignLanguageDraft, "English", "A cancelled draft is discarded")
    model.foreignLanguageDraft = "日本語"
    model.inputText = ""
    XCTAssertFalse(model.foreignLanguageEditWillSubmit)
  }

  func testAnAbandonedEditKeepsTheLanguage() {
    let model = AppModel(inputText: "我们的系统")

    model.beginEditingForeignLanguage()
    model.cancelForeignLanguageEditing()

    XCTAssertFalse(model.isEditingForeignLanguage)
    XCTAssertEqual(model.foreignLanguage, "English")
    XCTAssertEqual(model.foreignLanguageRewriteRevision, 1)
  }

  func testTheLanguageCannotBeRewrittenWhenItIsNotShownOrARequestRuns() {
    XCTAssertTrue(AppModel(inputText: "The new storage engine").beginEditingForeignLanguage())

    let model = AppModel(inputText: "我们的系统")
    let record = ResultRecord(mode: .translate, source: "我们的系统", outputLanguage: .english)
    model.setResultForTesting(record)
    model.setGenerationStateForTesting(.waiting(entryID: record.id))
    XCTAssertFalse(model.beginEditingForeignLanguage())
  }

  private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
      guard ContinuousClock.now < deadline else {
        XCTFail("Timed out waiting for condition")
        return
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  func testSupportedLanguageMatchingKeepsLegacySettingsReadable() {
    XCTAssertEqual(SupportedTranslationLanguage.matching("简体中文"), .chinese)
    XCTAssertEqual(SupportedTranslationLanguage.matching("英式英语"), .english)
    XCTAssertEqual(SupportedTranslationLanguage.matching("한국어"), .korean)
    XCTAssertEqual(SupportedTranslationLanguage.matching("日本語"), .japanese)
  }

  func testExplicitTargetCanOverrideTheAutomaticPair() async throws {
    let service = RecordingStreamingService()
    let model = AppModel(inputText: "我们的系统", service: service)

    model.selectForeignLanguage(.chinese)

    XCTAssertEqual(model.foreignLanguageOption, .chinese)
    try await waitUntil { service.requests.count == 1 }
    XCTAssertEqual(service.requests.first?.foreignLanguage, "简体中文")
  }

  func testExplicitTargetIsUsedForAnEnglishSource() async throws {
    let service = RecordingStreamingService()
    let model = AppModel(inputText: "The new storage engine", service: service)
    model.selectForeignLanguage(.japanese)

    try await waitUntil { service.requests.count == 1 }
    XCTAssertEqual(service.requests.first?.myLanguage, "日本語")
    XCTAssertEqual(service.requests.first?.foreignLanguage, "日本語")
  }

  func testTheWordIsWrittenGlyphByGlyphWithTheResultsStroke() {
    XCTAssertEqual(WriteInRenderer.duration(glyphs: 1), CidaMotion.characterInSeconds, accuracy: 1e-9)
    XCTAssertEqual(
      WriteInRenderer.duration(glyphs: "English".count), 0.120 + 6 * 0.020, accuracy: 1e-9)
  }
}

private final class RecordingStreamingService: TextProcessingService, @unchecked Sendable {
  private let lock = NSLock()
  private var recordedRequests: [ProcessingRequest] = []

  var requests: [ProcessingRequest] {
    lock.withLock { recordedRequests }
  }

  func stream(
    _ request: ProcessingRequest,
    settings: CidaSettings
  ) -> AsyncThrowingStream<String, Error> {
    lock.withLock { recordedRequests.append(request) }
    return AsyncThrowingStream { continuation in
      continuation.yield("Translated")
      continuation.finish()
    }
  }
}
