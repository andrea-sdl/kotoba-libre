# UI Redesign: macOS-Native Settings, Onboarding & Shortcuts

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Modernize Settings, Onboarding, and Shortcuts screens with macOS System Settings-inspired styling.

**Architecture:** Pure CSS + HTML template changes in vanilla TS. No new dependencies. Two files to modify: `src/styles.css` (complete restyle) and `src/main.ts` (HTML template updates for sidebar icons, toggle switches, key-cap display, and polished first-run card).

**Tech Stack:** Vanilla TypeScript, CSS3 (backdrop-filter, custom properties, transitions)

---

### Task 1: Add CSS Custom Properties and Update Base Styles

**Files:**
- Modify: `src/styles.css:1-38`

**Step 1: Replace root styles and add custom properties**

Replace lines 1-38 of `src/styles.css` with:

```css
:root {
  /* Colors */
  --bg-page: #f5f5f7;
  --bg-card: #ffffff;
  --bg-sidebar: rgba(246, 246, 248, 0.8);
  --bg-input: #f0f0f2;
  --text-primary: #1d1d1f;
  --text-secondary: #86868b;
  --text-tertiary: #aeaeb2;
  --accent: #007aff;
  --accent-hover: #0063d1;
  --accent-active: #004ea3;
  --border: rgba(0, 0, 0, 0.06);
  --border-input: rgba(0, 0, 0, 0.1);
  --shadow-card: 0 0.5px 1px rgba(0, 0, 0, 0.1);
  --shadow-card-hover: 0 1px 3px rgba(0, 0, 0, 0.12);
  --success: #34c759;
  --error: #ff3b30;
  --warning-bg: #fffbf0;
  --warning-border: #f0d39b;
  --warning-text: #79551a;
  --radius-sm: 6px;
  --radius-md: 8px;
  --radius-lg: 12px;
  --radius-xl: 16px;
  --transition: 200ms ease;

  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
  color: var(--text-primary);
  background: var(--bg-page);
  text-rendering: optimizeLegibility;
  font-synthesis: none;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

* {
  box-sizing: border-box;
}

html,
body {
  margin: 0;
  padding: 0;
}

body {
  min-height: 100vh;
  font-size: 14px;
  line-height: 1.5;
}

code {
  font-family: "SF Mono", Menlo, Monaco, monospace;
  font-size: 0.875em;
}

button,
input,
select {
  font: inherit;
}

.hidden {
  display: none !important;
}
```

**Step 2: Verify the file saves correctly**

Run: `head -60 src/styles.css`

---

### Task 2: Restyle Status, Hints, Actions, and Form Inputs

**Files:**
- Modify: `src/styles.css:40-101` (the .status, .hint, .actions, .checkbox-row, input, .pill, .empty blocks)

**Step 1: Replace utility and form base styles**

Replace the `.status` through `.empty` block (old lines 40-100) with:

```css
.status {
  min-height: 1.3rem;
  margin: 0;
  color: var(--success);
  font-size: 0.8125rem;
}

.status.error,
.hint.error {
  color: var(--error);
}

.hint {
  color: var(--text-secondary);
  font-size: 0.8125rem;
}

.actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

/* Toggle switch — replaces raw checkboxes */
.toggle-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 2px 0;
}

.toggle-row span {
  flex: 1;
  font-size: 0.875rem;
}

.toggle-switch {
  position: relative;
  width: 42px;
  height: 26px;
  flex-shrink: 0;
}

.toggle-switch input {
  opacity: 0;
  width: 0;
  height: 0;
  position: absolute;
}

.toggle-slider {
  position: absolute;
  inset: 0;
  background: #e5e5ea;
  border-radius: 13px;
  cursor: pointer;
  transition: background var(--transition);
}

.toggle-slider::before {
  content: "";
  position: absolute;
  top: 2px;
  left: 2px;
  width: 22px;
  height: 22px;
  background: white;
  border-radius: 50%;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.15);
  transition: transform var(--transition);
}

.toggle-switch input:checked + .toggle-slider {
  background: var(--accent);
}

.toggle-switch input:checked + .toggle-slider::before {
  transform: translateX(16px);
}

.toggle-switch input:focus-visible + .toggle-slider {
  outline: 2px solid var(--accent);
  outline-offset: 2px;
}

/* Keep .checkbox-row for backwards compat but hide */
.checkbox-row {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.checkbox-row input {
  width: 18px;
  height: 18px;
  margin: 0;
}

input,
select {
  border: none;
  border-radius: var(--radius-md);
  padding: 0.5rem 0.75rem;
  background: var(--bg-input);
  color: var(--text-primary);
  transition: box-shadow var(--transition), background var(--transition);
}

input:focus,
select:focus {
  outline: none;
  background: var(--bg-card);
  box-shadow: 0 0 0 3px rgba(0, 122, 255, 0.3);
}

input::placeholder {
  color: var(--text-tertiary);
}

.pill {
  display: inline-flex;
  align-items: center;
  height: 20px;
  padding: 0 0.5rem;
  border-radius: 999px;
  border: none;
  background: rgba(0, 122, 255, 0.1);
  color: var(--accent);
  font-size: 0.6875rem;
  font-weight: 600;
  letter-spacing: 0.02em;
  text-transform: uppercase;
}

.empty {
  margin: 0;
  color: var(--text-secondary);
  text-align: center;
  padding: 2rem 0;
}
```

---

### Task 3: Restyle the Settings Shell, Sidebar, and Panels

**Files:**
- Modify: `src/styles.css:102-177` (manager-page through panel-header p)

**Step 1: Replace settings layout styles**

Replace `.manager-page` through `.panel-header p` with:

```css
.manager-page {
  min-height: 100vh;
  display: grid;
  place-items: center;
  padding: 0;
}

.manager-shell {
  width: 100vw;
  height: 100vh;
  display: grid;
  grid-template-columns: 220px 1fr;
  overflow: hidden;
  background: var(--bg-page);
}

.manager-sidebar {
  background: var(--bg-sidebar);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border-right: 1px solid var(--border);
  padding: 1.25rem 0.75rem;
  display: flex;
  flex-direction: column;
}

.manager-sidebar h1 {
  margin: 0 0.5rem 1.25rem;
  font-size: 0.8125rem;
  font-weight: 600;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.sidebar-nav {
  display: grid;
  gap: 2px;
}

.sidebar-item {
  width: 100%;
  text-align: left;
  padding: 0.4375rem 0.625rem;
  border: none;
  border-radius: var(--radius-md);
  background: transparent;
  color: var(--text-primary);
  font-size: 0.875rem;
  font-weight: 400;
  cursor: pointer;
  transition: background var(--transition);
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.sidebar-item:hover {
  background: rgba(0, 0, 0, 0.04);
}

.sidebar-item.active {
  background: rgba(0, 122, 255, 0.12);
  color: var(--accent);
  font-weight: 500;
}

.sidebar-icon {
  font-size: 1rem;
  width: 1.25rem;
  text-align: center;
  flex-shrink: 0;
}

.manager-main {
  padding: 2rem 2.5rem;
  overflow: auto;
  max-width: 720px;
}

.panel {
  display: none;
}

.panel.active {
  display: block;
}

.panel-header {
  margin-bottom: 1.5rem;
}

.panel-header h2 {
  margin: 0 0 0.25rem;
  font-size: 1.5rem;
  font-weight: 600;
  letter-spacing: -0.02em;
}

.panel-header p {
  margin: 0;
  color: var(--text-secondary);
  font-size: 0.875rem;
}

.panel-header.compact h2 {
  font-size: 1.5rem;
}

.panel-header-row {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 1rem;
}
```

---

### Task 4: Restyle Cards, Agent List, and Editor

**Files:**
- Modify: `src/styles.css:182-285` (stack-card through editor-actions)

**Step 1: Replace card and agent styles**

Replace `.stack-card` through `.editor-actions` with:

```css
.section-label {
  font-size: 0.6875rem;
  font-weight: 600;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 0.5rem;
}

.stack-card,
.editor-card {
  border: none;
  border-radius: var(--radius-lg);
  padding: 1rem;
  background: var(--bg-card);
  box-shadow: var(--shadow-card);
}

.stack-card {
  display: grid;
  gap: 0.875rem;
}

.stack-card label,
.editor-card label {
  display: grid;
  gap: 0.25rem;
  font-size: 0.875rem;
  font-weight: 500;
}

.stack-card label span,
.editor-card label span {
  font-size: 0.8125rem;
  color: var(--text-secondary);
}

.instance-warning {
  border: 1px solid var(--warning-border);
  background: var(--warning-bg);
  color: var(--warning-text);
  border-radius: var(--radius-md);
  padding: 0.75rem 1rem;
  margin-bottom: 1rem;
  font-size: 0.8125rem;
}

.agent-list {
  display: grid;
  gap: 0.5rem;
  margin-bottom: 1rem;
}

.agent-card {
  border: none;
  border-radius: var(--radius-lg);
  background: var(--bg-card);
  box-shadow: var(--shadow-card);
  display: grid;
  grid-template-columns: 44px 1fr auto;
  gap: 0.75rem;
  align-items: center;
  padding: 0.75rem 1rem;
  transition: box-shadow var(--transition);
}

.agent-card:hover {
  box-shadow: var(--shadow-card-hover);
}

.agent-card.default {
  box-shadow: inset 0 0 0 2px rgba(0, 122, 255, 0.25), var(--shadow-card);
}

.agent-icon {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--accent), #5856d6);
  display: grid;
  place-items: center;
  font-size: 0.8125rem;
  font-weight: 700;
  color: white;
  letter-spacing: 0.02em;
  border: none;
}

.agent-meta h3 {
  margin: 0;
  font-size: 0.9375rem;
  font-weight: 600;
  line-height: 1.2;
}

.agent-meta p {
  margin: 0.125rem 0;
  color: var(--text-secondary);
  font-size: 0.75rem;
}

.agent-meta small {
  color: var(--text-tertiary);
  font-size: 0.75rem;
}

.agent-title-row {
  display: flex;
  align-items: center;
  gap: 0.375rem;
}

.agent-actions {
  display: flex;
  gap: 0.25rem;
  opacity: 0;
  transition: opacity var(--transition);
}

.agent-card:hover .agent-actions {
  opacity: 1;
}

.editor-grid {
  display: grid;
  gap: 0.75rem;
  grid-template-columns: repeat(2, minmax(200px, 1fr));
}

.editor-wide {
  grid-column: 1 / -1;
}

.editor-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-top: 0.75rem;
}
```

---

### Task 5: Restyle Buttons (Primary, Secondary, Danger, Star)

**Files:**
- Modify: `src/styles.css` — add button styles after the editor section

**Step 1: Add button styling rules**

Add after the editor-actions block:

```css
/* Buttons */
button {
  border: none;
  border-radius: var(--radius-md);
  padding: 0.5rem 1rem;
  font-size: 0.8125rem;
  font-weight: 500;
  cursor: pointer;
  transition: background var(--transition), color var(--transition), opacity var(--transition);
}

button[type="submit"],
button:not(.secondary):not(.danger):not(.star-toggle):not(.sidebar-item):not(.spotlight-item):not(#spotlight-open-settings) {
  background: var(--accent);
  color: white;
}

button[type="submit"]:hover,
button:not(.secondary):not(.danger):not(.star-toggle):not(.sidebar-item):not(.spotlight-item):not(#spotlight-open-settings):hover {
  background: var(--accent-hover);
}

button[type="submit"]:active,
button:not(.secondary):not(.danger):not(.star-toggle):not(.sidebar-item):not(.spotlight-item):not(#spotlight-open-settings):active {
  background: var(--accent-active);
}

button.secondary {
  background: transparent;
  color: var(--accent);
  border: 1px solid rgba(0, 122, 255, 0.3);
}

button.secondary:hover {
  background: rgba(0, 122, 255, 0.06);
}

button.danger {
  background: transparent;
  color: var(--error);
  border: 1px solid rgba(255, 59, 48, 0.3);
}

button.danger:hover {
  background: rgba(255, 59, 48, 0.06);
}

.star-toggle {
  background: none;
  border: none;
  padding: 0;
  font-size: 1.125rem;
  color: var(--text-tertiary);
  cursor: pointer;
  line-height: 1;
  transition: color var(--transition);
}

.star-toggle:hover {
  color: #ffb800;
}

.agent-card.default .star-toggle {
  color: #ffb800;
}
```

---

### Task 6: Restyle the Shortcut Key-Cap Display and Recording State

**Files:**
- Modify: `src/styles.css` — add key-cap styles
- Modify: `src/main.ts:411-431` — update shortcut panel HTML

**Step 1: Add key-cap CSS**

Add to `src/styles.css`:

```css
/* Keyboard key-cap display */
.keycap-display {
  display: flex;
  align-items: center;
  gap: 0.375rem;
  flex-wrap: wrap;
  padding: 0.75rem 0;
}

.keycap {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 2rem;
  padding: 0.3125rem 0.625rem;
  background: linear-gradient(180deg, #f8f8fa, #e8e8ed);
  border: 1px solid #c8c8cc;
  border-bottom-width: 2px;
  border-radius: var(--radius-sm);
  font-family: "SF Mono", Menlo, Monaco, monospace;
  font-size: 0.8125rem;
  font-weight: 500;
  color: var(--text-primary);
  box-shadow: 0 1px 0 rgba(0, 0, 0, 0.08);
}

.keycap-separator {
  color: var(--text-tertiary);
  font-size: 0.75rem;
}

.keycap-display.recording {
  border: 2px solid var(--error);
  border-radius: var(--radius-md);
  padding: 0.625rem 0.75rem;
  background: rgba(255, 59, 48, 0.04);
  animation: recording-pulse 1.5s ease-in-out infinite;
}

@keyframes recording-pulse {
  0%, 100% { border-color: var(--error); }
  50% { border-color: rgba(255, 59, 48, 0.3); }
}

.recording-indicator {
  display: inline-flex;
  align-items: center;
  gap: 0.375rem;
  font-size: 0.8125rem;
  color: var(--error);
  font-weight: 500;
}

.recording-dot {
  width: 8px;
  height: 8px;
  background: var(--error);
  border-radius: 50%;
  animation: dot-pulse 1s ease-in-out infinite;
}

@keyframes dot-pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.3; }
}
```

**Step 2: Update shortcut panel HTML in main.ts**

Replace the shortcut panel section (lines 411-431) in `initSettingsView()` with:

```html
<section id="panel-shortcuts" class="panel">
  <header class="panel-header compact">
    <div>
      <h2>Shortcuts</h2>
      <p>Global shortcut for opening the Spotlight launcher.</p>
    </div>
  </header>
  <div class="stack-card">
    <label>
      <span>Global Shortcut</span>
      <div id="keycap-container" class="keycap-display"></div>
      <input id="global-shortcut" type="hidden" />
      <small class="hint">Use Record, then press your preferred key combination.</small>
    </label>
    <div class="actions">
      <button id="shortcut-record" type="button" class="secondary">Record Shortcut</button>
      <button id="shortcut-reset" type="button" class="ghost">Reset Default</button>
      <button id="shortcut-save" type="button">Save Shortcut</button>
    </div>
    <p id="shortcut-status" class="status"></p>
  </div>
</section>
```

**Step 3: Add renderKeycap helper and update shortcut logic in main.ts**

After the `setShortcutRecording` function, add:

```typescript
const renderKeycaps = (shortcut: string) => {
  const container = document.querySelector<HTMLElement>("#keycap-container");
  if (!container) return;
  const parts = shortcut.split("+");
  container.innerHTML = parts
    .map((part, i) => {
      const label = part
        .replace("CmdOrCtrl", "\u2318")
        .replace("Ctrl", "\u2303")
        .replace("Alt", "\u2325")
        .replace("Shift", "\u21E7")
        .replace(/^Key/, "")
        .replace(/^Digit/, "");
      return `<span class="keycap">${escapeHtml(label)}</span>${i < parts.length - 1 ? '<span class="keycap-separator">+</span>' : ""}`;
    })
    .join("");
};
```

Update `setShortcutRecording` to toggle the recording class:

```typescript
const setShortcutRecording = (recording: boolean) => {
  isRecordingShortcut = recording;
  shortcutRecordButton.textContent = recording ? "Stop" : "Record Shortcut";
  shortcutRecordButton.setAttribute("aria-pressed", recording ? "true" : "false");
  const container = document.querySelector<HTMLElement>("#keycap-container");
  if (container) {
    container.classList.toggle("recording", recording);
    if (recording) {
      container.innerHTML = '<span class="recording-indicator"><span class="recording-dot"></span>Listening...</span>';
    } else {
      renderKeycaps(shortcutInput.value);
    }
  }
};
```

Update all places that set `shortcutInput.value` to also call `renderKeycaps()`:
- In `loadAll()` after `shortcutInput.value = settings.globalShortcut;` add `renderKeycaps(settings.globalShortcut);`
- In `shortcutResetButton` click handler after setting `shortcutInput.value` add `renderKeycaps(DEFAULT_SETTINGS.globalShortcut);`
- In the keydown handler after `shortcutInput.value = captured;` the `setShortcutRecording(false)` call will trigger renderKeycaps.

**Step 4: Change shortcut form to non-form (since we removed submit button)**

Replace the `shortcutForm.addEventListener("submit", ...)` with a click handler on `#shortcut-save`:

```typescript
const shortcutSaveButton = document.querySelector<HTMLButtonElement>("#shortcut-save");
// ... in the null check add shortcutSaveButton

shortcutSaveButton.addEventListener("click", async () => {
  const next: AppSettings = {
    ...settings,
    globalShortcut: shortcutInput.value.trim() || DEFAULT_SETTINGS.globalShortcut,
  };
  try {
    await saveSettings(next);
    settings = next;
    setShortcutStatus("Shortcut saved.");
  } catch (error) {
    setShortcutStatus(String(error), true);
  }
});
```

---

### Task 7: Update Sidebar HTML with Icons

**Files:**
- Modify: `src/main.ts:322-328` — sidebar nav buttons

**Step 1: Replace sidebar button markup**

Replace the 4 sidebar buttons with:

```html
<button type="button" data-panel="agents" class="sidebar-item active">
  <span class="sidebar-icon">&#9783;</span>Agents
</button>
<button type="button" data-panel="settings" class="sidebar-item">
  <span class="sidebar-icon">&#9881;</span>Settings
</button>
<button type="button" data-panel="shortcuts" class="sidebar-item">
  <span class="sidebar-icon">&#9000;</span>Shortcuts
</button>
<button type="button" data-panel="about" class="sidebar-item">
  <span class="sidebar-icon">&#9432;</span>About
</button>
```

---

### Task 8: Replace Checkboxes with Toggle Switches in Settings Panel

**Files:**
- Modify: `src/main.ts:389-402` — settings form checkboxes

**Step 1: Replace checkbox HTML**

Replace the three `label class="checkbox-row"` blocks with:

```html
<div class="toggle-row">
  <span>Restrict URLs to the configured instance host</span>
  <label class="toggle-switch">
    <input id="restrict-host" type="checkbox" />
    <span class="toggle-slider"></span>
  </label>
</div>

<div class="toggle-row">
  <span>Open presets in a new window</span>
  <label class="toggle-switch">
    <input id="open-in-new-window" type="checkbox" />
    <span class="toggle-slider"></span>
  </label>
</div>

<div class="toggle-row">
  <span>Debug In-Webview (open main webview inspector)</span>
  <label class="toggle-switch">
    <input id="debug-in-webview" type="checkbox" />
    <span class="toggle-slider"></span>
  </label>
</div>
```

---

### Task 9: Restyle the First-Run / Onboarding Card

**Files:**
- Modify: `src/styles.css:385-408` — first-run styles
- Modify: `src/main.ts:1133-1178` — first-run and default view HTML

**Step 1: Replace first-run CSS**

Replace `.first-run-page` through `.first-run-card p` with:

```css
.first-run-page {
  min-height: 100vh;
  display: grid;
  place-items: center;
  padding: 1rem;
  background: var(--bg-page);
}

.first-run-card {
  width: min(400px, 92vw);
  border: none;
  border-radius: var(--radius-xl);
  padding: 3rem;
  background: var(--bg-card);
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.08);
  text-align: center;
}

.first-run-logo {
  font-size: 1.75rem;
  font-weight: 600;
  letter-spacing: -0.03em;
  margin-bottom: 0.5rem;
  color: var(--text-primary);
}

.first-run-card p {
  margin: 0 0 2rem;
  color: var(--text-secondary);
  font-size: 0.9375rem;
  line-height: 1.5;
}

.first-run-card button {
  width: 100%;
  padding: 0.75rem 1.5rem;
  border-radius: var(--radius-lg);
  font-size: 0.9375rem;
  font-weight: 500;
  height: 44px;
}
```

**Step 2: Update first-run HTML in main.ts**

Replace `initFirstRunView()` body HTML with:

```html
<div class="first-run-page">
  <div class="first-run-card">
    <div class="first-run-logo">Toro Libre</div>
    <p>Set up your instance to get started.</p>
    <div class="actions" style="justify-content: center">
      <button id="first-run-open-settings" type="button">Open Settings</button>
    </div>
  </div>
</div>
```

**Step 3: Update default view HTML similarly**

Replace `initDefaultView()` body HTML with:

```html
<div class="first-run-page">
  <div class="first-run-card">
    <div class="first-run-logo">Toro Libre</div>
    <p>Use Settings to configure your instance and agents.</p>
    <div class="actions" style="justify-content: center">
      <button id="open-settings" type="button">Open Settings</button>
    </div>
  </div>
</div>
```

---

### Task 10: Add Ghost Button Style and Update Responsive Breakpoints

**Files:**
- Modify: `src/styles.css` — add ghost button, update media queries

**Step 1: Add ghost button style**

```css
button.ghost {
  background: transparent;
  color: var(--text-secondary);
  border: none;
  padding: 0.5rem 0.75rem;
}

button.ghost:hover {
  color: var(--text-primary);
  background: rgba(0, 0, 0, 0.04);
}
```

**Step 2: Update responsive breakpoints**

Replace the media queries at the end of the file with:

```css
@media (max-width: 980px) {
  .manager-shell {
    grid-template-columns: 1fr;
    height: auto;
    min-height: 100vh;
  }

  .manager-sidebar {
    border-right: 0;
    border-bottom: 1px solid var(--border);
    backdrop-filter: none;
    -webkit-backdrop-filter: none;
  }

  .sidebar-nav {
    display: flex;
    gap: 0.25rem;
    flex-wrap: wrap;
  }

  .manager-main {
    max-width: none;
  }
}

@media (max-width: 740px) {
  .agent-card {
    grid-template-columns: 1fr;
    align-items: flex-start;
  }

  .agent-actions {
    opacity: 1;
  }

  .editor-grid {
    grid-template-columns: 1fr;
  }

  .manager-main {
    padding: 1.25rem;
  }
}
```

---

### Task 11: Update Panel Header for Agents to Use New Layout

**Files:**
- Modify: `src/main.ts:333-339` — agents panel header

**Step 1: Update agents panel header**

Replace the header with:

```html
<header class="panel-header">
  <div class="panel-header-row">
    <div>
      <h2>Agents</h2>
      <p>Manage and configure your Toro Libre agents. Star sets default.</p>
    </div>
    <button id="agent-new" type="button" class="secondary">+ Add Agent</button>
  </div>
</header>
```

---

### Task 12: Final Integration Test and Polish

**Files:**
- Verify: `src/styles.css`, `src/main.ts`

**Step 1: Build the project**

Run: `npm run build`
Expected: Build succeeds with no errors

**Step 2: Type check**

Run: `npx tsc --noEmit`
Expected: No type errors

**Step 3: Commit**

```bash
git add src/styles.css src/main.ts
git commit -m "feat: redesign settings, onboarding, and shortcuts with macOS-native styling

- Replace raw checkboxes with CSS toggle switches
- Add sidebar icons and pill-style active state
- Implement keyboard key-cap visualization for shortcuts
- Add recording state animation for shortcut capture
- Polish first-run/onboarding card with centered layout
- Use CSS custom properties for consistent theming
- Add agent card hover effects and rounded avatars
- Style buttons with primary/secondary/ghost/danger variants
- Update responsive breakpoints"
```
