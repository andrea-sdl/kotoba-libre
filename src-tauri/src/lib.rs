use std::collections::HashSet;
use std::fs;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[cfg(target_os = "macos")]
use objc2::{AllocAnyThread, MainThreadMarker};
#[cfg(target_os = "macos")]
use objc2_app_kit::{NSApplication, NSImage};
#[cfg(target_os = "macos")]
use objc2_foundation::{NSData, NSString};
use serde::{Deserialize, Serialize};
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::{image::Image, AppHandle, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};
use tauri_plugin_store::StoreExt;
use url::{form_urlencoded, Url};
use uuid::Uuid;

const MAIN_WINDOW_LABEL: &str = "main";
const SETTINGS_WINDOW_LABEL: &str = "settings";
const LAUNCHER_WINDOW_LABEL: &str = "launcher";
const SETTINGS_STORE_PATH: &str = "settings.json";
const PRESETS_STORE_PATH: &str = "presets.json";
#[cfg(target_os = "macos")]
const DEFAULT_SHORTCUT: &str = "Alt+Space";
#[cfg(not(target_os = "macos"))]
const DEFAULT_SHORTCUT: &str = "CommandOrControl+Space";
const MENU_OPEN_SETTINGS_ID: &str = "open_settings";
const APP_ICON_BYTES: &[u8] = include_bytes!("../icons/app/icon-creative.png");

type CmdResult<T> = Result<T, String>;

#[derive(Debug)]
struct RuntimeFlags {
    registered_shortcut: Mutex<String>,
    restrict_host_to_chat: AtomicBool,
    instance_host: Mutex<Option<String>>,
}

impl RuntimeFlags {
    fn new(shortcut: String, restrict_host_to_chat: bool, instance_host: Option<String>) -> Self {
        Self {
            registered_shortcut: Mutex::new(shortcut),
            restrict_host_to_chat: AtomicBool::new(restrict_host_to_chat),
            instance_host: Mutex::new(instance_host),
        }
    }

    fn read_instance_host(&self) -> Option<String> {
        self.instance_host
            .lock()
            .ok()
            .and_then(|value| value.clone())
    }

    fn write_instance_host(&self, value: Option<String>) -> CmdResult<()> {
        let mut guard = self
            .instance_host
            .lock()
            .map_err(|_| "Instance host state lock poisoned".to_string())?;
        *guard = value;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
enum PresetKind {
    Agent,
    Link,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Preset {
    id: String,
    name: String,
    url_template: String,
    kind: PresetKind,
    tags: Vec<String>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
#[serde(default)]
struct AppSettings {
    instance_base_url: Option<String>,
    global_shortcut: String,
    open_in_new_window: bool,
    restrict_host_to_instance_host: bool,
    default_preset_id: Option<String>,
    debug_in_webview: bool,
    use_route_reload_for_launcher_chats: bool,
    accent_color: String,
    launcher_opacity: f64,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            instance_base_url: None,
            global_shortcut: DEFAULT_SHORTCUT.to_string(),
            open_in_new_window: false,
            restrict_host_to_instance_host: true,
            default_preset_id: None,
            debug_in_webview: false,
            use_route_reload_for_launcher_chats: false,
            accent_color: "blue".to_string(),
            launcher_opacity: 0.95,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ValidationResult {
    valid: bool,
    reason: Option<String>,
}

enum DeepLinkAction {
    OpenUrl(String),
    OpenPreset {
        preset_id: String,
        query: Option<String>,
    },
    OpenSettings,
}

fn normalize_settings(mut settings: AppSettings) -> AppSettings {
    settings.instance_base_url = settings.instance_base_url.and_then(|value| {
        let trimmed = value.trim().to_string();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    });

    let normalized_shortcut = normalize_shortcut_value(&settings.global_shortcut);
    if normalized_shortcut.is_empty() {
        settings.global_shortcut = DEFAULT_SHORTCUT.to_string();
    } else {
        settings.global_shortcut = normalized_shortcut;
    }
    if let Some(default_preset_id) = settings.default_preset_id.as_ref() {
        if default_preset_id.trim().is_empty() {
            settings.default_preset_id = None;
        } else {
            settings.default_preset_id = Some(default_preset_id.trim().to_string());
        }
    }

    settings
}

fn app_icon_bytes() -> &'static [u8] {
    APP_ICON_BYTES
}

fn app_icon_image() -> CmdResult<Image<'static>> {
    Image::from_bytes(app_icon_bytes()).map_err(|e| e.to_string())
}

#[cfg(target_os = "macos")]
fn apply_dock_icon(app: &tauri::AppHandle) -> CmdResult<()> {
    let bytes = app_icon_bytes().to_vec();
    let (tx, rx) = std::sync::mpsc::sync_channel(1);

    app.run_on_main_thread(move || {
        let data = NSData::with_bytes(&bytes);
        let icon_image = NSImage::initWithData(NSImage::alloc(), &data)
            .or_else(|| {
                let mut icon_path = std::env::temp_dir();
                let suffix = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|duration| duration.as_nanos())
                    .unwrap_or(0);
                icon_path.push(format!("torolibre-app-icon-{suffix}.png"));

                if fs::write(&icon_path, &bytes).is_err() {
                    return None;
                }

                let path = NSString::from_str(icon_path.to_string_lossy().as_ref());
                let image = NSImage::initWithContentsOfFile(NSImage::alloc(), &path);
                let _ = fs::remove_file(icon_path);
                image
            })
            .ok_or_else(|| "Failed to create macOS dock icon image".to_string())
            .map(|ns_image| {
                ns_image.setTemplate(false);
                let app =
                    NSApplication::sharedApplication(unsafe { MainThreadMarker::new_unchecked() });
                unsafe { app.setApplicationIconImage(Some(&ns_image)) };
            });
        let _ = tx.send(icon_image);
    })
    .map_err(|_| "Failed to schedule macOS icon update on main thread".to_string())?;

    rx.recv_timeout(Duration::from_secs(1))
        .map_err(|_| "Failed to apply macOS dock icon".to_string())?
}

#[cfg(target_os = "macos")]
fn apply_app_icon(app: &tauri::AppHandle) -> CmdResult<()> {
    apply_dock_icon(app)
}

#[cfg(not(target_os = "macos"))]
fn apply_app_icon(app: &tauri::AppHandle) -> CmdResult<()> {
    let image = app_icon_image()?;
    for label in [
        MAIN_WINDOW_LABEL,
        SETTINGS_WINDOW_LABEL,
        LAUNCHER_WINDOW_LABEL,
    ] {
        if let Some(window) = app.get_webview_window(label) {
            window.set_icon(image.clone()).map_err(|e| e.to_string())?;
        }
    }

    Ok(())
}

fn normalize_shortcut_token(token: &str) -> String {
    let trimmed = token.trim();
    let lower = trimmed.to_ascii_lowercase();

    match lower.as_str() {
        "⌘" | "command" | "cmd" | "commandorcontrol" | "commandorctrl" | "cmdorctrl"
        | "cmdorcontrol" => "CmdOrCtrl".to_string(),
        "⌃" | "^" | "control" | "ctrl" => "Ctrl".to_string(),
        "⌥" | "option" | "alt" => "Alt".to_string(),
        "⇧" | "shift" => "Shift".to_string(),
        "spacebar" => "Space".to_string(),
        _ => {
            if lower == "space" {
                return "Space".to_string();
            }

            if trimmed.len() == 1 {
                if let Some(c) = trimmed.chars().next() {
                    if c.is_ascii_alphabetic() {
                        return format!("Key{}", c.to_ascii_uppercase());
                    }
                    if c.is_ascii_digit() {
                        return format!("Digit{c}");
                    }
                }
            }

            trimmed.to_string()
        }
    }
}

fn normalize_shortcut_value(shortcut: &str) -> String {
    let mut seen = HashSet::new();
    let mut tokens = Vec::new();

    for token in shortcut.split('+') {
        let token = normalize_shortcut_token(token);
        if token.is_empty() {
            continue;
        }

        let dedupe_key = token.to_ascii_lowercase();
        if seen.insert(dedupe_key) {
            tokens.push(token);
        }
    }

    tokens.join("+")
}

fn now_marker() -> String {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|v| v.as_millis())
        .unwrap_or(0);
    format!("unix-ms-{millis}")
}

fn normalize_tags(tags: Vec<String>) -> Vec<String> {
    let mut out = tags
        .into_iter()
        .map(|t| t.trim().to_string())
        .filter(|t| !t.is_empty())
        .collect::<Vec<_>>();
    out.sort();
    out.dedup();
    out
}

fn normalize_preset(input: Preset, existing: Option<&Preset>) -> Preset {
    let now = now_marker();
    let id = if input.id.trim().is_empty() {
        Uuid::new_v4().to_string()
    } else {
        input.id.trim().to_string()
    };

    let created_at = if let Some(current) = existing {
        current.created_at.clone()
    } else if input.created_at.trim().is_empty() {
        now.clone()
    } else {
        input.created_at
    };

    let updated_at = if input.updated_at.trim().is_empty() {
        now
    } else {
        input.updated_at
    };

    Preset {
        id,
        name: input.name.trim().to_string(),
        url_template: input.url_template.trim().to_string(),
        kind: input.kind,
        tags: normalize_tags(input.tags),
        created_at,
        updated_at,
    }
}

fn normalize_loaded_presets(input: Vec<Preset>) -> Vec<Preset> {
    let mut seen_ids = HashSet::new();

    input
        .into_iter()
        .map(|mut preset| {
            let id = preset.id.trim().to_string();
            if id.is_empty() || seen_ids.contains(&id) {
                preset.id = Uuid::new_v4().to_string();
            } else {
                preset.id = id;
            }
            seen_ids.insert(preset.id.clone());

            preset.name = preset.name.trim().to_string();
            preset.url_template = preset.url_template.trim().to_string();
            preset.tags = normalize_tags(preset.tags);

            let created_at = preset.created_at.trim().to_string();
            let updated_at = preset.updated_at.trim().to_string();
            if created_at.is_empty() {
                let now = now_marker();
                preset.created_at = now.clone();
                preset.updated_at = if updated_at.is_empty() { now } else { updated_at };
            } else {
                preset.created_at = created_at.clone();
                preset.updated_at = if updated_at.is_empty() {
                    created_at
                } else {
                    updated_at
                };
            }

            preset
        })
        .collect()
}

fn load_settings(app: &AppHandle) -> CmdResult<AppSettings> {
    let store = app.store(SETTINGS_STORE_PATH).map_err(|e| e.to_string())?;
    let settings = match store.get("settings") {
        Some(value) => serde_json::from_value(value).unwrap_or_default(),
        None => AppSettings::default(),
    };
    Ok(normalize_settings(settings))
}

fn save_settings_internal(app: &AppHandle, settings: &AppSettings) -> CmdResult<()> {
    let store = app.store(SETTINGS_STORE_PATH).map_err(|e| e.to_string())?;
    store.set(
        "settings",
        serde_json::to_value(settings).map_err(|e| e.to_string())?,
    );
    store.save().map_err(|e| e.to_string())
}

fn load_presets(app: &AppHandle) -> CmdResult<Vec<Preset>> {
    let store = app.store(PRESETS_STORE_PATH).map_err(|e| e.to_string())?;
    let presets = match store.get("presets") {
        Some(value) => serde_json::from_value(value).unwrap_or_default(),
        None => Vec::new(),
    };
    let normalized = normalize_loaded_presets(presets.clone());
    if normalized != presets {
        save_presets(app, &normalized)?;
    }
    Ok(normalized)
}

fn save_presets(app: &AppHandle, presets: &[Preset]) -> CmdResult<()> {
    let store = app.store(PRESETS_STORE_PATH).map_err(|e| e.to_string())?;
    store.set(
        "presets",
        serde_json::to_value(presets).map_err(|e| e.to_string())?,
    );
    store.save().map_err(|e| e.to_string())
}

fn validate_url_template_internal(url_template: &str) -> ValidationResult {
    if url_template.trim().is_empty() {
        return ValidationResult {
            valid: false,
            reason: Some("URL template cannot be empty".to_string()),
        };
    }

    let candidate = url_template.replace("{query}", "example");
    let parsed = match Url::parse(&candidate) {
        Ok(url) => url,
        Err(error) => {
            return ValidationResult {
                valid: false,
                reason: Some(format!("Invalid URL template: {error}")),
            }
        }
    };

    if parsed.scheme() != "https" {
        return ValidationResult {
            valid: false,
            reason: Some("Only https URLs are supported".to_string()),
        };
    }

    if parsed.host_str().is_none() {
        return ValidationResult {
            valid: false,
            reason: Some("URL must contain a host".to_string()),
        };
    }

    ValidationResult {
        valid: true,
        reason: None,
    }
}

fn parse_instance_base_url(settings: &AppSettings) -> CmdResult<Option<Url>> {
    let raw = match settings.instance_base_url.as_ref() {
        Some(value) => value.trim(),
        None => return Ok(None),
    };

    if raw.is_empty() {
        return Ok(None);
    }

    let mut parsed = Url::parse(raw).map_err(|e| format!("Invalid instance URL: {e}"))?;
    if parsed.scheme() != "https" {
        return Err("Toro Libre instance URL must start with https://".to_string());
    }
    if parsed.host_str().is_none() {
        return Err("Toro Libre instance URL must include a host".to_string());
    }

    parsed.set_query(None);
    parsed.set_fragment(None);
    Ok(Some(parsed))
}

fn normalize_instance_base_url(settings: &mut AppSettings) -> CmdResult<()> {
    if let Some(parsed) = parse_instance_base_url(settings)? {
        settings.instance_base_url = Some(parsed.to_string());
    } else {
        settings.instance_base_url = None;
    }
    Ok(())
}

fn settings_instance_host(settings: &AppSettings) -> CmdResult<Option<String>> {
    Ok(parse_instance_base_url(settings)?
        .and_then(|url| url.host_str().map(|host| host.to_ascii_lowercase())))
}

fn enforce_destination(url: &str, settings: &AppSettings) -> CmdResult<Url> {
    let parsed = Url::parse(url).map_err(|e| format!("Invalid destination URL: {e}"))?;

    if parsed.scheme() != "https" {
        return Err("Only https URLs are supported".to_string());
    }

    if settings.restrict_host_to_instance_host {
        let host = parsed.host_str().unwrap_or_default().to_ascii_lowercase();
        let allowed_host = settings_instance_host(settings)?.ok_or_else(|| {
            "Set your Toro Libre instance URL in Settings before opening destinations".to_string()
        })?;
        if host != allowed_host {
            return Err(format!(
                "Destination host '{host}' is blocked by current policy"
            ));
        }
    }

    Ok(parsed)
}

fn allow_navigation(url: &Url, runtime_flags: &RuntimeFlags) -> bool {
    if url.scheme() != "https" {
        return true;
    }

    if !runtime_flags.restrict_host_to_chat.load(Ordering::Relaxed) {
        return true;
    }

    let allowed_host = match runtime_flags.read_instance_host() {
        Some(host) => host,
        None => return false,
    };

    matches!(url.host_str(), Some(host) if host.eq_ignore_ascii_case(&allowed_host))
}

fn main_webview_url(settings: &AppSettings) -> CmdResult<WebviewUrl> {
    if let Some(url) = parse_instance_base_url(settings)? {
        return Ok(WebviewUrl::External(url));
    }

    Ok(WebviewUrl::App("index.html?view=first-run".into()))
}

fn ensure_main_window(
    app: &AppHandle,
    runtime_flags: Arc<RuntimeFlags>,
    settings: &AppSettings,
) -> CmdResult<()> {
    if app.get_webview_window(MAIN_WINDOW_LABEL).is_some() {
        return Ok(());
    }

    let url = main_webview_url(settings)?;
    let icon = app_icon_image()?;
    WebviewWindowBuilder::new(app, MAIN_WINDOW_LABEL, url)
        .title("Toro Libre")
        .icon(icon)
        .map_err(|e| e.to_string())?
        .inner_size(1280.0, 860.0)
        .on_navigation(move |next_url| allow_navigation(next_url, runtime_flags.as_ref()))
        .build()
        .map_err(|e| e.to_string())?;

    Ok(())
}

fn apply_main_webview_debug_flag(app: &AppHandle, enabled: bool) {
    if let Some(main) = app.get_webview_window(MAIN_WINDOW_LABEL) {
        if enabled {
            main.open_devtools();
        } else {
            main.close_devtools();
        }
    }
}

fn show_settings_window(app: &AppHandle) -> CmdResult<()> {
    let icon = app_icon_image()?;
    if let Some(window) = app.get_webview_window(SETTINGS_WINDOW_LABEL) {
        window.set_icon(icon).map_err(|e| e.to_string())?;
        window.show().map_err(|e| e.to_string())?;
        window.set_focus().map_err(|e| e.to_string())?;
        return Ok(());
    }

    WebviewWindowBuilder::new(
        app,
        SETTINGS_WINDOW_LABEL,
        WebviewUrl::App("index.html?view=settings".into()),
    )
    .title("Toro Libre Wrapper - Agent Manager")
    .icon(icon)
    .map_err(|e| e.to_string())?
    .inner_size(1220.0, 860.0)
    .center()
    .resizable(true)
    .build()
    .map_err(|e| e.to_string())?;

    Ok(())
}

fn ensure_launcher_window(app: &AppHandle) -> CmdResult<()> {
    if app.get_webview_window(LAUNCHER_WINDOW_LABEL).is_some() {
        return Ok(());
    }

    let icon = app_icon_image()?;
    WebviewWindowBuilder::new(
        app,
        LAUNCHER_WINDOW_LABEL,
        WebviewUrl::App("index.html?view=launcher".into()),
    )

    .title("Librechat Spotlight")
    .icon(icon)
    .map_err(|e| e.to_string())?
    .inner_size(860.0, 115.0)
    .auto_resize()
    .decorations(false)
    .skip_taskbar(true)
    .resizable(false)
    .always_on_top(true)
    .visible(false)
    .center()
    .shadow(false)
    .transparent(true)
    .build()
    .map_err(|e| e.to_string())?;

    #[cfg(target_os = "macos")]
    {
        if let Some(win) = app.get_webview_window(LAUNCHER_WINDOW_LABEL) {
            let ns_win = win.ns_window().map_err(|e| e.to_string())?;
            unsafe {
                use objc2_app_kit::NSColor;
                let ns_window: &objc2_app_kit::NSWindow =
                    &*(ns_win as *const objc2_app_kit::NSWindow);
                ns_window.setBackgroundColor(Some(&NSColor::clearColor()));
                ns_window.setOpaque(false);
            }
        }
    }

    Ok(())
}

fn toggle_launcher_window(app: &AppHandle) -> CmdResult<()> {
    ensure_launcher_window(app)?;
    let launcher = app
        .get_webview_window(LAUNCHER_WINDOW_LABEL)
        .ok_or_else(|| "Launcher window not available".to_string())?;

    let visible = launcher.is_visible().map_err(|e| e.to_string())?;
    if visible {
        launcher.hide().map_err(|e| e.to_string())?;
        return Ok(());
    }

    launcher.show().map_err(|e| e.to_string())?;
    launcher.set_focus().map_err(|e| e.to_string())?;
    Ok(())
}

fn hide_launcher_window(app: &AppHandle) -> CmdResult<()> {
    if let Some(launcher) = app.get_webview_window(LAUNCHER_WINDOW_LABEL) {
        launcher.hide().map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn register_global_shortcut(
    app: &AppHandle,
    runtime_flags: Arc<RuntimeFlags>,
    shortcut: &str,
) -> CmdResult<()> {
    let normalized = shortcut.trim();
    if normalized.is_empty() {
        return Err("Global shortcut cannot be empty".to_string());
    }

    let previous = {
        runtime_flags
            .registered_shortcut
            .lock()
            .map_err(|_| "Shortcut state lock poisoned".to_string())?
            .clone()
    };

    if !previous.is_empty() && app.global_shortcut().is_registered(previous.as_str()) {
        let _ = app.global_shortcut().unregister(previous.as_str());
    }

    let handler = move |app: &AppHandle,
                        _shortcut: &tauri_plugin_global_shortcut::Shortcut,
                        event: tauri_plugin_global_shortcut::ShortcutEvent| {
        if event.state() == ShortcutState::Pressed {
            let _ = toggle_launcher_window(app);
        }
    };

    app.global_shortcut()
        .on_shortcut(normalized, handler)
        .map_err(|e| e.to_string())?;

    *runtime_flags
        .registered_shortcut
        .lock()
        .map_err(|_| "Shortcut state lock poisoned".to_string())? = normalized.to_string();

    Ok(())
}

fn can_use_spa_navigation(instance_host: Option<&str>, url: &Url) -> bool {
    match (instance_host, url.host_str()) {
        (Some(instance_host), Some(url_host)) => url_host.eq_ignore_ascii_case(instance_host),
        _ => false,
    }
}

fn open_url_in_window(
    app: &AppHandle,
    url: Url,
    open_in_new_window: bool,
    debug_in_webview: bool,
    use_route_reload_for_launcher_chats: bool,
    instance_host: Option<&str>,
) -> CmdResult<()> {
    if open_in_new_window {
        let label = format!("chat-{}", Uuid::new_v4());
        WebviewWindowBuilder::new(app, label, WebviewUrl::External(url))
            .title("Toro Libre")
            .inner_size(1280.0, 860.0)
            .build()
            .map_err(|e| e.to_string())?;
        return Ok(());
    }

    let main = app
        .get_webview_window(MAIN_WINDOW_LABEL)
        .ok_or_else(|| "Main window not available".to_string())?;
    if can_use_spa_navigation(instance_host, &url) {
        let payload = serde_json::to_string(url.as_str()).map_err(|e| e.to_string())?;
        let debug_flag = if debug_in_webview { "true" } else { "false" };
        let route_reload_flag = if use_route_reload_for_launcher_chats {
            "true"
        } else {
            "false"
        };
        let script = format!(
            r#"(async function() {{
  try {{
    const next = new URL({payload});
    const target = `${{next.pathname}}${{next.search}}${{next.hash}}`;
    const debug = {debug_flag};
    const useRouteReloadForLauncherChats = {route_reload_flag};
    const debugLog = (...args) => {{
      if (!debug) {{
        return;
      }}
      try {{
        const normalized = args.map((arg) => {{
          if (typeof arg === "string") {{
            return arg;
          }}
          try {{
            return JSON.stringify(arg);
          }} catch (_) {{
            return String(arg);
          }}
        }});
        console.log("[Toro Libre Debug]", ...args);
        const key = "__torolibreDebugEvents";
        const line = `${{new Date().toISOString()}} ${{normalized.join(" ")}}`;
        if (!Array.isArray(window[key])) {{
          window[key] = [];
        }}
        window[key].push(line);
      }} catch (_) {{}}
    }};
    debugLog("navigation start", {{
      destination: next.href,
      target,
      current: `${{window.location.pathname}}${{window.location.search}}${{window.location.hash}}`,
    }});
    const shouldAutoSubmitFromQuery =
      (next.searchParams.get("submit") ?? "").toLowerCase() === "true" &&
      (next.searchParams.has("prompt") || next.searchParams.has("q"));
    if (useRouteReloadForLauncherChats && shouldAutoSubmitFromQuery) {{
      debugLog("forced route reload for launcher chats", {{ to: next.href }});
      window.location.assign(next.href);
      return;
    }}

    const locationValue = () =>
      `${{window.location.pathname}}${{window.location.search}}${{window.location.hash}}`;
    const isAtTargetLocation = () => locationValue() === target;
    const delay = (ms) => new Promise((resolve) => window.setTimeout(resolve, ms));
    const waitForTargetLocation = async (timeoutMs) => {{
      const started = Date.now();
      while (Date.now() - started < timeoutMs) {{
        if (isAtTargetLocation()) {{
          return true;
        }}
        await delay(60);
      }}
      return isAtTargetLocation();
    }};

    const pushWithHistory = (value) => {{
      if (!(window.history && typeof window.history.pushState === "function")) {{
        debugLog("pushWithHistory unavailable");
        return false;
      }}

      const current = `${{window.location.pathname}}${{window.location.search}}${{window.location.hash}}`;
      if (current !== value) {{
        window.history.pushState({{}}, "", value);
        debugLog("pushState", {{ from: current, to: value }});
      }} else {{
        debugLog("pushState skipped (already on target)");
      }}

      window.dispatchEvent(new PopStateEvent("popstate", {{ state: window.history.state }}));
      document.dispatchEvent(new PopStateEvent("popstate", {{ state: window.history.state }}));
      window.dispatchEvent(new Event("pushstate"));
      debugLog("history events dispatched");
      return true;
    }};

    const navigateWithHistoryAndWait = async (value, timeoutMs = 1200) => {{
      if (!pushWithHistory(value)) {{
        return false;
      }}
      await waitForRouteToApply();
      return await waitForTargetLocation(timeoutMs);
    }};

    const clickFirstMatching = (selectors) => {{
      for (const selector of selectors) {{
        const element = document.querySelector(selector);
        if (element instanceof HTMLElement) {{
          element.click();
          return true;
        }}
      }}
      return false;
    }};

    const navigateViaLibreChatUi = async () => {{
      if (!shouldAutoSubmitFromQuery) {{
        return false;
      }}
      if (!(next.pathname === "/c/new" || next.pathname.startsWith("/c/new/"))) {{
        return false;
      }}

      // Keep query params in current location so LibreChat's New Chat flow
      // carries them into /c/new and lets useQueryParams process them natively.
      try {{
        const current = new URL(window.location.href);
        current.search = next.search;
        window.history.replaceState(window.history.state, "", `${{current.pathname}}${{current.search}}${{current.hash}}`);
        window.dispatchEvent(new PopStateEvent("popstate", {{ state: window.history.state }}));
      }} catch (error) {{
        debugLog("navigateViaLibreChatUi replaceState failed", {{ error: String(error) }});
      }}

      await delay(80);

      // Force a route remount first (search), then trigger New Chat button.
      clickFirstMatching([
        "a[href='/search']",
        "a[href$='/search']",
        "[data-testid='nav-search-button']",
      ]);

      await delay(120);

      const clickedNewChat = clickFirstMatching([
        "[data-testid='nav-new-chat-button']",
        "a[href='/c/new']",
        "a[href$='/c/new']",
      ]);
      if (!clickedNewChat) {{
        debugLog("navigateViaLibreChatUi missing new chat control");
        return false;
      }}

      const reached = await waitForTargetLocation(2000);
      debugLog("navigateViaLibreChatUi completed", {{ reached }});
      return reached;
    }};

    const performSubmitRouteRemount = async () => {{
      if (!shouldAutoSubmitFromQuery) {{
        return false;
      }}

      // LibreChat's query-processing hook is mount-oriented; remount chat route
      // without full reload by briefly switching routes.
      const remountPath = `/search?tl_remount=${{Date.now()}}`;
      if (window.location.pathname !== "/search") {{
        pushWithHistory(remountPath);
        await waitForRouteToApply();
      }}

      const reached = await navigateWithHistoryAndWait(target, 1600);
      debugLog("submit remount route completed", {{ reached }});
      return reached;
    }};

    const waitForRouteToApply = async () => {{
      await new Promise((resolve) => window.setTimeout(resolve, 0));
      await new Promise((resolve) => window.setTimeout(resolve, 80));
    }};

    const routeWithRouter = async (value) => {{
      const nextPush =
        globalThis.next?.router?.push ??
        globalThis.__next_router__?.push ??
        globalThis.__NEXT_ROUTER__?.push;
      if (typeof nextPush === "function") {{
        const result = nextPush(value);
        if (result && typeof result.then === "function") {{
          await result;
        }}
        await waitForRouteToApply();
        const reached = await waitForTargetLocation(1200);
        debugLog("routeWithRouter used next push", {{ reached }});
        return reached;
      }}

      const genericNavigate =
        globalThis.__next_router__?.navigate ??
        globalThis.__NEXT_ROUTER__?.navigate ??
        globalThis.__remixRouter?.navigate;
      if (typeof genericNavigate === "function") {{
        const result = genericNavigate(value);
        if (result && typeof result.then === "function") {{
          await result;
        }}
        await waitForRouteToApply();
        const reached = await waitForTargetLocation(1200);
        debugLog("routeWithRouter used generic navigate", {{ reached }});
        return reached;
      }}
      debugLog("routeWithRouter unavailable");
      return false;
    }};

    if (await routeWithRouter(target)) {{
      debugLog("navigation completed with router first", {{ shouldAutoSubmitFromQuery }});
      return;
    }}

    if (await navigateViaLibreChatUi()) {{
      debugLog("navigation completed with LibreChat UI strategy");
      return;
    }}

    if (await performSubmitRouteRemount()) {{
      debugLog("navigation completed with submit remount strategy");
      return;
    }}

    if (pushWithHistory(target)) {{
      const reached = await waitForTargetLocation(600);
      debugLog("navigation completed with history fallback", {{ reached, shouldAutoSubmitFromQuery }});
      if (reached) {{
        return;
      }}
    }}
    debugLog("navigation path not handled");
    if (shouldAutoSubmitFromQuery) {{
      debugLog("skip hard fallback for submit query to avoid full reload");
      return;
    }}
    debugLog("immediate hard navigate fallback", {{ to: next.href }});
    window.location.assign(next.href);
    return;
  }} catch (error) {{
    try {{
      console.log("[Toro Libre Debug] navigation exception", error);
    }} catch (_) {{}}
  }}
  return;
}})();"#
        );

        if main.eval(&script).is_err() {
            main.navigate(url).map_err(|e| e.to_string())?;
        }
    } else {
        main.navigate(url).map_err(|e| e.to_string())?;
    }

    main.show().map_err(|e| e.to_string())?;
    main.set_focus().map_err(|e| e.to_string())?;
    Ok(())
}

fn expand_template(url_template: &str, query: Option<&str>) -> String {
    let has_query_template = url_template.contains("{query}");
    let templated = if has_query_template {
        let encoded = query
            .map(|value| form_urlencoded::byte_serialize(value.as_bytes()).collect::<String>())
            .unwrap_or_default();
        url_template.replace("{query}", &encoded)
    } else {
        url_template.to_string()
    };

    if has_query_template {
        return templated;
    }

    let query = match query {
        Some(query) if !query.is_empty() => query,
        _ => return templated,
    };

    match Url::parse(&templated) {
        Ok(mut parsed) => {
            let retained = parsed
                .query_pairs()
                .filter(|(key, _)| key != "prompt" && key != "q" && key != "submit")
                .map(|(key, value)| (key.into_owned(), value.into_owned()))
                .collect::<Vec<_>>();
            parsed.set_query(None);
            {
                let mut pairs = parsed.query_pairs_mut();
                for (key, value) in retained {
                    pairs.append_pair(&key, &value);
                }
                pairs.append_pair("prompt", query);
                pairs.append_pair("submit", "true");
            }
            parsed.to_string()
        }
        Err(_) => templated,
    }
}

fn open_url_internal(app: &AppHandle, destination: &str) -> CmdResult<()> {
    let settings = load_settings(app)?;
    let target = enforce_destination(destination, &settings)?;
    let instance_host = settings_instance_host(&settings)?;
    open_url_in_window(
        app,
        target,
        settings.open_in_new_window,
        settings.debug_in_webview,
        settings.use_route_reload_for_launcher_chats,
        instance_host.as_deref(),
    )
}

fn open_preset_internal(app: &AppHandle, preset_id: &str, query: Option<&str>) -> CmdResult<()> {
    let presets = load_presets(app)?;
    let preset = presets
        .iter()
        .find(|item| item.id == preset_id)
        .ok_or_else(|| format!("Preset '{preset_id}' not found"))?;

    let destination = expand_template(&preset.url_template, query);
    open_url_internal(app, &destination)
}

fn navigate_main_to_instance_home(app: &AppHandle, settings: &AppSettings) -> CmdResult<()> {
    let Some(target) = parse_instance_base_url(settings)? else {
        return Ok(());
    };

    if app.get_webview_window(MAIN_WINDOW_LABEL).is_none() {
        return Ok(());
    }

    let instance_host = settings_instance_host(settings)?;
    open_url_in_window(
        app,
        target,
        false,
        settings.debug_in_webview,
        settings.use_route_reload_for_launcher_chats,
        instance_host.as_deref(),
    )
}

fn query_value(url: &Url, key: &str) -> Option<String> {
    url.query_pairs()
        .find_map(|(k, v)| if k == key { Some(v.into_owned()) } else { None })
}

fn parse_deep_link(raw: &str) -> CmdResult<DeepLinkAction> {
    let parsed = Url::parse(raw).map_err(|e| format!("Invalid deep link URL: {e}"))?;

    if parsed.scheme() == "torolibre" {
        return parse_custom_scheme(&parsed);
    }

    if parsed.scheme() == "https" {
        return parse_web_link(&parsed);
    }

    Err("Unsupported deep link scheme".to_string())
}

fn parse_custom_scheme(url: &Url) -> CmdResult<DeepLinkAction> {
    match url.host_str() {
        Some("open") => {
            let destination =
                query_value(url, "url").ok_or_else(|| "Missing ?url= parameter".to_string())?;
            Ok(DeepLinkAction::OpenUrl(destination))
        }
        Some("preset") => {
            let preset_id = url
                .path_segments()
                .and_then(|mut s| s.next())
                .filter(|segment| !segment.is_empty())
                .ok_or_else(|| "Missing preset id in deep link".to_string())?
                .to_string();
            let query = query_value(url, "query");
            Ok(DeepLinkAction::OpenPreset { preset_id, query })
        }
        Some("settings") => Ok(DeepLinkAction::OpenSettings),
        Some(other) => Err(format!("Unsupported deep link host: {other}")),
        None => Err("Invalid deep link host".to_string()),
    }
}

fn parse_web_link(url: &Url) -> CmdResult<DeepLinkAction> {
    if url.path() == "/app/open" {
        let destination =
            query_value(url, "url").ok_or_else(|| "Missing ?url= parameter".to_string())?;
        return Ok(DeepLinkAction::OpenUrl(destination));
    }

    if url.path() == "/app/settings" {
        return Ok(DeepLinkAction::OpenSettings);
    }

    if let Some(preset_id) = url.path().strip_prefix("/app/preset/") {
        if preset_id.is_empty() {
            return Err("Missing preset id in deep link".to_string());
        }

        return Ok(DeepLinkAction::OpenPreset {
            preset_id: preset_id.to_string(),
            query: query_value(url, "query"),
        });
    }

    Err("Unsupported web deep-link path".to_string())
}

fn handle_deep_link_string(app: &AppHandle, raw_url: &str) -> CmdResult<()> {
    match parse_deep_link(raw_url)? {
        DeepLinkAction::OpenUrl(destination) => open_url_internal(app, &destination),
        DeepLinkAction::OpenPreset { preset_id, query } => {
            open_preset_internal(app, &preset_id, query.as_deref())
        }
        DeepLinkAction::OpenSettings => show_settings_window(app),
    }
}

fn set_application_menu(app: &AppHandle) -> CmdResult<()> {
    let settings_item = MenuItem::with_id(
        app,
        MENU_OPEN_SETTINGS_ID,
        "Settings...",
        true,
        Some("CmdOrCtrl+,"),
    )
    .map_err(|e| e.to_string())?;

    let app_separator = PredefinedMenuItem::separator(app).map_err(|e| e.to_string())?;
    let quit_item = PredefinedMenuItem::quit(app, None).map_err(|e| e.to_string())?;
    let undo_item = PredefinedMenuItem::undo(app, None).map_err(|e| e.to_string())?;
    let redo_item = PredefinedMenuItem::redo(app, None).map_err(|e| e.to_string())?;
    let edit_separator = PredefinedMenuItem::separator(app).map_err(|e| e.to_string())?;
    let cut_item = PredefinedMenuItem::cut(app, None).map_err(|e| e.to_string())?;
    let copy_item = PredefinedMenuItem::copy(app, None).map_err(|e| e.to_string())?;
    let paste_item = PredefinedMenuItem::paste(app, None).map_err(|e| e.to_string())?;
    let select_all_item = PredefinedMenuItem::select_all(app, None).map_err(|e| e.to_string())?;

    let app_submenu = Submenu::with_items(
        app,
        "Toro Libre",
        true,
        &[&settings_item, &app_separator, &quit_item],
    )
    .map_err(|e| e.to_string())?;
    let edit_submenu = Submenu::with_items(
        app,
        "Edit",
        true,
        &[
            &undo_item,
            &redo_item,
            &edit_separator,
            &cut_item,
            &copy_item,
            &paste_item,
            &select_all_item,
        ],
    )
    .map_err(|e| e.to_string())?;
    let menu = Menu::with_items(app, &[&app_submenu, &edit_submenu]).map_err(|e| e.to_string())?;

    app.set_menu(menu).map_err(|e| e.to_string())?;
    app.on_menu_event(|app_handle, event| {
        if event.id() == MENU_OPEN_SETTINGS_ID {
            let _ = show_settings_window(app_handle);
        }
    });

    Ok(())
}

fn wire_deep_links(app: &AppHandle) {
    if let Ok(Some(urls)) = app.deep_link().get_current() {
        for url in urls {
            let _ = handle_deep_link_string(app, url.as_ref());
        }
    }

    let app_handle = app.clone();
    app.deep_link().on_open_url(move |event| {
        for url in event.urls() {
            let _ = handle_deep_link_string(&app_handle, url.as_ref());
        }
    });
}

#[tauri::command]
fn get_settings(app: AppHandle) -> CmdResult<AppSettings> {
    load_settings(&app)
}

#[tauri::command]
fn save_settings(
    app: AppHandle,
    settings: AppSettings,
    runtime_flags: State<'_, Arc<RuntimeFlags>>,
) -> CmdResult<()> {
    let previous = load_settings(&app).unwrap_or_default();
    let mut normalized = normalize_settings(settings);
    normalize_instance_base_url(&mut normalized)?;
    save_settings_internal(&app, &normalized)?;

    runtime_flags
        .restrict_host_to_chat
        .store(normalized.restrict_host_to_instance_host, Ordering::Relaxed);
    runtime_flags.write_instance_host(settings_instance_host(&normalized)?)?;

    register_global_shortcut(
        &app,
        runtime_flags.inner().clone(),
        &normalized.global_shortcut,
    )?;

    apply_main_webview_debug_flag(&app, normalized.debug_in_webview);

    if previous.instance_base_url != normalized.instance_base_url {
        if let Some(main) = app.get_webview_window(MAIN_WINDOW_LABEL) {
            let _ = main.close();
        }
        ensure_main_window(&app, runtime_flags.inner().clone(), &normalized)?;
        let _ = navigate_main_to_instance_home(&app, &normalized);
    }
    apply_app_icon(&app)?;

    Ok(())
}

#[tauri::command]
fn list_presets(app: AppHandle) -> CmdResult<Vec<Preset>> {
    let mut presets = load_presets(&app)?;
    presets.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    Ok(presets)
}

#[tauri::command]
fn upsert_preset(app: AppHandle, preset: Preset) -> CmdResult<Preset> {
    let mut presets = load_presets(&app)?;
    let existing_index = presets.iter().position(|item| item.id == preset.id);
    let normalized = normalize_preset(
        preset,
        existing_index
            .and_then(|index| presets.get(index))
            .map(|preset| preset as &Preset),
    );

    if normalized.name.is_empty() {
        return Err("Preset name cannot be empty".to_string());
    }

    let validation = validate_url_template_internal(&normalized.url_template);
    if !validation.valid {
        return Err(validation
            .reason
            .unwrap_or_else(|| "Invalid URL template".to_string()));
    }

    if let Some(index) = existing_index {
        presets[index] = normalized.clone();
    } else {
        presets.push(normalized.clone());
    }

    save_presets(&app, &presets)?;
    Ok(normalized)
}

#[tauri::command]
fn delete_preset(app: AppHandle, id: String) -> CmdResult<()> {
    let mut presets = load_presets(&app)?;
    let original_len = presets.len();
    presets.retain(|item| item.id != id);

    if presets.len() == original_len {
        return Err("Preset not found".to_string());
    }

    save_presets(&app, &presets)
}

#[tauri::command]
fn open_preset(app: AppHandle, id: String, query: Option<String>) -> CmdResult<()> {
    open_preset_internal(&app, &id, query.as_deref())
}

#[tauri::command]
fn open_url(app: AppHandle, url: String) -> CmdResult<()> {
    open_url_internal(&app, &url)
}

#[tauri::command]
fn validate_url_template(url_template: String) -> ValidationResult {
    validate_url_template_internal(&url_template)
}

#[tauri::command]
fn show_settings(app: AppHandle) -> CmdResult<()> {
    show_settings_window(&app)
}

#[tauri::command]
fn hide_launcher(app: AppHandle) -> CmdResult<()> {
    hide_launcher_window(&app)
}

#[tauri::command]
fn get_window_label(window: tauri::WebviewWindow) -> String {
    window.label().to_string()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_single_instance::init(
            |app: &AppHandle, args, _cwd| {
                let mut handled = false;
                for arg in args {
                    if handle_deep_link_string(app, &arg).is_ok() {
                        handled = true;
                    }
                }

                if !handled {
                    if let Some(main) = app.get_webview_window(MAIN_WINDOW_LABEL) {
                        let _ = main.show();
                        let _ = main.set_focus();
                    }
                }
            },
        ))
        .setup(|app| {
            let mut settings = load_settings(app.handle())?;
            if normalize_instance_base_url(&mut settings).is_err() {
                settings.instance_base_url = None;
            } else {
                let _ = save_settings_internal(app.handle(), &settings);
            }
            let instance_host = settings_instance_host(&settings)?;
            let runtime_flags = Arc::new(RuntimeFlags::new(
                settings.global_shortcut.clone(),
                settings.restrict_host_to_instance_host,
                instance_host,
            ));
            app.manage(runtime_flags.clone());

            set_application_menu(app.handle())?;
            ensure_main_window(app.handle(), runtime_flags.clone(), &settings)?;
            apply_main_webview_debug_flag(app.handle(), settings.debug_in_webview);
            ensure_launcher_window(app.handle())?;
            apply_app_icon(app.handle())?;
            register_global_shortcut(app.handle(), runtime_flags, &settings.global_shortcut)?;
            wire_deep_links(app.handle());

            if settings.instance_base_url.is_none() {
                let _ = show_settings_window(app.handle());
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            save_settings,
            list_presets,
            upsert_preset,
            delete_preset,
            open_preset,
            open_url,
            validate_url_template,
            show_settings,
            hide_launcher,
            get_window_label
        ])
        .on_window_event(|window, event| {
            if window.label() == LAUNCHER_WINDOW_LABEL {
                if let tauri::WindowEvent::Focused(false) = event {
                    let _ = window.hide();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings_restricting_host() -> AppSettings {
        AppSettings {
            instance_base_url: Some("https://chat.example.com".to_string()),
            global_shortcut: DEFAULT_SHORTCUT.to_string(),
            open_in_new_window: false,
            restrict_host_to_instance_host: true,
            default_preset_id: Some("preset-1".to_string()),
            debug_in_webview: false,
            use_route_reload_for_launcher_chats: false,
            accent_color: "blue".to_string(),
            launcher_opacity: 0.95,
        }
    }

    #[test]
    fn shortcut_symbols_are_normalized() {
        assert_eq!(
            normalize_shortcut_value("⌘ + ⇧ + space"),
            "CmdOrCtrl+Shift+Space"
        );
        assert_eq!(normalize_shortcut_value("ctrl + k"), "Ctrl+KeyK");
    }

    #[test]
    fn settings_normalize_shortcut_aliases() {
        let normalized = normalize_settings(AppSettings {
            global_shortcut: "commandorcontrol + option + v".to_string(),
            ..settings_restricting_host()
        });

        assert_eq!(normalized.global_shortcut, "CmdOrCtrl+Alt+KeyV");
    }

    #[test]
    fn deep_link_open_url_is_parsed() {
        let parsed = parse_deep_link("torolibre://open?url=https%3A%2F%2Fchat.example.com%2Fc%2F123")
            .expect("deep link should parse");

        match parsed {
            DeepLinkAction::OpenUrl(url) => assert_eq!(url, "https://chat.example.com/c/123"),
            _ => panic!("expected open url action"),
        }
    }

    #[test]
    fn deep_link_preset_is_parsed() {
        let parsed = parse_deep_link("torolibre://preset/preset-1?query=hello%20world")
            .expect("deep link should parse");

        match parsed {
            DeepLinkAction::OpenPreset { preset_id, query } => {
                assert_eq!(preset_id, "preset-1");
                assert_eq!(query.as_deref(), Some("hello world"));
            }
            _ => panic!("expected preset action"),
        }
    }

    #[test]
    fn deep_link_invalid_fails() {
        assert!(parse_deep_link("torolibre://open").is_err());
        assert!(parse_deep_link("ftp://example.com/app/open?url=https://chat.example.com").is_err());
    }

    #[test]
    fn host_restriction_blocks_non_chat_host() {
        let settings = settings_restricting_host();
        assert!(enforce_destination("https://chat.example.com/c/new", &settings).is_ok());
        assert!(enforce_destination("https://example.com", &settings).is_err());
    }

    #[test]
    fn host_restriction_can_be_disabled() {
        let settings = AppSettings {
            restrict_host_to_instance_host: false,
            ..settings_restricting_host()
        };
        assert!(enforce_destination("https://example.com", &settings).is_ok());
    }

    #[test]
    fn host_restriction_requires_instance_when_enabled() {
        let settings = AppSettings {
            instance_base_url: None,
            ..settings_restricting_host()
        };
        assert!(enforce_destination("https://chat.example.com/c/new", &settings).is_err());
    }

    #[test]
    fn template_query_placeholder_is_encoded() {
        let result = expand_template("https://chat.example.com/search?q={query}", Some("hello world"));
        assert_eq!(result, "https://chat.example.com/search?q=hello+world");
    }

    #[test]
    fn template_query_is_appended_as_prompt_with_submit_when_missing_placeholder() {
        let result = expand_template(
            "https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs",
            Some("hello world"),
        );
        assert_eq!(
            result,
            "https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs&prompt=hello+world&submit=true"
        );
    }

    #[test]
    fn loaded_presets_are_normalized_with_unique_non_empty_ids() {
        let input = vec![
            Preset {
                id: "".to_string(),
                name: "  Agent One  ".to_string(),
                url_template: " https://chat.example.com/c/new?agent_id=1 ".to_string(),
                kind: PresetKind::Agent,
                tags: vec![" support ".to_string(), "support".to_string()],
                created_at: "".to_string(),
                updated_at: "".to_string(),
            },
            Preset {
                id: "dup".to_string(),
                name: "Agent Two".to_string(),
                url_template: "https://chat.example.com/c/new?agent_id=2".to_string(),
                kind: PresetKind::Agent,
                tags: vec![],
                created_at: "unix-ms-1".to_string(),
                updated_at: "".to_string(),
            },
            Preset {
                id: "dup".to_string(),
                name: "Agent Three".to_string(),
                url_template: "https://chat.example.com/c/new?agent_id=3".to_string(),
                kind: PresetKind::Agent,
                tags: vec![],
                created_at: "unix-ms-2".to_string(),
                updated_at: "unix-ms-3".to_string(),
            },
        ];

        let normalized = normalize_loaded_presets(input);
        assert_eq!(normalized.len(), 3);
        assert!(!normalized[0].id.is_empty());
        assert_eq!(normalized[1].id, "dup");
        assert_ne!(normalized[2].id, "dup");
        assert_ne!(normalized[2].id, normalized[0].id);
        assert_eq!(normalized[0].name, "Agent One");
        assert_eq!(
            normalized[0].url_template,
            "https://chat.example.com/c/new?agent_id=1"
        );
        assert_eq!(normalized[0].tags, vec!["support".to_string()]);
        assert!(!normalized[0].created_at.is_empty());
        assert!(!normalized[0].updated_at.is_empty());
        assert_eq!(normalized[1].updated_at, "unix-ms-1");
    }

    #[test]
    fn spa_navigation_allowed_for_launcher_submit_url_on_instance_host() {
        let url = Url::parse(
            "https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs&prompt=hello&submit=true",
        )
        .expect("url parses");
        assert!(can_use_spa_navigation(Some("chat.example.com"), &url));
    }

    #[test]
    fn spa_navigation_blocked_for_non_instance_host() {
        let url = Url::parse("https://example.com/c/new?prompt=hello&submit=true")
            .expect("url parses");
        assert!(!can_use_spa_navigation(Some("chat.example.com"), &url));
    }

    #[test]
    fn settings_roundtrip() {
        let settings = AppSettings::default();
        let serialized = serde_json::to_string(&settings).expect("serialize settings");
        let decoded: AppSettings = serde_json::from_str(&serialized).expect("deserialize settings");
        assert_eq!(settings, decoded);
    }

    #[test]
    fn preset_roundtrip() {
        let preset = Preset {
            id: "id-1".to_string(),
            name: "Support Agent".to_string(),
            url_template: "https://chat.example.com/c/new?agent=support".to_string(),
            kind: PresetKind::Agent,
            tags: vec!["support".to_string(), "internal".to_string()],
            created_at: "unix-ms-1".to_string(),
            updated_at: "unix-ms-2".to_string(),
        };

        let serialized = serde_json::to_string(&preset).expect("serialize preset");
        let decoded: Preset = serde_json::from_str(&serialized).expect("deserialize preset");
        assert_eq!(preset, decoded);
    }
}
