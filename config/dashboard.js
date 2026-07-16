const effortOrder = ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"];
const translations = {
  zh: {
    appTitle: "至尊 Codex 皮肤面板", saved: "已保存", reset: "恢复默认", save: "保存配置",
    effortMap: "档位装扮", themeEditor: "主题编辑", duplicate: "复制当前", newTheme: "新建配色",
    delete: "删除", builtinPreset: "内置预设", themeName: "主题名称", material: "材质",
    polished: "镜面", brushed: "拉丝", satin: "缎面", carbon: "碳纤维", texture: "纹理强度",
    shineAngle: "光泽角度", preview: "Codex 预览", previewUser: "为当前任务整理实现方案",
    previewPlan: "实现计划", previewAssistant: "配置已读取，主题会随推理档位自动切换。",
    previewPlaceholder: "继续描述任务…", syncNote: "配置会同步到 Codex；保存后约 1.5 秒自动应用。",
    previewEffort: "预览档位", sendPreview: "发送预览消息", waiting: "待保存", saving: "保存中",
    saveFailed: "保存失败", savedAuto: "已保存 · Codex 自动更新", unchanged: "保持原样",
    presets: "预设", customThemes: "我的配色", effortTheme: "{effort}档主题",
    hexColor: "{field}十六进制颜色", builtinEditable: "内置预设 · 复制后可编辑",
    customEditable: "我的配色 · 可编辑", copySuffix: "副本", newColor: "新配色 {number}",
    effortMinimal: "最小", effortLow: "低", effortMedium: "中", effortHigh: "高",
    effortXhigh: "极高", effortMax: "最大", effortUltra: "巅峰",
    backgroundStart: "背景起始", backgroundEnd: "背景高光", surface: "表面", accent: "强调",
    text: "字体", border: "边框", themeGold: "鎏金", themeSilver: "镜银", themeCopper: "赤铜",
    themeCarbon: "碳纤维"
  },
  en: {
    appTitle: "Supreme Codex Skin Panel", saved: "Saved", reset: "Reset", save: "Save",
    effortMap: "Effort Styles", themeEditor: "Theme Editor", duplicate: "Duplicate", newTheme: "New Theme",
    delete: "Delete", builtinPreset: "Built-in preset", themeName: "Theme name", material: "Material",
    polished: "Polished", brushed: "Brushed", satin: "Satin", carbon: "Carbon Fiber", texture: "Texture",
    shineAngle: "Shine angle", preview: "Codex Preview", previewUser: "Outline an implementation plan for this task",
    previewPlan: "Implementation Plan", previewAssistant: "Configuration loaded. The theme follows the reasoning effort automatically.",
    previewPlaceholder: "Describe the next task…", syncNote: "Settings sync to Codex and apply about 1.5 seconds after saving.",
    previewEffort: "Preview effort", sendPreview: "Send preview message", waiting: "Unsaved", saving: "Saving",
    saveFailed: "Save failed", savedAuto: "Saved · Codex updates automatically", unchanged: "Default appearance",
    presets: "Presets", customThemes: "My Themes", effortTheme: "Theme for {effort}",
    hexColor: "{field} hexadecimal color", builtinEditable: "Built-in preset · Duplicate to edit",
    customEditable: "My theme · Editable", copySuffix: "Copy", newColor: "New Theme {number}",
    effortMinimal: "Minimal", effortLow: "Low", effortMedium: "Medium", effortHigh: "High",
    effortXhigh: "Extra High", effortMax: "Maximum", effortUltra: "Supreme",
    backgroundStart: "Background start", backgroundEnd: "Background highlight", surface: "Surface",
    accent: "Accent", text: "Text", border: "Border", themeGold: "Gold", themeSilver: "Silver",
    themeCopper: "Copper", themeCarbon: "Carbon Fiber"
  }
};
const effortKeys = {
  minimal: "effortMinimal", low: "effortLow", medium: "effortMedium", high: "effortHigh",
  xhigh: "effortXhigh", max: "effortMax", ultra: "effortUltra"
};
const builtInThemeKeys = { gold: "themeGold", silver: "themeSilver", copper: "themeCopper", carbon: "themeCarbon" };
const colorFields = ["backgroundStart", "backgroundEnd", "surface", "accent", "text", "border"];

let payload;
let settings;
let defaults;
let activeTheme = "gold";
let saveTimer;
let currentLanguage = localStorage.getItem("codex-theme-language") ||
  (navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en");

const byId = (id) => document.getElementById(id);
const clone = (value) => JSON.parse(JSON.stringify(value));
const t = (key, values = {}) => Object.entries(values).reduce(
  (text, [name, value]) => text.replace(`{${name}}`, value),
  translations[currentLanguage][key] || key
);
const effortLabel = (effort) => t(effortKeys[effort]);
const materialLabel = (material) => t(material);
const themeDisplayName = (themeId, theme) => theme.builtin && builtInThemeKeys[themeId]
  ? t(builtInThemeKeys[themeId])
  : theme.name;

function applyLanguage() {
  document.documentElement.lang = currentLanguage === "zh" ? "zh-CN" : "en";
  document.title = t("appTitle");
  document.querySelectorAll("[data-i18n]").forEach((element) => {
    element.textContent = t(element.dataset.i18n);
  });
  document.querySelectorAll("[data-i18n-aria]").forEach((element) => {
    element.ariaLabel = t(element.dataset.i18nAria);
  });
  byId("languageButton").textContent = currentLanguage === "zh" ? "English" : "中文";
  if (!settings) return;
  const previewEffort = byId("previewEffort").value || "xhigh";
  renderPreviewEfforts(previewEffort);
  renderEfforts();
  renderThemeTabs();
  renderEditor();
  updatePreview();
}

function setSaveState(state, text) {
  const element = byId("saveState");
  element.dataset.state = state;
  element.textContent = text;
}

function markDirty() {
  setSaveState("saving", t("waiting"));
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveSettings, 550);
}

async function saveSettings() {
  clearTimeout(saveTimer);
  setSaveState("saving", t("saving"));
  try {
    const response = await fetch("/api/update", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ theme_settings: settings })
    });
    const result = await response.json();
    if (!response.ok || !result.ok) throw new Error(result.error || t("saveFailed"));
    setSaveState("saved", t("savedAuto"));
  } catch (error) {
    setSaveState("error", error.message);
  }
}

function themeOptions(selected) {
  const fragment = document.createDocumentFragment();
  const none = document.createElement("option");
  none.value = "none";
  none.textContent = t("unchanged");
  none.selected = selected === "none";
  fragment.append(none);
  for (const [label, builtin] of [[t("presets"), true], [t("customThemes"), false]]) {
    const group = document.createElement("optgroup");
    group.label = label;
    for (const [id, theme] of Object.entries(settings.themes)) {
      if (Boolean(theme.builtin) !== builtin) continue;
      const option = document.createElement("option");
      option.value = id;
      option.textContent = themeDisplayName(id, theme);
      option.selected = id === selected;
      group.append(option);
    }
    if (group.children.length) fragment.append(group);
  }
  return fragment;
}

function renderEfforts() {
  const list = byId("effortList");
  list.replaceChildren();
  let enabled = 0;
  for (const effort of effortOrder) {
    const themeId = settings.efforts[effort] || "none";
    if (themeId !== "none") enabled += 1;
    const row = document.createElement("div");
    row.className = "effort-row";

    const name = document.createElement("div");
    name.className = "effort-name";
    const strong = document.createElement("strong");
    strong.textContent = effortLabel(effort);
    const code = document.createElement("span");
    code.textContent = effort.toUpperCase();
    name.append(strong, code);

    const select = document.createElement("select");
    select.ariaLabel = t("effortTheme", { effort: effortLabel(effort) });
    select.append(themeOptions(themeId));
    select.addEventListener("change", () => {
      settings.efforts[effort] = select.value;
      renderEfforts();
      updatePreview();
      markDirty();
    });

    const swatch = document.createElement("span");
    swatch.className = "theme-swatch";
    swatch.style.background = themeId === "none" ? "#353a3f" : settings.themes[themeId].accent;
    row.append(name, select, swatch);
    list.append(row);
  }
  byId("enabledCount").textContent = `${enabled} / ${effortOrder.length}`;
}

function renderThemeTabs() {
  const tabs = byId("themeTabs");
  tabs.replaceChildren();
  for (const [themeId, theme] of Object.entries(settings.themes)) {
    const button = document.createElement("button");
    button.type = "button";
    button.role = "tab";
    button.ariaSelected = String(themeId === activeTheme);
    button.dataset.builtin = String(Boolean(theme.builtin));
    button.textContent = themeDisplayName(themeId, theme);
    button.addEventListener("click", () => {
      activeTheme = themeId;
      renderThemeTabs();
      renderEditor();
    });
    tabs.append(button);
  }
}

function renderColors(theme, readonly) {
  const grid = byId("colorGrid");
  grid.replaceChildren();
  for (const key of colorFields) {
    const label = t(key);
    const wrapper = document.createElement("div");
    wrapper.className = "color-control";
    const color = document.createElement("input");
    color.className = "color-input";
    color.type = "color";
    color.value = theme[key];
    color.disabled = readonly;
    color.id = `color-${key}`;
    const text = document.createElement("input");
    text.className = "color-text";
    text.type = "text";
    text.maxLength = 7;
    text.value = theme[key];
    text.disabled = readonly;
    text.ariaLabel = t("hexColor", { field: label });
    const caption = document.createElement("label");
    caption.htmlFor = color.id;
    caption.textContent = label;

    color.addEventListener("input", () => {
      theme[key] = color.value;
      text.value = color.value.toUpperCase();
      renderEfforts();
      updatePreview();
      markDirty();
    });
    text.addEventListener("change", () => {
      if (/^#[0-9a-f]{6}$/i.test(text.value)) {
        theme[key] = text.value.toUpperCase();
        color.value = text.value;
        renderEfforts();
        updatePreview();
        markDirty();
      } else {
        text.value = theme[key];
      }
    });
    wrapper.append(color, caption, text);
    grid.append(wrapper);
  }
}

function renderEditor() {
  const theme = settings.themes[activeTheme];
  const readonly = Boolean(theme.builtin);
  const name = byId("themeName");
  name.value = themeDisplayName(activeTheme, theme);
  name.disabled = readonly;
  name.oninput = () => {
    theme.name = name.value.trim() || activeTheme;
    renderThemeTabs();
    renderEfforts();
    updatePreview();
    markDirty();
  };

  document.querySelectorAll("#materialControl button").forEach((button) => {
    button.ariaPressed = String(button.dataset.material === theme.material);
    button.disabled = readonly;
    button.onclick = () => {
      theme.material = button.dataset.material;
      renderEditor();
      updatePreview();
      markDirty();
    };
  });

  renderColors(theme, readonly);
  const texture = byId("textureOpacity");
  const angle = byId("shineAngle");
  texture.value = theme.textureOpacity;
  angle.value = theme.shineAngle;
  texture.disabled = readonly;
  angle.disabled = readonly;
  byId("textureValue").value = Number(theme.textureOpacity).toFixed(2);
  byId("angleValue").value = `${theme.shineAngle}°`;
  texture.oninput = () => {
    theme.textureOpacity = Number(texture.value);
    byId("textureValue").value = theme.textureOpacity.toFixed(2);
    updatePreview();
    markDirty();
  };
  angle.oninput = () => {
    theme.shineAngle = Number(angle.value);
    byId("angleValue").value = `${theme.shineAngle}°`;
    updatePreview();
    markDirty();
  };
  byId("presetBanner").textContent = readonly ? t("builtinEditable") : t("customEditable");
  byId("presetBanner").dataset.kind = readonly ? "preset" : "custom";
  byId("editorContent").dataset.readonly = String(readonly);
  byId("deleteTheme").disabled = readonly;
}

function nextThemeId() {
  let index = 1;
  while (settings.themes[`custom-${index}`]) index += 1;
  return `custom-${index}`;
}

function addTheme(source, name) {
  const id = nextThemeId();
  settings.themes[id] = { ...clone(source), name, builtin: false };
  activeTheme = id;
  renderThemeTabs();
  renderEditor();
  renderEfforts();
  updatePreview();
  markDirty();
}

function deleteActiveTheme() {
  const theme = settings.themes[activeTheme];
  if (!theme || theme.builtin) return;
  const removedId = activeTheme;
  delete settings.themes[removedId];
  for (const effort of effortOrder) {
    if (settings.efforts[effort] === removedId) settings.efforts[effort] = "none";
  }
  activeTheme = settings.themes.gold ? "gold" : Object.keys(settings.themes)[0];
  renderThemeTabs();
  renderEditor();
  renderEfforts();
  updatePreview();
  markDirty();
}

function renderPreviewEfforts(selectedEffort = "xhigh") {
  const select = byId("previewEffort");
  select.replaceChildren();
  for (const effort of effortOrder) {
    const option = document.createElement("option");
    option.value = effort;
    option.textContent = `${effortLabel(effort)} · ${effort}`;
    option.selected = effort === selectedEffort;
    select.append(option);
  }
  select.onchange = updatePreview;
}

function updatePreview() {
  const effort = byId("previewEffort").value || "xhigh";
  const themeId = settings.efforts[effort] || "none";
  const preview = byId("codexPreview");
  preview.dataset.theme = themeId;
  if (themeId === "none") {
    preview.dataset.material = "satin";
    byId("previewBadge").textContent = `${effort} · ${t("unchanged")}`;
    return;
  }
  const theme = settings.themes[themeId];
  preview.dataset.material = theme.material;
  const values = {
    "--p-start": theme.backgroundStart, "--p-end": theme.backgroundEnd,
    "--p-surface": theme.surface, "--p-accent": theme.accent,
    "--p-text": theme.text, "--p-border": theme.border,
    "--p-opacity": theme.textureOpacity, "--p-angle": `${theme.shineAngle}deg`
  };
  for (const [property, value] of Object.entries(values)) preview.style.setProperty(property, value);
  byId("previewBadge").textContent = `${effort} · ${themeDisplayName(themeId, theme)} · ${materialLabel(theme.material)}`;
}

async function initialize() {
  applyLanguage();
  const response = await fetch("/api/data", { cache: "no-store" });
  payload = await response.json();
  settings = clone(payload.themeSettings);
  defaults = clone(payload.defaults);
  byId("projectName").textContent = payload.project;
  if (!settings.themes[activeTheme]) activeTheme = Object.keys(settings.themes)[0];
  renderPreviewEfforts();
  renderEfforts();
  renderThemeTabs();
  renderEditor();
  updatePreview();
  byId("saveButton").addEventListener("click", saveSettings);
  byId("languageButton").addEventListener("click", () => {
    currentLanguage = currentLanguage === "zh" ? "en" : "zh";
    localStorage.setItem("codex-theme-language", currentLanguage);
    applyLanguage();
  });
  byId("duplicateTheme").addEventListener("click", () => {
    const source = settings.themes[activeTheme];
    addTheme(source, `${themeDisplayName(activeTheme, source)} ${t("copySuffix")}`);
  });
  byId("newTheme").addEventListener("click", () => {
    const source = defaults.themes.custom || settings.themes[activeTheme];
    addTheme(source, t("newColor", {
      number: Object.values(settings.themes).filter((theme) => !theme.builtin).length + 1
    }));
  });
  byId("deleteTheme").addEventListener("click", deleteActiveTheme);
  byId("resetButton").addEventListener("click", () => {
    settings = clone(defaults);
    activeTheme = settings.themes.gold ? "gold" : Object.keys(settings.themes)[0];
    renderEfforts();
    renderThemeTabs();
    renderEditor();
    updatePreview();
    markDirty();
  });
}

initialize().catch((error) => setSaveState("error", error.message));
