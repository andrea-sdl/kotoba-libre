import {
  deletePreset,
  getSettings,
  getWindowLabel,
  hideLauncher,
  listPresets,
  openPreset,
  openUrl,
  saveSettings,
  showSettings,
  upsertPreset,
  validateUrlTemplate,
} from "./api";
import type { AppSettings, Preset, PresetKind } from "./types";
import appIcon from "./assets/icons/creative.svg";

const DEFAULT_SETTINGS: AppSettings = {
  instanceBaseUrl: null,
  globalShortcut: navigator.platform.toLowerCase().includes("mac")
    ? "Alt+Space"
    : "CommandOrControl+Space",
  openInNewWindow: false,
  restrictHostToInstanceHost: true,
  defaultPresetId: null,
  debugInWebview: false,
  accentColor: "blue",
  launcherOpacity: 0.95,
};

const ACCENT_PRESETS: Record<
  string,
  { accent: string; hover: string; active: string; rgb: string }
> = {
  blue: {
    accent: "#007aff",
    hover: "#0063d1",
    active: "#004ea3",
    rgb: "0, 122, 255",
  },
  purple: {
    accent: "#af52de",
    hover: "#9536cc",
    active: "#7b20b8",
    rgb: "175, 82, 222",
  },
  pink: {
    accent: "#ff2d55",
    hover: "#e0264a",
    active: "#c41f3f",
    rgb: "255, 45, 85",
  },
  red: {
    accent: "#ff3b30",
    hover: "#e0342a",
    active: "#c42d24",
    rgb: "255, 59, 48",
  },
  orange: {
    accent: "#ff9500",
    hover: "#e08400",
    active: "#c47400",
    rgb: "255, 149, 0",
  },
  green: {
    accent: "#34c759",
    hover: "#2aad4a",
    active: "#20933b",
    rgb: "52, 199, 89",
  },
  teal: {
    accent: "#5ac8fa",
    hover: "#4ab4e0",
    active: "#3a9fc6",
    rgb: "90, 200, 250",
  },
  graphite: {
    accent: "#8e8e93",
    hover: "#7a7a7f",
    active: "#66666b",
    rgb: "142, 142, 147",
  },
};

function applyAccentColor(colorName: string): void {
  const preset = ACCENT_PRESETS[colorName] ?? ACCENT_PRESETS.blue;
  const root = document.documentElement;
  root.style.setProperty("--accent", preset.accent);
  root.style.setProperty("--accent-hover", preset.hover);
  root.style.setProperty("--accent-active", preset.active);
  root.style.setProperty("--accent-rgb", preset.rgb);
}

const PANEL_IDS = ["agents", "settings", "shortcuts", "about"] as const;
type PanelId = (typeof PANEL_IDS)[number];

function appIconMarkup(): string {
  return `<img src="${escapeHtml(appIcon)}" alt="App icon" class="app-icon-img" />`;
}

function rootElement(): HTMLElement {
  const root = document.querySelector<HTMLElement>("#app");
  if (!root) {
    throw new Error("Missing #app root element");
  }
  return root;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function nowMarker(): string {
  return `unix-ms-${Date.now()}`;
}

function parseTags(raw: string): string[] {
  return raw
    .split(",")
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0);
}

function formatTags(tags: string[]): string {
  return tags.join(", ");
}

function debounce<T extends (...args: never[]) => void>(
  fn: T,
  waitMs: number,
): (...args: Parameters<T>) => void {
  let timer: number | undefined;
  return (...args: Parameters<T>) => {
    window.clearTimeout(timer);
    timer = window.setTimeout(() => {
      fn(...args);
    }, waitMs);
  };
}


const SUPPORTED_SHORTCUT_CODES = new Set<string>([
  "Space",
  "Enter",
  "Tab",
  "Escape",
  "Backspace",
  "Delete",
  "Insert",
  "Home",
  "End",
  "PageUp",
  "PageDown",
  "ArrowUp",
  "ArrowDown",
  "ArrowLeft",
  "ArrowRight",
  "Minus",
  "Equal",
  "BracketLeft",
  "BracketRight",
  "Backslash",
  "Semicolon",
  "Quote",
  "Comma",
  "Period",
  "Slash",
  "Backquote",
  "Numpad0",
  "Numpad1",
  "Numpad2",
  "Numpad3",
  "Numpad4",
  "Numpad5",
  "Numpad6",
  "Numpad7",
  "Numpad8",
  "Numpad9",
  "NumpadAdd",
  "NumpadSubtract",
  "NumpadMultiply",
  "NumpadDivide",
  "NumpadDecimal",
  "NumpadEnter",
  "NumpadEqual",
]);

function shortcutKeyFromCode(code: string): string | null {
  if (
    /^Key[A-Z]$/.test(code) ||
    /^Digit[0-9]$/.test(code) ||
    /^F(?:[1-9]|1[0-9]|2[0-4])$/.test(code)
  ) {
    return code;
  }

  if (SUPPORTED_SHORTCUT_CODES.has(code)) {
    return code;
  }

  return null;
}

function shortcutFromKeyEvent(event: KeyboardEvent): string | null {
  const hasModifier =
    event.metaKey || event.ctrlKey || event.altKey || event.shiftKey;
  if (!hasModifier) {
    return null;
  }

  if (["Meta", "Control", "Alt", "Shift"].includes(event.key)) {
    return null;
  }

  const key = shortcutKeyFromCode(event.code);
  if (!key) {
    return null;
  }

  const parts: string[] = [];
  if (event.metaKey) {
    parts.push("CmdOrCtrl");
  }
  if (event.ctrlKey && !event.metaKey) {
    parts.push("Ctrl");
  }
  if (event.altKey) {
    parts.push("Alt");
  }
  if (event.shiftKey) {
    parts.push("Shift");
  }
  parts.push(key);

  return parts.join("+");
}

let pasteFallbackInstalled = false;

function installPasteFallback(): void {
  if (pasteFallbackInstalled) {
    return;
  }

  pasteFallbackInstalled = true;
  document.addEventListener(
    "keydown",
    async (event) => {
      const isPasteShortcut =
        (event.metaKey || event.ctrlKey) &&
        event.key.toLowerCase() === "v" &&
        !event.defaultPrevented;
      if (!isPasteShortcut) {
        return;
      }

      const target = event.target;
      if (
        !(target instanceof HTMLInputElement) &&
        !(target instanceof HTMLTextAreaElement)
      ) {
        return;
      }

      if (
        typeof target.selectionStart !== "number" ||
        typeof target.selectionEnd !== "number"
      ) {
        return;
      }

      try {
        const text = await navigator.clipboard.readText();
        event.preventDefault();
        const start = target.selectionStart;
        const end = target.selectionEnd;
        target.setRangeText(text, start, end, "end");
        target.dispatchEvent(new Event("input", { bubbles: true }));
      } catch {
        // Leave native behavior untouched if clipboard access is unavailable.
      }
    },
    true,
  );
}

function normalizeInstanceBaseUrl(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed) {
    return null;
  }

  try {
    const url = new URL(trimmed);
    if (url.protocol !== "https:") {
      return null;
    }
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

function suggestPresetTemplate(instanceBaseUrl: string | null): string {
  if (!instanceBaseUrl) {
    return "https://";
  }

  try {
    const base = new URL(
      instanceBaseUrl.endsWith("/") ? instanceBaseUrl : `${instanceBaseUrl}/`,
    );
    return new URL("c/new", base).toString();
  } catch {
    return instanceBaseUrl;
  }
}

function emptyPreset(
  settings: AppSettings,
  kind: PresetKind = "agent",
): Preset {
  const marker = nowMarker();
  return {
    id: "",
    name: "",
    urlTemplate: suggestPresetTemplate(settings.instanceBaseUrl),
    kind,
    tags: [],
    createdAt: marker,
    updatedAt: marker,
  };
}

const AVATAR_GRADIENTS: Array<[string, string]> = [
  ["#0a84ff", "#5e5ce6"],
  ["#5e5ce6", "#bf5af2"],
  ["#64d2ff", "#0a84ff"],
  ["#30d158", "#34c759"],
  ["#ff9f0a", "#ff6a00"],
  ["#ff375f", "#ff2d55"],
  ["#40c8e0", "#0fb9b1"],
  ["#7d7aff", "#5e5ce6"],
];

function hashString(value: string): number {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function presetAvatarLabel(preset: Preset): string {
  const words = preset.name
    .trim()
    .split(/[^A-Za-z0-9]+/)
    .filter((word) => word.length > 0);
  if (words.length === 0) {
    return preset.kind === "link" ? "LN" : "AG";
  }

  const first = words[0]?.[0] ?? "";
  const second =
    words.length > 1 ? (words[1]?.[0] ?? "") : (words[0]?.[1] ?? "");
  const combined = `${first}${second}`.toUpperCase().trim();
  return combined.length > 0 ? combined : preset.kind === "link" ? "LN" : "AG";
}

function presetAvatarStyle(preset: Preset): string {
  const hash = hashString(`${preset.id}:${preset.name}:${preset.kind}`);
  const gradient = AVATAR_GRADIENTS[hash % AVATAR_GRADIENTS.length];
  return `--avatar-start:${gradient[0]};--avatar-end:${gradient[1]};`;
}


async function initSettingsView(): Promise<void> {
  const root = rootElement();
  root.innerHTML = `
    <div class="manager-page">
      <div class="manager-shell">
        <aside class="manager-sidebar">
          <h1>Toro Libre Wrapper</h1>
          <nav class="sidebar-nav" id="sidebar-nav">
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
          </nav>
        </aside>

        <main class="manager-main">
          <section id="panel-agents" class="panel active">
            <header class="panel-header">
              <div class="panel-header-row">
                <div>
                  <h2>Agents</h2>
                  <p>Manage and configure your Toro Libre agents. Star sets default.</p>
                </div>
                <button id="agent-new" type="button" class="secondary">+ Add Agent</button>
              </div>
            </header>
            <div id="instance-warning" class="instance-warning hidden"></div>
            <div id="preset-list" class="agent-list"></div>
            <form id="preset-form" class="editor-card">
              <input id="preset-id" type="hidden" />
              <div class="editor-grid">
                <label>
                  <span>Name</span>
                  <input id="preset-name" type="text" placeholder="Coding Assistant" required />
                </label>
                <label>
                  <span>Kind</span>
                  <select id="preset-kind">
                    <option value="agent">Agent</option>
                    <option value="link">Link</option>
                  </select>
                </label>
                <label class="editor-wide">
                  <span>Configured URL</span>
                  <input id="preset-url" type="url" placeholder="https://your-librechat-instance/c/new?agent_id=..." required />
                  <small id="preset-url-hint" class="hint"></small>
                </label>
                <label class="editor-wide">
                  <span>Tags</span>
                  <input id="preset-tags" type="text" placeholder="coding, support" />
                </label>
              </div>
              <div class="editor-actions">
                <button type="submit">Save Agent</button>
                <button id="preset-open" type="button" class="secondary">Open URL</button>
                <button id="preset-clear" type="button" class="secondary">Clear</button>
              </div>
              <p id="preset-status" class="status"></p>
            </form>
          </section>

          <section id="panel-settings" class="panel">
            <header class="panel-header compact">
              <div>
                <h2>Instance Settings</h2>
                <p>Choose the Toro Libre instance this app should target.</p>
              </div>
            </header>
            <form id="settings-form" class="stack-card">
              <label>
                <span>Toro Libre Instance URL</span>
                <input id="instance-base-url" type="url" placeholder="https://chat.example.com" required />
                <small class="hint">Example: <code>https://chat.example.com</code></small>
              </label>

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

              <div class="setting-group">
                <label>
                  <span>Accent Color</span>
                  <div id="accent-color-picker" class="color-picker-row"></div>
                </label>
              </div>

              <div class="setting-group">
                <label>
                  <span class="range-label">Launcher Opacity <span id="opacity-value" class="range-value">95%</span></span>
                  <input id="launcher-opacity" type="range" min="50" max="100" step="5" />
                </label>
              </div>

              <div class="actions">
                <button type="submit">Save Settings</button>
              </div>
              <p id="settings-status" class="status"></p>
            </form>
          </section>

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
                <button id="shortcut-save" type="button" class="btn-primary">Save Shortcut</button>
              </div>
              <p id="shortcut-status" class="status"></p>
            </div>
          </section>

          <section id="panel-about" class="panel">
            <header class="panel-header compact">
              <div>
                <h2>About</h2>
                <p>Quick launcher wrapper for self-hosted Toro Libre instances.</p>
              </div>
            </header>
            <div class="stack-card">
              <p><strong>How it works</strong></p>
              <p>1. Configure your instance URL in Settings.</p>
              <p>2. Add one or more agents with URL templates.</p>
              <p>3. Use the global shortcut to ask directly from Spotlight-style launcher.</p>
              <div class="actions">
                <button id="open-main-settings" type="button" class="secondary">Open Settings Window</button>
              </div>
            </div>
          </section>
        </main>
      </div>
    </div>
  `;

  const sidebarNav = document.querySelector<HTMLElement>("#sidebar-nav");
  const settingsForm =
    document.querySelector<HTMLFormElement>("#settings-form");
  const shortcutSaveButton =
    document.querySelector<HTMLButtonElement>("#shortcut-save");

  const instanceBaseUrlInput =
    document.querySelector<HTMLInputElement>("#instance-base-url");
  const openInNewWindowInput = document.querySelector<HTMLInputElement>(
    "#open-in-new-window",
  );
  const restrictHostInput =
    document.querySelector<HTMLInputElement>("#restrict-host");
  const debugInWebviewInput =
    document.querySelector<HTMLInputElement>("#debug-in-webview");
  const shortcutInput =
    document.querySelector<HTMLInputElement>("#global-shortcut");
  const shortcutRecordButton =
    document.querySelector<HTMLButtonElement>("#shortcut-record");
  const shortcutResetButton =
    document.querySelector<HTMLButtonElement>("#shortcut-reset");

  const accentColorPicker = document.querySelector<HTMLElement>(
    "#accent-color-picker",
  );
  const launcherOpacityInput =
    document.querySelector<HTMLInputElement>("#launcher-opacity");
  const opacityValueLabel =
    document.querySelector<HTMLElement>("#opacity-value");

  const settingsStatus =
    document.querySelector<HTMLElement>("#settings-status");
  const shortcutStatus =
    document.querySelector<HTMLElement>("#shortcut-status");

  const presetForm = document.querySelector<HTMLFormElement>("#preset-form");
  const presetIdInput = document.querySelector<HTMLInputElement>("#preset-id");
  const presetNameInput =
    document.querySelector<HTMLInputElement>("#preset-name");
  const presetKindInput =
    document.querySelector<HTMLSelectElement>("#preset-kind");
  const presetUrlInput =
    document.querySelector<HTMLInputElement>("#preset-url");
  const presetTagsInput =
    document.querySelector<HTMLInputElement>("#preset-tags");
  const presetHint = document.querySelector<HTMLElement>("#preset-url-hint");
  const presetStatus = document.querySelector<HTMLElement>("#preset-status");
  const presetList = document.querySelector<HTMLElement>("#preset-list");
  const presetNewButton =
    document.querySelector<HTMLButtonElement>("#agent-new");
  const presetClearButton =
    document.querySelector<HTMLButtonElement>("#preset-clear");
  const presetOpenButton =
    document.querySelector<HTMLButtonElement>("#preset-open");
  const instanceWarning =
    document.querySelector<HTMLElement>("#instance-warning");
  const openMainSettingsButton = document.querySelector<HTMLButtonElement>(
    "#open-main-settings",
  );

  if (
    !sidebarNav ||
    !settingsForm ||
    !shortcutSaveButton ||
    !instanceBaseUrlInput ||
    !openInNewWindowInput ||
    !restrictHostInput ||
    !debugInWebviewInput ||
    !shortcutInput ||
    !shortcutRecordButton ||
    !shortcutResetButton ||
    !settingsStatus ||
    !shortcutStatus ||
    !presetForm ||
    !presetIdInput ||
    !presetNameInput ||
    !presetKindInput ||
    !presetUrlInput ||
    !presetTagsInput ||
    !presetHint ||
    !presetStatus ||
    !presetList ||
    !presetNewButton ||
    !presetClearButton ||
    !presetOpenButton ||
    !instanceWarning ||
    !openMainSettingsButton ||
    !accentColorPicker ||
    !launcherOpacityInput ||
    !opacityValueLabel
  ) {
    throw new Error("Settings UI failed to initialize");
  }

  let settings: AppSettings = DEFAULT_SETTINGS;
  let presets: Preset[] = [];
  let isRecordingShortcut = false;

  const setStatus = (el: HTMLElement, message: string, isError = false) => {
    el.textContent = message;
    el.classList.toggle("error", isError);
  };

  const setSettingsStatus = (message: string, isError = false) => {
    setStatus(settingsStatus, message, isError);
  };

  const setShortcutStatus = (message: string, isError = false) => {
    setStatus(shortcutStatus, message, isError);
  };

  const setPresetStatus = (message: string, isError = false) => {
    setStatus(presetStatus, message, isError);
  };

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

  const renderAccentPicker = (activeColor: string) => {
    accentColorPicker.innerHTML = Object.entries(ACCENT_PRESETS)
      .map(([name, preset]) => {
        const selected = name === activeColor ? " selected" : "";
        return `<button type="button" class="color-swatch${selected}" data-color="${escapeHtml(name)}" style="background:${preset.accent}" title="${escapeHtml(name)}"></button>`;
      })
      .join("");

    for (const swatch of accentColorPicker.querySelectorAll<HTMLButtonElement>(
      ".color-swatch",
    )) {
      swatch.addEventListener("click", async () => {
        const color = swatch.dataset.color;
        if (!color) return;
        applyAccentColor(color);
        settings = { ...settings, accentColor: color };
        try {
          await saveSettings(settings);
          renderAccentPicker(color);
          setSettingsStatus("Accent color saved.");
        } catch (error) {
          setSettingsStatus(String(error), true);
        }
      });
    }
  };

  launcherOpacityInput.addEventListener("input", () => {
    const val = parseInt(launcherOpacityInput.value, 10);
    opacityValueLabel.textContent = `${val}%`;
  });

  launcherOpacityInput.addEventListener("change", async () => {
    const val = parseInt(launcherOpacityInput.value, 10);
    settings = { ...settings, launcherOpacity: val / 100 };
    try {
      await saveSettings(settings);
      setSettingsStatus("Launcher opacity saved.");
    } catch (error) {
      setSettingsStatus(String(error), true);
    }
  });

  const setShortcutRecording = (recording: boolean) => {
    isRecordingShortcut = recording;
    shortcutRecordButton.textContent = recording ? "Stop" : "Record Shortcut";
    shortcutRecordButton.setAttribute(
      "aria-pressed",
      recording ? "true" : "false",
    );
    const container = document.querySelector<HTMLElement>("#keycap-container");
    if (container) {
      container.classList.toggle("recording", recording);
      if (recording) {
        container.innerHTML =
          '<span class="recording-indicator"><span class="recording-dot"></span>Listening...</span>';
      } else {
        renderKeycaps(shortcutInput.value);
      }
    }
  };

  const applyPanel = (panelId: PanelId) => {
    for (const panel of PANEL_IDS) {
      const panelEl = document.querySelector<HTMLElement>(`#panel-${panel}`);
      const buttonEl = sidebarNav.querySelector<HTMLButtonElement>(
        `[data-panel="${panel}"]`,
      );
      if (!panelEl || !buttonEl) {
        continue;
      }
      const active = panel === panelId;
      panelEl.classList.toggle("active", active);
      buttonEl.classList.toggle("active", active);
    }
  };

  const updateInstanceWarning = () => {
    if (!settings.instanceBaseUrl) {
      instanceWarning.classList.remove("hidden");
      instanceWarning.innerHTML =
        "<strong>First run:</strong> choose your Toro Libre instance in <em>Settings</em> before launching agents.";
    } else {
      instanceWarning.classList.add("hidden");
      instanceWarning.textContent = "";
    }
  };

  const updatePresetForm = (preset: Preset) => {
    presetIdInput.value = preset.id;
    presetNameInput.value = preset.name;
    presetKindInput.value = preset.kind;
    presetUrlInput.value = preset.urlTemplate;
    presetTagsInput.value = formatTags(preset.tags);
  };

  const currentPresetFromForm = (): Preset => {
    const existing = presets.find((item) => item.id === presetIdInput.value);
    const marker = nowMarker();

    return {
      id: presetIdInput.value,
      name: presetNameInput.value.trim(),
      urlTemplate: presetUrlInput.value.trim(),
      kind: presetKindInput.value as PresetKind,
      tags: parseTags(presetTagsInput.value),
      createdAt: existing?.createdAt ?? marker,
      updatedAt: marker,
    };
  };

  const renderPresetList = () => {
    if (presets.length === 0) {
      presetList.innerHTML =
        '<p class="empty">No agents yet. Use \"Add New Agent\".</p>';
      return;
    }

    const sorted = [...presets].sort((a, b) => a.name.localeCompare(b.name));
    presetList.innerHTML = sorted
      .map((preset) => {
        const isDefault = settings.defaultPresetId === preset.id;
        const defaultClass = isDefault ? " default" : "";
        return `
          <article class="agent-card${defaultClass}" data-id="${escapeHtml(preset.id)}">
            <div class="agent-icon" style="${escapeHtml(presetAvatarStyle(preset))}">${escapeHtml(presetAvatarLabel(preset))}</div>
            <div class="agent-meta">
              <div class="agent-title-row">
                <button type="button" class="star-toggle" data-action="toggle-default" data-id="${escapeHtml(preset.id)}" title="Set as default">${isDefault ? "&#9733;" : "&#9734;"}</button>
                <h3>${escapeHtml(preset.name)}</h3>
                ${isDefault ? '<span class="pill">DEFAULT</span>' : ""}
              </div>
              <p>Configured URL: <code>${escapeHtml(preset.urlTemplate)}</code></p>
              <small>${escapeHtml(preset.kind.toUpperCase())}${preset.tags.length ? ` - ${escapeHtml(preset.tags.join(", "))}` : ""}</small>
            </div>
            <div class="agent-actions">
              <button type="button" data-action="edit" data-id="${escapeHtml(preset.id)}" class="secondary">Edit</button>
              <button type="button" data-action="delete" data-id="${escapeHtml(preset.id)}" class="secondary danger">Delete</button>
            </div>
          </article>
        `;
      })
      .join("");

    for (const button of presetList.querySelectorAll<HTMLButtonElement>(
      "button[data-action]",
    )) {
      button.addEventListener("click", async () => {
        const id = button.dataset.id;
        const action = button.dataset.action;
        if (!id || !action) {
          return;
        }

        const preset = presets.find((item) => item.id === id);
        if (!preset) {
          return;
        }

        if (action === "toggle-default") {
          const nextSettings: AppSettings = {
            ...settings,
            defaultPresetId: settings.defaultPresetId === id ? null : id,
          };
          try {
            await saveSettings(nextSettings);
            settings = nextSettings;
            renderPresetList();
            setPresetStatus(
              settings.defaultPresetId === id
                ? `Default set to ${preset.name}.`
                : "Default cleared.",
            );
          } catch (error) {
            setPresetStatus(String(error), true);
          }
          return;
        }

        if (action === "edit") {
          updatePresetForm(preset);
          setPresetStatus(`Editing agent: ${preset.name}`);
          return;
        }

        if (action === "delete") {
          if (!window.confirm(`Delete agent \"${preset.name}\"?`)) {
            return;
          }

          try {
            await deletePreset(id);
            presets = presets.filter((item) => item.id !== id);
            if (settings.defaultPresetId === id) {
              const nextSettings: AppSettings = {
                ...settings,
                defaultPresetId: null,
              };
              await saveSettings(nextSettings);
              settings = nextSettings;
            }
            if (presetIdInput.value === id) {
              updatePresetForm(emptyPreset(settings));
            }
            setPresetStatus(`Deleted agent: ${preset.name}`);
            renderPresetList();
          } catch (error) {
            setPresetStatus(String(error), true);
          }
        }
      });
    }
  };

  const validatePresetUrl = debounce(async () => {
    if (!presetUrlInput.value.trim()) {
      presetHint.textContent = "";
      presetHint.classList.remove("error");
      return;
    }

    try {
      const validation = await validateUrlTemplate(presetUrlInput.value.trim());
      if (validation.valid) {
        presetHint.textContent = "Template looks valid.";
        presetHint.classList.remove("error");
      } else {
        presetHint.textContent = validation.reason ?? "Invalid URL template.";
        presetHint.classList.add("error");
      }
    } catch (error) {
      presetHint.textContent = String(error);
      presetHint.classList.add("error");
    }
  }, 250);

  const loadAll = async () => {
    try {
      settings = await getSettings();
      presets = await listPresets();

      if (
        settings.defaultPresetId &&
        !presets.some((preset) => preset.id === settings.defaultPresetId)
      ) {
        settings = { ...settings, defaultPresetId: null };
        await saveSettings(settings);
      }

      instanceBaseUrlInput.value = settings.instanceBaseUrl ?? "";
      openInNewWindowInput.checked = settings.openInNewWindow;
      restrictHostInput.checked = settings.restrictHostToInstanceHost;
      debugInWebviewInput.checked = settings.debugInWebview;
      shortcutInput.value = settings.globalShortcut;
      renderKeycaps(settings.globalShortcut);
      setShortcutRecording(false);

      applyAccentColor(settings.accentColor);
      renderAccentPicker(settings.accentColor);
      const opacityPercent = Math.round(
        (settings.launcherOpacity ?? 0.95) * 100,
      );
      launcherOpacityInput.value = String(opacityPercent);
      opacityValueLabel.textContent = `${opacityPercent}%`;

      updateInstanceWarning();
      updatePresetForm(emptyPreset(settings));
      renderPresetList();

      if (!settings.instanceBaseUrl) {
        applyPanel("settings");
        setSettingsStatus("First run: set your Toro Libre instance URL.");
      } else {
        setSettingsStatus("Loaded.");
      }
      setPresetStatus("");
      setShortcutStatus("");
    } catch (error) {
      const message = String(error);
      setSettingsStatus(message, true);
      setPresetStatus(message, true);
      setShortcutStatus(message, true);
    }
  };

  for (const button of sidebarNav.querySelectorAll<HTMLButtonElement>(
    "[data-panel]",
  )) {
    button.addEventListener("click", () => {
      const panel = button.dataset.panel;
      if (panel && PANEL_IDS.includes(panel as PanelId)) {
        applyPanel(panel as PanelId);
      }
    });
  }

  settingsForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    const normalizedInstanceUrl = normalizeInstanceBaseUrl(
      instanceBaseUrlInput.value,
    );
    if (!normalizedInstanceUrl) {
      setSettingsStatus("Instance URL must be a valid https:// URL.", true);
      return;
    }

    const next: AppSettings = {
      ...settings,
      instanceBaseUrl: normalizedInstanceUrl,
      openInNewWindow: openInNewWindowInput.checked,
      restrictHostToInstanceHost: restrictHostInput.checked,
      debugInWebview: debugInWebviewInput.checked,
    };

    try {
      await saveSettings(next);
      settings = next;
      instanceBaseUrlInput.value = normalizedInstanceUrl;
      updateInstanceWarning();
      if (!presetIdInput.value) {
        updatePresetForm(emptyPreset(settings));
      }
      setSettingsStatus("Settings saved.");
      setPresetStatus("");
    } catch (error) {
      setSettingsStatus(String(error), true);
    }
  });

  shortcutSaveButton.addEventListener("click", async () => {
    const next: AppSettings = {
      ...settings,
      globalShortcut:
        shortcutInput.value.trim() || DEFAULT_SETTINGS.globalShortcut,
    };

    try {
      await saveSettings(next);
      settings = next;
      setShortcutStatus("Shortcut saved.");
    } catch (error) {
      setShortcutStatus(String(error), true);
    }
  });

  shortcutRecordButton.addEventListener("click", () => {
    if (isRecordingShortcut) {
      setShortcutRecording(false);
      setShortcutStatus("Shortcut capture canceled.");
      return;
    }

    setShortcutRecording(true);
    setShortcutStatus("Press a key combination (Esc to cancel).");
  });

  shortcutResetButton.addEventListener("click", () => {
    shortcutInput.value = DEFAULT_SETTINGS.globalShortcut;
    renderKeycaps(DEFAULT_SETTINGS.globalShortcut);
    setShortcutRecording(false);
    setShortcutStatus(`Reset to default: ${DEFAULT_SETTINGS.globalShortcut}`);
  });

  presetForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    if (!settings.instanceBaseUrl) {
      applyPanel("settings");
      setPresetStatus("Set instance URL first.", true);
      return;
    }

    const draft = currentPresetFromForm();
    try {
      const saved = await upsertPreset(draft);
      const existingIndex = presets.findIndex((item) => item.id === saved.id);
      if (existingIndex >= 0) {
        presets[existingIndex] = saved;
      } else {
        presets.push(saved);
      }
      updatePresetForm(saved);
      renderPresetList();
      setPresetStatus(`Saved agent: ${saved.name}`);
    } catch (error) {
      setPresetStatus(String(error), true);
    }
  });

  presetNewButton.addEventListener("click", () => {
    updatePresetForm(emptyPreset(settings));
    setPresetStatus("Creating new agent.");
    applyPanel("agents");
  });

  presetClearButton.addEventListener("click", () => {
    updatePresetForm(emptyPreset(settings));
    setPresetStatus("Editor cleared.");
  });

  presetOpenButton.addEventListener("click", async () => {
    const draft = currentPresetFromForm();
    if (!draft.urlTemplate) {
      setPresetStatus("Set a URL first.", true);
      return;
    }

    try {
      await openUrl(draft.urlTemplate);
      setPresetStatus("Opened URL.");
    } catch (error) {
      setPresetStatus(String(error), true);
    }
  });

  presetUrlInput.addEventListener("input", () => {
    void validatePresetUrl();
  });

  window.addEventListener("keydown", (event) => {
    if (!isRecordingShortcut) {
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      setShortcutRecording(false);
      setShortcutStatus("Shortcut capture canceled.");
      return;
    }

    const captured = shortcutFromKeyEvent(event);
    if (!captured) {
      return;
    }

    event.preventDefault();
    shortcutInput.value = captured;
    setShortcutRecording(false);
    setShortcutStatus(`Shortcut captured: ${captured}`);
  });

  openMainSettingsButton.addEventListener("click", async () => {
    await showSettings();
  });

  await loadAll();
}

async function initLauncherView(): Promise<void> {
  document.documentElement.style.background = "transparent";
  document.body.style.background = "transparent";
  const root = rootElement();
  root.innerHTML = `
    <div class="spotlight-page">
      <div class="spotlight-shell">
        <div class="spotlight-input-wrap">
          <span class="spotlight-icon">⌕</span>
          <input id="spotlight-input" type="text" placeholder="Ask..." autofocus />
          <select id="spotlight-agent-select"></select>
        </div>
        <p id="launcher-status" class="status"></p>
      </div>
    </div>
  `;

  const input = document.querySelector<HTMLInputElement>("#spotlight-input");
  const agentSelect = document.querySelector<HTMLSelectElement>("#spotlight-agent-select");
  const status = document.querySelector<HTMLElement>("#launcher-status");

  if (!input || !agentSelect || !status) {
    throw new Error("Launcher UI failed to initialize");
  }

  let settings: AppSettings = DEFAULT_SETTINGS;
  let presets: Preset[] = [];
  let isLoadingPresets = false;

  const setStatus = (message: string, isError = false) => {
    status.textContent = message;
    status.classList.toggle("error", isError);
  };

  const sortedPresets = (): Preset[] => {
    return [...presets].sort((a, b) => {
      const defaultA = settings.defaultPresetId === a.id ? 1 : 0;
      const defaultB = settings.defaultPresetId === b.id ? 1 : 0;
      return defaultB - defaultA || a.name.localeCompare(b.name);
    });
  };

  const populateSelect = () => {
    const sorted = sortedPresets();
    agentSelect.innerHTML = sorted
      .map((preset) => {
        const isDefault = settings.defaultPresetId === preset.id;
        const label = isDefault ? `${preset.name} ★` : preset.name;
        return `<option value="${escapeHtml(preset.id)}">${escapeHtml(label)}</option>`;
      })
      .join("");

    if (sorted.length > 0) {
      agentSelect.value = sorted[0].id;
    }
  };

  const runPreset = async () => {
    const targetId = agentSelect.value;
    const target = presets.find((p) => p.id === targetId);

    if (!target) {
      setStatus("No agent selected.", true);
      return;
    }

    const query = input.value.trim() || undefined;

    try {
      await openPreset(target.id, query);
      await hideLauncher();
      setStatus(`Opened ${target.name}.`);
    } catch (error) {
      setStatus(String(error), true);
    }
  };

  const loadPresets = async () => {
    try {
      settings = await getSettings();
      presets = await listPresets();

      applyAccentColor(settings.accentColor);
      const shell = document.querySelector<HTMLElement>(".spotlight-shell");
      if (shell) {
        const opacity = settings.launcherOpacity ?? 0.95;
        shell.style.background = `rgba(255, 255, 255, ${opacity})`;
      }

      populateSelect();

      if (!settings.instanceBaseUrl) {
        setStatus("Configure instance URL first.", true);
        return;
      }

      if (presets.length === 0) {
        setStatus("No agents configured yet. Add one in Settings.", true);
        return;
      }

      setStatus("");
    } catch (error) {
      setStatus(String(error), true);
    }
  };

  const refreshPresets = async () => {
    if (isLoadingPresets) {
      return;
    }
    isLoadingPresets = true;
    try {
      await loadPresets();
    } finally {
      isLoadingPresets = false;
    }
  };

  input.addEventListener("keydown", async (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      await runPreset();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      await hideLauncher();
    }
  });

  const page = document.querySelector<HTMLElement>(".spotlight-page");
  if (page) {
    page.addEventListener("mousedown", async (event) => {
      if (event.target === page) {
        await hideLauncher();
      }
    });
  }

  window.addEventListener("focus", () => {
    void refreshPresets();
    input.focus();
    input.select();
  });

  await refreshPresets();
  input.focus();
  input.select();
}

function initFirstRunView(): void {
  const root = rootElement();
  root.innerHTML = `
    <div class="first-run-page">
      <div class="first-run-card">
        <div class="first-run-logo">${appIconMarkup()}<span>Toro Libre</span></div>
        <p>Set up your instance to get started.</p>
        <div class="actions" style="justify-content: center">
          <button id="first-run-open-settings" type="button" class="btn-primary">Open Settings</button>
        </div>
      </div>
    </div>
  `;

  const openSettingsButton = document.querySelector<HTMLButtonElement>(
    "#first-run-open-settings",
  );
  if (openSettingsButton) {
    openSettingsButton.addEventListener("click", async () => {
      await showSettings();
    });
  }
}

function initDefaultView(): void {
  const root = rootElement();
  root.innerHTML = `
    <div class="first-run-page">
      <div class="first-run-card">
        <div class="first-run-logo">${appIconMarkup()}<span>Toro Libre</span></div>
        <p>Use Settings to configure your instance and agents.</p>
        <div class="actions" style="justify-content: center">
          <button id="open-settings" type="button" class="btn-primary">Open Settings</button>
        </div>
      </div>
    </div>
  `;

  const openSettingsButton =
    document.querySelector<HTMLButtonElement>("#open-settings");
  if (openSettingsButton) {
    openSettingsButton.addEventListener("click", async () => {
      await showSettings();
    });
  }
}

async function bootstrap(): Promise<void> {
  installPasteFallback();

  const queryView = new URL(window.location.href).searchParams.get("view");
  let view = queryView;
  if (!view) {
    try {
      const label = await getWindowLabel();
      if (label === "settings" || label === "launcher") {
        view = label;
      } else if (label === "main") {
        view = "first-run";
      }
    } catch (error) {
      console.warn("Unable to resolve window label for bootstrap", error);
    }
  }

  if (view === "settings") {
    await initSettingsView();
    return;
  }

  if (view === "launcher") {
    await initLauncherView();
    return;
  }

  if (view === "first-run") {
    initFirstRunView();
    return;
  }

  initDefaultView();
}

void bootstrap();
