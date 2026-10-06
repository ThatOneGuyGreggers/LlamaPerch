Use these rules when designing or modifying an application's UI. Sources: [[AI Coding UI Guidelines Sources]].
## Process
1. Inspect the existing framework, components, tokens, icons, typography, and comparable screens. Preserve a coherent existing design unless asked to redesign it.
2. Identify the primary user, task, content, actions, target OS, window sizes, and required states.
3. For new products, choose a deliberate visual direction suited to the product; do not assemble a generic template.
4. Build the primary workflow with semantic structure and native controls before adding polish.
5. Run and inspect the rendered UI. Test realistic content, supported sizes, keyboard use, themes, and target platforms.
## Design
- Make each screen's purpose, primary content, and primary action obvious.
- Create hierarchy with layout, spacing, typography, and contrast before decoration.
- Keep related controls together; reveal advanced options only when needed.
- Use a consistent grid, spacing scale, type scale, color roles, and icon family.
- Preserve useful density in productivity software. Reflow or collapse secondary content as space decreases.
- Use system fonts for native apps and legible monospace fonts for code or fixed-width data.
- Use semantic colors for accent, selection, success, warning, and danger; never rely on color alone.
- Use effects and motion only to clarify hierarchy, state, or spatial relationships.
- Prefer familiar controls and existing components. Do not imitate native controls poorly.
- Label actions with specific verbs. Keep one primary button per local action group.
- Keep field labels visible, preserve input after errors, and explain recovery.
- Use lists for collections and tables for comparing aligned values.
- Use modal dialogs only when users must decide before continuing. Support undo where practical.
- Show clear focus, selection, loading, empty, success, error, disabled, offline, and permission states when relevant.
- Preserve standard editing and OS shortcuts. Essential actions must not depend on hover or dragging.
## Avoid
- Generic combinations of oversized headings, floating cards, gradient buttons, and decorative dashboards.
- Unnecessary cards, nested panels, sidebars, pills, borders, fake metrics, or filler imagery.
- Applying mobile or marketing-page layouts to desktop software.
- Visual novelty that harms native behavior, clarity, density, performance, or accessibility.
## Platform
Share product identity across platforms, but adapt controls, menus, windows, terminology, and shortcuts.
- **macOS:** Follow Apple HIG. Use the system menu bar, standard toolbars, sidebars, sheets, dialogs, file panels, and SF Symbols. Use `⌘` shortcuts and `⌘,` for Settings. Respect appearance, accent, contrast, transparency, and motion settings. Support Full Keyboard Access and VoiceOver.
- **Windows:** Follow Windows/Fluent guidance. Preserve title-bar behavior, Snap Layouts, system dialogs, and `Ctrl` shortcuts. Use Windows terminology. Respect display scaling, contrast themes, appearance, and motion settings. Support UI Automation and Narrator.
- **Linux:** Target named desktops/toolkits. Follow GNOME HIG for GTK and KDE HIG for Qt. Respect system fonts, themes, icons, scaling, and window decorations. Do not assume a distribution, shell, package manager, compositor, or control position. Account for Wayland/X11 and sandboxes where relevant. Support AT-SPI and Orca.
## Accessibility
- Make every function keyboard accessible with visible, logical focus.
- Prefer semantic native controls; expose names, roles, values, states, relationships, and errors.
- Meet WCAG 2.2 AA contrast: $4.5:1$ for normal text and $3:1$ for large text and essential controls.
- Support text scaling, zoom, dark mode, high contrast, and reduced motion without losing content or function.
- Provide alternatives to color-only cues, hover, precise dragging, and complex gestures.
- Test with the target OS screen reader.
## Completion
Before finishing, verify that the UI fits the product, reuses its design system, covers relevant states, adapts to supported sizes, follows target-OS conventions, works by keyboard and screen reader, respects accessibility settings, and has been visually inspected while running.
