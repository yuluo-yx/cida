import SwiftUI

/// The translation target menu shown after the built-in 翻译 action.
/// Chinese and English are selected automatically from the source language; Korean and Japanese
/// remain selected until the user chooses another target. ⌘L keeps the legacy free-form editor
/// available for existing keyboard workflows.
struct PanelForeignLanguage: View {
  @Bindable var model: AppModel
  static let gapAfterTitle: CGFloat = 5
  static let titleOverlap = PanelSegmentedControlMetrics.titlePadding - gapAfterTitle

  @State private var isPresented = false
  /// Seconds into writing the target label; the label is fully visible at `writtenSeconds`.
  @State private var elapsed = 0.0
  /// Seconds into writing 成 in. A rewritten target leaves it as it is.
  @State private var jointElapsed = 0.0
  /// 1 while 成 is written first and the target follows it, 0 when only the target is shown.
  @State private var languageFirstGlyph = 0
  /// 0 while the target is on screen, 1 once it has faded out.
  @State private var fade = 0.0
  @State private var targetWidth: CGFloat = 0
  @State private var jointGlyphWidth: CGFloat = 0
  @State private var draftWidth: CGFloat = 0
  @State private var isHovered = false
  @State private var leaveTask: Task<Void, Never>?
  @FocusState private var isFieldFocused: Bool
  @FocusState private var isLanguageFocused: Bool

  var body: some View {
    content
      .offset(x: -overlap)
      .frame(width: width, alignment: .leading)
      // The target starts in the title's trailing padding, so the visible part is the frame moved
      // back by that much: nothing at zero width, the full menu once open.
      .mask(alignment: .leading) {
        Rectangle()
          .frame(width: width)
          .padding(.vertical, -4)
          .offset(x: -overlap)
      }
      .background(measurements)
      .contentShape(Rectangle())
      .onHover { isHovered = $0 }
      .focusable(!model.isEditingForeignLanguage && model.showsForeignLanguage)
      .focused($isLanguageFocused)
      .focusEffectDisabled()
      .overlay {
        if isLanguageFocused && !model.isEditingForeignLanguage {
          RoundedRectangle(cornerRadius: 2)
            .strokeBorder(CidaDesign.accent, lineWidth: 1)
        }
      }
      .help("选择翻译目标语言 · ⌘L 自定义")
      .accessibilityAction { model.beginEditingForeignLanguage() }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("要译成的语言")
      .accessibilityValue(model.foreignLanguageOption.title)
      .accessibilityHidden(!model.showsForeignLanguage)
      .accessibilityIdentifier("foreign-language")
      .onAppear {
        isPresented = model.showsForeignLanguage
        elapsed = writtenSeconds
        jointElapsed = CidaMotion.characterInSeconds
        if model.isEditingForeignLanguage { startEditing() }
      }
      .onChange(of: model.showsForeignLanguage) { _, shows in
        let animated = model.animatesForeignLanguageChange && !CidaMotion.reducesMotion
        if shows { writeIn(animated: animated) } else { leave(animated: animated) }
      }
      .onChange(of: model.foreignLanguageRewriteRevision) {
        writeIn(animated: !CidaMotion.reducesMotion, rewriting: true)
      }
      .onChange(of: model.isEditingForeignLanguage) { _, editing in
        if editing { startEditing() } else { isFieldFocused = false }
      }
      .onChange(of: isFieldFocused) { _, focused in
        if !focused { model.cancelForeignLanguageEditing() }
      }
  }

  private func startEditing() {
    Task { @MainActor in isFieldFocused = true }
  }

  private var content: some View {
    HStack(spacing: Self.gapAfterTitle) {
      if let joint {
        Text(joint)
          .font(Self.jointFont)
          .foregroundStyle(CidaDesign.accent)
          .fixedSize()
          .textRenderer(
            WriteInRenderer(
              elapsed: jointElapsed, fade: fade, blursGlyphs: !CidaMotion.reducesMotion
            )
          )
          .accessibilityHidden(true)
      }
      if model.isEditingForeignLanguage {
        editor
      } else {
        targetMenu
      }
    }
  }

  private var targetMenu: some View {
    Menu {
      ForEach(CidaSettings.supportedTranslationLanguages) { language in
        Button {
          model.selectForeignLanguage(language)
        } label: {
          if language == model.foreignLanguageOption {
            Label(language.title, systemImage: "checkmark")
          } else {
            Text(language.title)
          }
        }
        .accessibilityIdentifier("foreign-language-option-\(language.rawValue)")
      }
    } label: {
      HStack(spacing: 3) {
        Text(model.foreignLanguageOption.title)
          .font(Self.font)
          .foregroundStyle(CidaDesign.textSecondary)
          .underline(isHovered, color: CidaDesign.textSecondary)
          .textRenderer(
            WriteInRenderer(
              elapsed: elapsed, fade: fade, blursGlyphs: !CidaMotion.reducesMotion,
              firstGlyph: languageFirstGlyph
            )
          )
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(CidaDesign.textTertiary)
      }
      .fixedSize()
    }
    .menuStyle(.borderlessButton)
    .buttonStyle(.plain)
    .accessibilityLabel("要译成的语言")
    .accessibilityValue(model.foreignLanguageOption.title)
    .accessibilityIdentifier("foreign-language-picker")
    .help("选择翻译目标语言")
  }

  private var editor: some View {
    TextField("", text: $model.foreignLanguageDraft)
      .textFieldStyle(.plain)
      .font(Self.font)
      .foregroundStyle(CidaDesign.textPrimary)
      .focused($isFieldFocused)
      .onSubmit {
        if let window = NSApp.keyWindow, InputMethodRouting.isComposing(in: window) { return }
        model.commitForeignLanguage(model.foreignLanguageDraft)
      }
      .frame(width: max(24, draftWidth + 2), alignment: .leading)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(CidaDesign.textTertiary)
          .frame(height: 1)
          .offset(y: 2)
      }
      .accessibilityLabel("要译成的语言")
      .accessibilityIdentifier("foreign-language-editor")
      .help(model.foreignLanguageConfirmationHint)
  }

  private var measurements: some View {
    ZStack {
      Text("成").font(Self.jointFont).fixedSize()
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { jointGlyphWidth = $0 }
      HStack(spacing: 3) {
        Text(model.foreignLanguageOption.title).font(Self.font)
        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
      }
      .fixedSize()
      .onGeometryChange(for: CGFloat.self, of: \.size.width) { targetWidth = $0 }
      Text(model.foreignLanguageDraft.isEmpty ? " " : model.foreignLanguageDraft)
        .font(Self.font).fixedSize()
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { draftWidth = $0 }
    }
    .hidden()
    .accessibilityHidden(true)
  }

  private static let font = CidaDesign.mainUI(11.5, weight: .medium)
  private static let jointFont = CidaDesign.mainUI(11.5, weight: .semibold)

  private var joint: String? {
    let name = model.settings.actions.first { $0.id == .translate }?.name
    return name == ProcessingMode.translate.title ? "成" : nil
  }

  /// How far into the title's trailing padding the content starts: 成 sits against the verb.
  private var overlap: CGFloat {
    joint == nil ? Self.titleOverlap : PanelSegmentedControlMetrics.titlePadding
  }

  /// 成 and the target menu, then the segment's own trailing padding.
  private var width: CGFloat {
    let joint = joint == nil ? 0 : jointGlyphWidth + Self.gapAfterTitle
    let trailing = PanelSegmentedControlMetrics.titlePadding - overlap
    if model.isEditingForeignLanguage { return joint + draftWidth + 2 + trailing }
    return isPresented ? joint + targetWidth + trailing : 0
  }

  private var writtenSeconds: Double {
    WriteInRenderer.duration(glyphs: languageFirstGlyph + model.foreignLanguageOption.title.count)
  }

  /// The segment opens to its final width while the target label is written in one after another.
  private func writeIn(animated: Bool, rewriting: Bool = false) {
    leaveTask?.cancel()
    languageFirstGlyph = joint != nil && !rewriting ? 1 : 0
    guard animated else {
      withAnimation(nil) {
        isPresented = true
        elapsed = writtenSeconds
        jointElapsed = CidaMotion.characterInSeconds
      }
      if CidaMotion.reducesMotion {
        fade = 1
        withAnimation(.linear(duration: CidaMotion.iconSwapSeconds)) { fade = 0 }
      } else {
        fade = 0
      }
      return
    }
    fade = 0
    elapsed = 0
    withAnimation(CidaMotion.heightCurve.animation(duration: CidaMotion.heightSeconds)) {
      isPresented = true
    }
    withAnimation(.linear(duration: writtenSeconds)) { elapsed = writtenSeconds }
    if !rewriting {
      jointElapsed = 0
      withAnimation(.linear(duration: CidaMotion.characterInSeconds)) {
        jointElapsed = CidaMotion.characterInSeconds
      }
    }
  }

  /// The target fades out whole; halfway through, the segment closes behind it.
  private func leave(animated: Bool) {
    leaveTask?.cancel()
    guard animated else {
      if CidaMotion.reducesMotion, isPresented {
        withAnimation(.linear(duration: CidaMotion.iconSwapSeconds)) { fade = 1 }
        leaveTask = Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(CidaMotion.iconSwapMilliseconds))
          guard !Task.isCancelled else { return }
          isPresented = false
        }
      } else {
        isPresented = false
      }
      return
    }
    withAnimation(CidaMotion.characterInCurve.animation(duration: CidaMotion.characterInSeconds)) {
      fade = 1
    }
    leaveTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(CidaMotion.characterInMilliseconds / 2))
      guard !Task.isCancelled else { return }
      withAnimation(CidaMotion.heightCurve.animation(duration: CidaMotion.heightSeconds)) {
        isPresented = false
      }
    }
  }
}

/// Draws a word glyph by glyph as the result streams in: each glyph fades in and sharpens over
/// `motion-char-in-ms`, the next one `motion-language-stagger-ms` later; `fade` takes the whole
/// word out again with the same blur. `firstGlyph` counts the glyphs written before this word.
struct WriteInRenderer: TextRenderer, Animatable {
  var elapsed: Double
  var fade: Double
  var blursGlyphs: Bool
  var firstGlyph = 0

  var animatableData: AnimatablePair<Double, Double> {
    get { AnimatablePair(elapsed, fade) }
    set {
      elapsed = newValue.first
      fade = newValue.second
    }
  }

  static let stagger = Double(CidaMotion.languageStaggerMilliseconds) / 1_000

  /// How long a word of `glyphs` takes to be written in full.
  static func duration(glyphs: Int) -> Double {
    Double(max(0, glyphs - 1)) * stagger + CidaMotion.characterInSeconds
  }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    var index = firstGlyph
    for line in layout {
      for run in line {
        for glyph in run {
          let time = (elapsed - Double(index) * Self.stagger) / CidaMotion.characterInSeconds
          let written = CidaMotion.characterInCurve.progress(at: time)
          var glyphContext = context
          glyphContext.opacity = written * (1 - fade)
          if blursGlyphs {
            let blur = CidaMotion.characterBlurRadius * CGFloat(max(1 - written, fade))
            if blur > 0.01 { glyphContext.addFilter(.blur(radius: blur)) }
          }
          glyphContext.draw(glyph)
          index += 1
        }
      }
    }
  }
}
