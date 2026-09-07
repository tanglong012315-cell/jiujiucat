# Nvwa

`Nvwa` is PawFolio's standalone SwiftUI design-system package. It targets
iOS 17+ and mirrors the current Nvwa Figma library without Web views,
embedded pages, or JavaScript.

## Source of truth

- Figma file: `B7QSpRFNAt2tZ6S2JiG3Ij`
- System Colors: `2013:4824`
- Components canvas: `2014:7053`
- Input canvas: `2052:7149`
- Navigation section: `2102:1075`
- Navigation / Profile: `2102:1169`
- Navigation / Secondary: `2102:1102`
- Exact token snapshot: [`FIGMA_TOKENS.md`](FIGMA_TOKENS.md)
- Component nodes and variant matrix:
  [`FIGMA_COMPONENTS.md`](FIGMA_COMPONENTS.md)

These sources were read through the official Figma MCP on 2026-09-03. The
current local collection contains 28 colour variables with Light and Dark
modes.

The node `2106:1212` in the previously shared URL is stale or invalid in the
current file. Use the valid canvas and section nodes above when inspecting or
implementing the library.

## Implementation contract

- Match an existing Nvwa token or component before adding local feature styling.
- Figma is authoritative for published variants, geometry, and bindings.
- Keep host-only runtime capabilities clearly identified as code extensions;
  they are not additional Figma variants.
- Do not infer colours from legacy names. In particular, `Primary Green` now
  resolves to blue (`#0051FE` Light, `#2D66F0` Dark).
- Do not recreate the removed Bright Green and Forest Green variables. Hidden
  Boolean paths can retain old paints, but visible components bind to current
  Nvwa variables.
- Key Feature is a closed set of nine component-owned illustrations from node
  `2029:9063`: Invest, Keep, Convert, Send, Receive, Add, Close, Tick, Warning.
  Do not substitute Remix glyphs or reintroduce removed Feature variants.

## Usage

```swift
import Nvwa

NvwaButton("Next", kind: .primary, size: .large) {
    continueFlow()
}

NvwaCheckbox(
    "Include dividends",
    isChecked: $includesDividends,
    checkedIcon: Image("IconCheckboxFill"),
    uncheckedIcon: Image("IconCheckboxBlank")
)

NvwaNavigationBar(
    profileInitials: "PF",
    addIcon: Image("IconAdd"),
    profileAccessibilityLabel: "Open profile",
    addAccessibilityLabel: "Add holding",
    onProfile: openProfile,
    onAdd: addHolding
)

NvwaNavigationBar(
    guestIcon: Image("HostGuestIcon"),
    addIcon: Image("IconAdd"),
    guestAccessibilityLabel: "Log in",
    addAccessibilityLabel: "Add holding",
    onLogin: openLogin,
    onAdd: addHolding
)

NvwaKeyFeatureIcon(.invest)
```

PawFolio already bundles Inter Regular, Medium, SemiBold, and Bold using the
PostScript names consumed by this package. Another host must bundle the same
font files or deliberately provide an equivalent typography policy.

## Component inventory

- `NvwaButton` — Primary, Secondary, Outline, Warning, and Outline Warning;
  Huge, Large, Small, and Tiny.
- `NvwaTooltip` — Top, Bottom, Left, and Right, with optional action.
- `NvwaToggle` and `NvwaAvatar`.
- `NvwaTag`, `NvwaSegmentControl`, and `NvwaCheckbox`.
- `NvwaHint`, `NvwaToast`, `NvwaSection`, and `NvwaSlider`.
- `NvwaTextDropdownButton`, `NvwaBackgroundDropdownButton`, and
  `NvwaDropdownMenu` — the three dropdown families from Section `2070:825`;
  Remix chevron/check artwork is injected by the host.
- `NvwaModalHeader` and `NvwaKeyFeatureIcon`.
- `NvwaNavigationBar` — Profile and Secondary.
- `NvwaInputField`, `NvwaSearchInput`, `NvwaDateInput`, and `NvwaFlagInput`.
- `NvwaCalendar` and its month, year, and decade navigation.
- `NvwaReorderState`, `NvwaReorderLayout`, and `.nvwaReorderable(...)` — the public,
  code-only sortable-list API. One state value belongs to each independent list; the
  modifier owns tap suppression, scroll-safe long press, target projection, axis
  locking, local pointer translation, displacement animation, and the lifted-item
  treatment. Gesture and styling primitives stay private so feature code cannot
  accidentally rebuild only part of the interaction.

The exact authored combinations and measurements are in
[`FIGMA_COMPONENTS.md`](FIGMA_COMPONENTS.md). For example, Figma currently
defines Large + Leading only for Outline Button; Huge has no icon variants,
and broader Swift API support is a
code extension, not evidence of an additional design-library variant.

## Icons and runtime extensions

Nvwa ships no general icon set. Host applications inject functional icons from
[Remix Icon](https://remixicon.com/), including button, input, navigation,
calendar, checkbox, and other semantic glyphs. The nine Key Feature glyphs are
the explicit exception: they are Figma-authored illustration artwork owned by
that component and bundled privately alongside the Tooltip pointer. Hosts are
responsible for retaining the Remix Icon licence for their own packaged assets.

Figma currently has no button pressed/loading/disabled, toggle-disabled,
checkbox-indeterminate, or slider-state variants. Generic Segment data and
selection, expanded-width layouts, arbitrary Avatar sizing, Hint highlighting,
arbitrary Modal actions, Slider bindings/ranges/accessibility, Calendar
localization/synchronization, and runtime press/accessibility behavior are
code-only extensions. Reorder gestures and their lifted-item presentation are
also runtime extensions rather than Figma-authored component variants.
