export type PresetKind = "agent" | "link";

export type Preset = {
  id: string;
  name: string;
  urlTemplate: string;
  kind: PresetKind;
  tags: string[];
  createdAt: string;
  updatedAt: string;
};

export type AppSettings = {
  instanceBaseUrl: string | null;
  globalShortcut: string;
  openInNewWindow: boolean;
  restrictHostToInstanceHost: boolean;
  defaultPresetId: string | null;
  debugInWebview: boolean;
  useRouteReloadForLauncherChats: boolean;
  accentColor: string;
  launcherOpacity: number;
};

export type ValidationResult = {
  valid: boolean;
  reason?: string;
};
