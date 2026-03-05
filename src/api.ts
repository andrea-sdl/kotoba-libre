import { invoke } from "@tauri-apps/api/core";
import type {
  AppSettings,
  ImportPresetsResult,
  Preset,
  ValidationResult,
} from "./types";

export async function getSettings(): Promise<AppSettings> {
  return invoke<AppSettings>("get_settings");
}

export async function saveSettings(settings: AppSettings): Promise<void> {
  await invoke("save_settings", { settings });
}

export async function listPresets(): Promise<Preset[]> {
  return invoke<Preset[]>("list_presets");
}

export async function upsertPreset(preset: Preset): Promise<Preset> {
  return invoke<Preset>("upsert_preset", { preset });
}

export async function deletePreset(id: string): Promise<void> {
  await invoke("delete_preset", { id });
}

export async function importPresets(
  presets: Preset[],
): Promise<ImportPresetsResult> {
  return invoke<ImportPresetsResult>("import_presets", { presets });
}

export async function openPreset(id: string, query?: string): Promise<void> {
  await invoke("open_preset", { id, query: query ?? null });
}

export async function openUrl(url: string): Promise<void> {
  await invoke("open_url", { url });
}

export async function validateUrlTemplate(
  urlTemplate: string,
): Promise<ValidationResult> {
  return invoke<ValidationResult>("validate_url_template", { urlTemplate });
}

export async function showSettings(): Promise<void> {
  await invoke("show_settings");
}

export async function hideLauncher(): Promise<void> {
  await invoke("hide_launcher");
}

export async function getWindowLabel(): Promise<string> {
  return invoke<string>("get_window_label");
}
