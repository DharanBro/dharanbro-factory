# UI craft

Read before your first UI slice. The repo's design system (disco-ui components and variants, its tokens, type scale, colours, depth, radius and motion) wins over anything here. This guide covers what the design system leaves to you: hierarchy, composition, states, reuse and polish.

# Intent First

Before touching code, answer these.

- **Who is this human?** Not "users." The actual person. Where are they when they open this? What did they do 5 minutes ago, what will they do 5 minutes after? A dispatcher at 7am with a queue is not an admin fixing config at midnight.
- **What must they accomplish?** The verb. Find the late order. Assign the trip. Approve the change. The answer determines what leads, what follows, what hides.

Defaults hide in the parts that feel like infrastructure:

- **Navigation feels like scaffolding.** But navigation *is* the product: where you are, where you can go, what matters. A page floating in space is a component demo, not software.
- **Data feels like presentation.** But a number on screen is not design. What does it *mean* to the person looking? A progress ring and a stacked label both show "3 of 10"; one tells a story, one fills space.

# Visual Hierarchy & Composition

The single biggest driver of "this looks designed" versus "this looks generated." Defaults produce *flatness*: everything the same size, weight, and spacing, so nothing leads and the eye has nowhere to go. Craft produces *hierarchy*: the eye knows instantly what matters.

## One focal point per view

Every screen has one thing the user came to do. That thing dominates through size, contrast, position, or the space around it. When everything competes equally, nothing wins. Before building, name the focal element. Then make it win: bigger, higher-contrast, or ringed in whitespace. Demote everything else deliberately.

## Weight beats size

Use the design system's type scale; never pick sizes by feel. **Weight and color do more hierarchy work than size.** A single 14px size holds three tiers through weight + opacity alone (`value: 600 / primary`, `label: 500 / secondary`, `meta: 400 / muted`), separating more cleanly than two regular weights two points apart. Build from three levers together (size, weight, color/opacity), never size alone. If you squint and can't tell headline from body from label, the hierarchy is too weak.

Worked example, a metric, flat vs decided. *Flat:* `Revenue` / `$48,200` both 14px regular gray, three identical boxes, no focal point. *Decided:* `REVENUE` 11px/500/muted · `$48,200` 28px/600/primary/tabular-nums (the hero) · `↑12%` 12px/500/success. Same data, opposite legibility.

## Density is a decision

A tool panel at 12–16px padding feels workbench-tight; the same card at 24px feels like a brochure. In an existing app, match the density of the screens around yours and hold it.

## Spatial rhythm: breathe unevenly

Dense control zones give way to open content; heavy elements balance against light ones. Monotone layouts (same card size, same gap, same density everywhere) are the sound of no one deciding. Group tightly related things, then put real air between groups.

## Proportions speak

A 280px sidebar next to full-width content says "navigation serves content." A 360px sidebar says "these are peers." Choose widths and ratios that state a relationship.

## Distribution and restraint

- **~60/30/10**: a dominant neutral surface, a secondary tone, and ~10% accent. Most of the screen is structure.
- **One accent, used with intention**, beats five colors used without thought. Gray builds structure; color *communicates* (status, action, identity). Unmotivated color is noise.
- **Hierarchy through space and weight, not lines.** Reach for whitespace and tonal shift before borders and dividers.

# Before Writing Each Component

Decide, briefly and without writing it into the code:

```
Task:       [who, and the verb they came to do]
Hierarchy:  [the focal element, and how it wins: size / weight / contrast / space]
Reuse:      [the existing components, variants and tokens you will use]
States:     [which of hover, focus, disabled, loading, empty, error apply]
```

# Use What Exists

The most common way AI degrades a codebase: it hand-rolls what already exists. A bespoke `<div onClick>` "button" beside the project's real `Button`. A from-scratch dropdown with no keyboard support beside an installed primitive that has it. A 14-class Tailwind string copy-pasted onto every card instead of the component or token that's right there. **Before you build a control or style an element, look at what the project already gives you.**

## Controls: native → primitive → hand-roll

1. **Native HTML first** where it works. A `<button>` is a button; an `<a>` is a link; `<input type="text">`, `<dialog>`, `<details>` exist. Never `<div onClick>` something the platform already provides; you lose focus, keyboard, and semantics.
2. **The design system's component, or an installed headless primitive,** for anything stateful and hard to get right: select, combobox, dialog, popover, tooltip, dropdown menu, tabs, date picker. These ship keyboard navigation, focus management, ARIA, and positioning that take days to reproduce. "Build custom" means *compose and style a primitive*, not write the behavior from scratch.
3. **Hand-roll only as a last resort.** Then you owe the complete behavior contract: keyboard nav (arrow keys, Enter, Escape), focus trap/return, full ARIA roles and state, click-outside, and scroll-lock for overlays.

## Styling: system → component → token → utility

1. **Use the design system.** disco-ui components, a CVA variant set, the theme: use `<Button variant="…">` and the existing variants before writing a one-off. Match the codebase's styling convention; don't introduce your own.
2. **When a styled element repeats, extract a component.** The same utility string on nine buttons is duplication. One component (or one CVA variant) owns it. Extract on the second real reuse, not the first.
3. **Bind to semantic tokens, not hardcoded literals.** `bg-card border-border text-muted-foreground`, not `bg-white border-gray-200 text-gray-500`. Raw values break theming and dark mode.
4. **Inline utilities are for genuine one-offs.** The same long className sprayed everywhere is a missing component or token.

# Where the design system has no answer

Use these only for gaps; where the design system has a value, it wins.

- **Text hierarchy, four levels:** primary, secondary, tertiary, muted (default / supporting / metadata / disabled). Using only two means the hierarchy is too flat.
- **Spacing:** the base unit's multiples only. Random values signal no system.
- **Padding:** symmetrical unless content genuinely demands asymmetry.
- **Depth:** match the strategy the app already uses (borders, shadows, or surface shifts); don't mix.
- **Radius:** small for inputs and buttons, medium for cards, large for modals.

# Polish & Motion Essentials

## Static polish

- **Concentric radius.** Nested rounded elements: `outerRadius = innerRadius + padding`. Same radius on parent and child makes UI feel off.
- **Tabular numbers.** Any dynamic number (counters, prices, timers, table columns) gets `font-variant-numeric: tabular-nums` to prevent layout shift.
- **Optical alignment.** When geometric centering looks off, fix it optically: icon-side padding ≈ text-side − 2px.
- **States are not optional.** Every interactive element needs default, hover, active, focus, disabled. Data needs loading, empty, error. Missing states are the fastest tell of an unfinished interface.
- **Hit areas: 44×44px (WCAG), 40 at minimum.** If the visible control is smaller, extend it with a pseudo-element. Never let two hit areas overlap.
- **Text wrapping.** `text-wrap: balance` on headings; `text-wrap: pretty` on body and captions.

## Motion

Use the design system's motion tokens when it has them. Motion should be felt, not watched.

- **Should it animate at all?** Actions repeated 100+ times a day (keyboard shortcuts, command palette) get **no** animation. Occasional surfaces (modals, drawers, toasts) get standard animation.
- **Duration < 300ms** for UI. Button press 100–160ms; tooltips/popovers 125–200ms; dropdowns 150–250ms; modals/drawers 200–500ms.
- **Ease-out, never ease-in.** `cubic-bezier(0.23, 1, 0.32, 1)` for entering/interactive; ease-in-out for on-screen movement.
- **Never animate from `scale(0)`.** Start at `scale(0.95)` + `opacity: 0`.
- **Origin-aware popovers.** Popovers scale from their trigger, not center. Modals stay centered.
- **Only animate `transform` and `opacity`.** Never `transition: all`; name exact properties.
- **Respect `prefers-reduced-motion`:** keep opacity/color transitions, drop movement.

# Avoid

- **Harsh borders:** if borders are the first thing you see, they're too strong
- **Flat hierarchy:** everything one size/weight; no clear focal point
- **Monotone layout:** same card size, gap, and density everywhere
- **Inconsistent spacing:** the clearest sign of no system
- **Mixed depth strategies**
- **Missing states:** hover, focus, disabled, loading, empty, error
- **Dramatic drop shadows; large radius on small elements; thick decorative borders**
- **Gradients and color for decoration:** color should mean something
- **Multiple accent colors**
- **Structural hacks:** negative margins undoing parent padding, escape-hatch `calc()`, absolute positioning to dodge layout flow

# Check before finishing a UI slice

- **Squint test:** blur your eyes. Hierarchy still readable? Nothing jumping out harshly?
- **Reuse test:** every control is a design-system component or native element; no hardcoded colors or spacing.
- **States test:** every new interactive element and data view has its states.

---

Adapted from [interface-design](https://github.com/Dammyjay93/interface-design) (`.claude/skills/interface-design/SKILL.md`, commit `2f9be32`): human-facing workflow, new-direction exploration and design-system-level rules removed, examples and a few lines changed to fit Encore and defer to the repo's design system. Original licence:

```text
MIT License

Copyright (c) 2026 Damola Akinleye

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
