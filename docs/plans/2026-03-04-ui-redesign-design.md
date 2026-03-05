# UI Redesign: macOS-Native Settings, Onboarding & Shortcuts

## Goal

Modernize the Settings window, Onboarding card, and Shortcuts panel to match macOS System Settings aesthetic. Pure CSS changes + minor HTML restructuring in main.ts. No new dependencies.

## Design Direction

macOS Ventura+ System Settings inspired. Light theme, grouped inset cards, toggle switches, translucent sidebar, clean typography.

## Color Palette

| Token | Value | Usage |
|-------|-------|-------|
| `--bg-page` | `#f5f5f7` | Content area background |
| `--bg-card` | `#ffffff` | Grouped settings cards |
| `--bg-sidebar` | `rgba(246,246,248,0.8)` | Sidebar with blur |
| `--bg-input` | `#f0f0f2` | Input fields at rest |
| `--text-primary` | `#1d1d1f` | Headings, labels |
| `--text-secondary` | `#86868b` | Hints, descriptions |
| `--accent` | `#007aff` | Primary buttons, active states |
| `--accent-hover` | `#0063d1` | Button hover |
| `--border` | `rgba(0,0,0,0.06)` | Subtle card/input borders |
| `--shadow-card` | `0 0.5px 1px rgba(0,0,0,0.1)` | Card elevation |
| `--success` | `#34c759` | Success status |
| `--error` | `#ff3b30` | Error status |
| `--recording` | `#ff3b30` | Recording indicator |

## Settings Window

### Sidebar
- `backdrop-filter: blur(20px)` + `--bg-sidebar`
- 1px right border in `--border`
- Nav items: 32px height, 8px border-radius, 8px horizontal padding
- Active item: `--accent` background at 12% opacity, `--accent` text color
- Unicode icons before labels: Agents (grid), Settings (gear), Shortcuts (keyboard), About (info)
- 12px gap between items, 20px top padding

### Content Area
- Background: `--bg-page`
- Max-width 640px, centered with 32px padding

### Grouped Cards
- White background, 10px border-radius, `--shadow-card`
- 16px internal padding
- Stacked vertically with 24px gap between groups
- Section label above each group: 12px uppercase, `--text-secondary`, 600 weight, 8px bottom margin

### Form Inputs
- Background: `--bg-input`, no border, 8px border-radius
- 10px vertical / 12px horizontal padding
- On focus: 2px `--accent` ring (box-shadow), white background
- Font: system, 14px

### Toggle Switches (replace checkboxes)
- 44px wide, 26px tall, 13px border-radius
- Off: `#e5e5ea` background, white circle
- On: `--accent` background, white circle translated right
- 200ms transition
- Label text to the right, vertically centered

### Agent Cards
- Inside grouped card container
- Each agent: flex row, 12px padding, 8px border-radius
- 40px rounded avatar circle (colored background, white initials)
- Name + meta stacked vertically
- Edit/Delete as small icon buttons, visible on hover only
- Hover state: `rgba(0,0,0,0.03)` background

### Buttons
- Primary: `--accent` background, white text, 8px radius, 10px/20px padding
- Secondary: transparent background, `--accent` text, 1px `--accent` border
- Danger: `--error` text, transparent background
- All: 14px font, 500 weight, 200ms hover transition

## Onboarding (First-Run Card)

- Page: centered on `--bg-page` background
- Card: white, 16px radius, `0 8px 32px rgba(0,0,0,0.08)` shadow
- 48px padding all sides, max-width 400px
- Top: styled app name "Toro Libre" in 28px/600 weight
- Below: "Set up your instance to get started" in `--text-secondary`, 15px
- Button: full-width `--accent` filled button, 12px radius, 44px height
- 32px gap between text block and button

## Shortcuts Panel

### Key-Cap Visualization
- Replace readonly input with styled key display
- Each key segment: inline-block, `#e8e8ed` background, `#f8f8fa` top gradient (3D effect)
- 1px solid `#c8c8cc` border, 2px bottom border (depth)
- 8px radius, 8px/12px padding, monospace font, 14px
- Keys separated by `+` character in `--text-secondary`

### Recording State
- Key display gets pulsing 2px `--recording` border
- "Recording..." label with animated red dot (8px circle, pulse animation)
- Background tint: `rgba(255,59,48,0.04)`

### Button Row
- Record: secondary button, becomes red-tinted during recording
- Reset Default: ghost button (text only, no border)
- Save: primary blue button
- 12px gap between buttons, flex row

## Files to Modify

1. `src/styles.css` — Complete restyle of settings, first-run, shortcuts CSS
2. `src/main.ts` — HTML generation changes:
   - Add sidebar icons
   - Replace checkbox HTML with toggle switch markup
   - Replace shortcut input with key-cap display markup
   - Update first-run card HTML
   - Update agent card hover behavior

## Out of Scope

- Dark mode (future enhancement)
- Launcher/spotlight redesign (not requested)
- New dependencies or frameworks
- Backend changes
