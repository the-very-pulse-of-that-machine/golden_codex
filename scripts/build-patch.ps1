[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$BuildPackage,
  [switch]$Install,
  [switch]$AllowInstall,
  [switch]$Launch,
  [switch]$InstallPrerequisites,
  [switch]$NoLaunch,
  [switch]$KeepWorkDir,
  [switch]$ButtonRepairOnly,
  [switch]$StableConfigOnly,
  [switch]$ExistingTrustedCertificateOnly,
  [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

function Fail {
  param([string]$Message)
  throw "[codex-gold-reasoning] $Message"
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$vendoredBaseScript = Join-Path $projectRoot 'vendor\patch_codex_fast_mode_windows_msix.ps1'
$installedBaseScript = Join-Path $env:USERPROFILE '.codex\skills\codex-windows-fast-patch\scripts\patch_codex_fast_mode_windows_msix.ps1'
$baseScript = if (Test-Path -LiteralPath $vendoredBaseScript -PathType Leaf) { $vendoredBaseScript } else { $installedBaseScript }
if (-not (Test-Path -LiteralPath $baseScript -PathType Leaf)) {
  Fail "base Codex MSIX patch script not found: $baseScript"
}

if ($Install) {
  Fail 'direct installation is disabled in the build script. Build first, then run scripts\install-patch.ps1 from elevated PowerShell.'
}

if (-not $DryRun -and -not $BuildPackage -and -not $Install) {
  Write-Host '[codex-gold-reasoning] no action mode specified; defaulting to -DryRun'
  $DryRun = $true
}

$themeSettingsPath = Join-Path $projectRoot 'config\theme-settings.json'
$defaultThemeSettingsPath = Join-Path $projectRoot 'config\theme-settings.default.json'
if (-not (Test-Path -LiteralPath $themeSettingsPath -PathType Leaf)) {
  if (-not (Test-Path -LiteralPath $defaultThemeSettingsPath -PathType Leaf)) {
    Fail "theme settings and fallback are both missing: $themeSettingsPath"
  }
  Write-Host "[codex-gold-reasoning] theme settings missing; using fallback: $defaultThemeSettingsPath"
  $themeSettingsPath = $defaultThemeSettingsPath
}

function Assert-HexColor {
  param([string]$Value, [string]$Name)
  if ($Value -notmatch '^#[0-9a-fA-F]{6}$') {
    Fail "theme color $Name must use #RRGGBB: $Value"
  }
}

function Get-ColorScheme {
  param([string]$HexColor)
  $red = [Convert]::ToInt32($HexColor.Substring(1, 2), 16)
  $green = [Convert]::ToInt32($HexColor.Substring(3, 2), 16)
  $blue = [Convert]::ToInt32($HexColor.Substring(5, 2), 16)
  $luminance = (0.2126 * $red) + (0.7152 * $green) + (0.0722 * $blue)
  if ($luminance -lt 140) { return 'dark' }
  return 'light'
}

function Get-MaterialBackground {
  param($Theme)
  $angle = [int]$Theme.shineAngle
  switch ([string]$Theme.material) {
    'polished' {
      return "radial-gradient(circle at 20% 0%, rgba(255,255,255,.92), transparent 25rem), linear-gradient(${angle}deg, $($Theme.backgroundStart) 0%, $($Theme.accent) 25%, $($Theme.surface) 48%, $($Theme.backgroundEnd) 72%, $($Theme.backgroundStart) 100%)"
    }
    'satin' {
      return "linear-gradient(${angle}deg, $($Theme.backgroundStart) 0%, $($Theme.accent) 34%, $($Theme.surface) 52%, $($Theme.backgroundEnd) 76%, $($Theme.backgroundStart) 100%)"
    }
    'carbon' {
      return "linear-gradient(${angle}deg, rgba(255,255,255,.08), transparent 42%), repeating-linear-gradient(45deg, $($Theme.backgroundStart) 0 8px, $($Theme.surface) 8px 16px)"
    }
    default {
      return "radial-gradient(circle at 18% 0%, rgba(255,255,255,.78), transparent 23rem), linear-gradient(${angle}deg, $($Theme.backgroundStart) 0%, $($Theme.accent) 24%, $($Theme.surface) 44%, $($Theme.backgroundEnd) 68%, $($Theme.backgroundStart) 100%)"
    }
  }
}

$themeSettings = Get-Content -Raw -Encoding UTF8 -LiteralPath $themeSettingsPath | ConvertFrom-Json # [code2config] injected
$allowedEfforts = @('minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra')
$allowedMaterials = @('polished', 'brushed', 'satin', 'carbon')
$effortMap = [ordered]@{}
foreach ($effort in $allowedEfforts) {
  $themeId = [string]$themeSettings.efforts.$effort
  if ([string]::IsNullOrWhiteSpace($themeId)) { $themeId = 'none' }
  if ($themeId -ne 'none' -and -not $themeSettings.themes.PSObject.Properties[$themeId]) {
    Fail "effort $effort references missing theme: $themeId"
  }
  $effortMap[$effort] = $themeId
}

foreach ($property in $themeSettings.themes.PSObject.Properties) {
  $themeId = $property.Name
  $theme = $property.Value
  if ($themeId -notmatch '^[a-z][a-z0-9-]{0,31}$') {
    Fail "invalid theme id: $themeId"
  }
  if ([string]$theme.material -notin $allowedMaterials) {
    Fail "invalid material for theme ${themeId}: $($theme.material)"
  }
  foreach ($colorName in @('backgroundStart', 'backgroundEnd', 'surface', 'accent', 'text', 'border')) {
    Assert-HexColor ([string]$theme.$colorName) "$themeId.$colorName"
  }
  $textureOpacity = [double]$theme.textureOpacity
  $shineAngle = [int]$theme.shineAngle
  if ($textureOpacity -lt 0 -or $textureOpacity -gt 0.6) {
    Fail "textureOpacity for theme $themeId must be between 0 and 0.6"
  }
  if ($shineAngle -lt 0 -or $shineAngle -gt 360) {
    Fail "shineAngle for theme $themeId must be between 0 and 360"
  }
}

$fallbackConfigJson = $themeSettings | ConvertTo-Json -Depth 8 -Compress
$generatedJs = @"
/* codex-reasoning-theme-config-v1:start */
;(()=>{const observerKey="__codexReasoningThemeConfigObserver",legacyObserverKey="__codexGoldReasoningPackageObserver",pollKey="__codexReasoningThemeConfigPoll",selector='[data-composer-navigation-target="reasoning"][data-selected-reasoning-effort]',fallback=$fallbackConfigJson,efforts=["minimal","low","medium","high","xhigh","max","ultra"],materials=new Set(["polished","brushed","satin","carbon"]),colors=["backgroundStart","backgroundEnd","surface","accent","text","border"],hex=/^#[0-9a-f]{6}$/i,properties=["--codex-theme-start","--codex-theme-end","--codex-theme-surface","--codex-theme-accent","--codex-theme-text","--codex-theme-border","--codex-theme-opacity","--codex-theme-angle","--codex-theme-color-scheme"];function valid(value){if(!value||value.version!==1||!value.efforts||typeof value.efforts!=="object"||!value.themes||typeof value.themes!=="object"||Object.keys(value.themes).length===0)return null;for(const effort of efforts){const id=value.efforts[effort]||"none";if(id!=="none"&&!value.themes[id])return null}for(const[id,theme]of Object.entries(value.themes)){if(!/^[a-z][a-z0-9-]{0,31}$/.test(id)||!theme||!materials.has(theme.material)||colors.some(key=>!hex.test(String(theme[key]||"")))||!Number.isFinite(Number(theme.textureOpacity))||Number(theme.textureOpacity)<0||Number(theme.textureOpacity)>0.6||!Number.isInteger(Number(theme.shineAngle))||Number(theme.shineAngle)<0||Number(theme.shineAngle)>360)return null}return value}const external=(()=>{try{return window.codexReasoningThemeConfig?.read?.()}catch{return null}})(),config=valid(external)||fallback;let observedTrigger=null,lastSignature="";function clear(root){root.removeAttribute("data-codex-gold-reasoning");root.removeAttribute("data-codex-reasoning-theme");root.removeAttribute("data-codex-reasoning-material");for(const property of properties)root.style.removeProperty(property)}function resolveEffort(trigger){let effort=trigger?.getAttribute("data-selected-reasoning-effort");const maximum=trigger?.getAttribute("data-max-effort")==="true"||trigger?.querySelector('[data-max-effort="true"]');if(maximum&&(!effort||config.efforts[effort]==="none"))effort=["ultra","max","xhigh"].find(candidate=>config.efforts[candidate]&&config.efforts[candidate]!=="none")||effort;return effort}function update(){const root=document.documentElement,effort=resolveEffort(observedTrigger),themeId=config.efforts[effort]||"none",theme=config.themes[themeId],signature=theme?JSON.stringify([effort,themeId,theme.material,...colors.map(key=>theme[key]),theme.textureOpacity,theme.shineAngle]):"none";if(signature===lastSignature)return;lastSignature=signature;clear(root);if(themeId==="none"||!theme)return;const start=parseInt(theme.backgroundStart.slice(1),16),red=start>>16,green=start>>8&255,blue=start&255,luminance=.2126*red+.7152*green+.0722*blue;root.dataset.codexReasoningTheme=themeId;root.dataset.codexReasoningMaterial=theme.material;const values={"--codex-theme-start":theme.backgroundStart,"--codex-theme-end":theme.backgroundEnd,"--codex-theme-surface":theme.surface,"--codex-theme-accent":theme.accent,"--codex-theme-text":theme.text,"--codex-theme-border":theme.border,"--codex-theme-opacity":String(theme.textureOpacity),"--codex-theme-angle":theme.shineAngle+"deg","--codex-theme-color-scheme":luminance<140?"dark":"light"};for(const[property,value]of Object.entries(values))root.style.setProperty(property,value)}function attach(){const trigger=document.querySelector(selector);if(trigger===observedTrigger){update();return}window[observerKey]?.disconnect();observedTrigger=trigger;lastSignature="";const observer=new MutationObserver(update);if(trigger)observer.observe(trigger,{subtree:true,childList:true,attributes:true,attributeFilter:["data-selected-reasoning-effort","data-max-effort"]});window[observerKey]=observer;update()}function start(){window[legacyObserverKey]?.disconnect();window[observerKey]?.disconnect();clearInterval(window[pollKey]);attach();window[pollKey]=setInterval(attach,750)}document.readyState==="loading"?document.addEventListener("DOMContentLoaded",start,{once:true}):start()})();
/* codex-reasoning-theme-config-v1:end */
"@
$generatedStableConfigJs = @"
/* codex-gold-reasoning-config-v1:start */
;(()=>{const observerKey="__codexGoldReasoningPackageObserver",pollKey="__codexReasoningThemeConfigFilePoll",styleId="codex-reasoning-theme-runtime-style",fallback=$fallbackConfigJson,efforts=["minimal","low","medium","high","xhigh","max","ultra"],materials=new Set(["polished","brushed","satin","carbon"]),colors=["backgroundStart","backgroundEnd","surface","accent","text","border"],hex=/^#[0-9a-f]{6}$/i;function valid(value){if(!value||value.version!==1||!value.efforts||typeof value.efforts!=="object"||!value.themes||typeof value.themes!=="object"||Object.keys(value.themes).length===0)return null;for(const effort of efforts){const id=String(value.efforts[effort]||"none");if(id!=="none"&&!value.themes[id])return null}for(const[id,theme]of Object.entries(value.themes)){if(!/^[a-z][a-z0-9-]{0,31}$/.test(id)||!theme||!materials.has(theme.material)||colors.some(key=>!hex.test(String(theme[key]||""))))return null}return value}function readConfig(){try{return valid(window.electronBridge?.readReasoningThemeConfig?.())||valid(window.codexReasoningThemeConfig?.read?.())||fallback}catch{return fallback}}let config=readConfig(),configSignature=JSON.stringify(config);function background(theme){const angle=Number.isInteger(Number(theme.shineAngle))?Number(theme.shineAngle):120;if(theme.material==="carbon")return"linear-gradient("+angle+"deg,rgba(255,255,255,.08),transparent 42%),repeating-linear-gradient(45deg,"+theme.backgroundStart+" 0 8px,"+theme.surface+" 8px 16px)";if(theme.material==="satin")return"linear-gradient("+angle+"deg,"+theme.backgroundStart+" 0%,"+theme.accent+" 34%,"+theme.surface+" 52%,"+theme.backgroundEnd+" 76%,"+theme.backgroundStart+" 100%)";if(theme.material==="polished")return"radial-gradient(circle at 20% 0%,rgba(255,255,255,.92),transparent 25rem),linear-gradient("+angle+"deg,"+theme.backgroundStart+" 0%,"+theme.accent+" 25%,"+theme.surface+" 48%,"+theme.backgroundEnd+" 72%,"+theme.backgroundStart+" 100%)";return"radial-gradient(circle at 18% 0%,rgba(255,255,255,.78),transparent 23rem),linear-gradient("+angle+"deg,"+theme.backgroundStart+" 0%,"+theme.accent+" 24%,"+theme.surface+" 44%,"+theme.backgroundEnd+" 68%,"+theme.backgroundStart+" 100%)"}function themeCss(){const rules=[];for(const[id,theme]of Object.entries(config.themes)){const selector='html[data-codex-reasoning-theme="'+id+'"]',surface=parseInt(theme.surface.slice(1),16),red=surface>>16,green=surface>>8&255,blue=surface&255,luminance=.2126*red+.7152*green+.0722*blue,scheme=luminance<140?"dark":"light",angle=Number.isInteger(Number(theme.shineAngle))?Number(theme.shineAngle):120,opacity=Math.max(0,Math.min(.6,Number(theme.textureOpacity)||0)),componentBackground="linear-gradient("+angle+"deg,"+theme.surface+","+theme.accent+" 48%,"+theme.backgroundEnd+")",componentSelectors=[' [class*="bg-token-"]',' [class*="bg-primary"]',' [class*="bg-secondary"]',' aside',' header',' nav',' main',' section',' [role="dialog"]',' [role="menu"]',' textarea',' input'].map(part=>selector+part).join(','),controlSelectors=[' button',' [role="button"]',' [role="menuitem"]',' [data-radix-collection-item]',' svg',' [class*="text-token-"]'].map(part=>selector+part).join(',');let texture="linear-gradient("+angle+"deg,transparent 0 18%,rgba(255,255,255,.7) 23%,transparent 29% 58%,rgba(255,255,255,.55) 63%,transparent 70%),repeating-linear-gradient(100deg,rgba(255,255,255,.14) 0 1px,transparent 1px 9px)";if(theme.material==="polished")texture="linear-gradient("+angle+"deg,transparent 0 22%,rgba(255,255,255,.82) 28%,transparent 35% 66%,rgba(255,255,255,.5) 72%,transparent 80%)";else if(theme.material==="satin")texture="repeating-linear-gradient("+angle+"deg,rgba(255,255,255,.08) 0 2px,transparent 2px 12px)";else if(theme.material==="carbon")texture="repeating-linear-gradient(135deg,rgba(255,255,255,.12) 0 2px,transparent 2px 8px),repeating-linear-gradient(45deg,rgba(0,0,0,.2) 0 2px,transparent 2px 8px)";rules.push(selector+"{--token-main-surface-primary:"+theme.surface+"!important;--token-main-surface-secondary:"+theme.backgroundEnd+"!important;--token-main-surface-tertiary:"+theme.accent+"!important;--token-sidebar-surface-primary:color-mix(in srgb,"+theme.accent+" 70%,"+theme.backgroundStart+")!important;--token-sidebar-surface-secondary:color-mix(in srgb,"+theme.accent+" 75%,"+theme.backgroundEnd+")!important;--token-input-background:"+theme.surface+"!important;--token-border-default:"+theme.border+"!important;--token-border-medium:"+theme.border+"!important;--token-foreground:"+theme.text+"!important;--token-description-foreground:"+theme.text+"!important;--token-text-secondary:"+theme.text+"!important;--token-text-tertiary:"+theme.text+"!important;color-scheme:"+scheme+"!important}");rules.push(selector+","+selector+" body,"+selector+" #root{background:"+background(theme)+"!important;color:"+theme.text+"!important}");rules.push(selector+" body::before{content:\"\";position:fixed;inset:0;pointer-events:none;z-index:2147483647;opacity:"+opacity+";background:"+texture+";mix-blend-mode:screen}");rules.push(componentSelectors+"{background-image:"+componentBackground+"!important;border-color:"+theme.border+"!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.36),0 0 0 1px "+theme.border+"!important}");rules.push(controlSelectors+"{color:"+theme.text+"!important;border-color:"+theme.border+"!important}")}return rules.join("\n")}function installStyle(){let style=document.getElementById(styleId);if(!style){style=document.createElement("style");style.id=styleId;document.head.appendChild(style)}style.textContent=themeCss()}function update(){const trigger=document.querySelector('[data-composer-navigation-target="reasoning"][data-selected-reasoning-effort]'),maximum=trigger?.getAttribute("data-max-effort")==="true"||!!trigger?.querySelector('[data-max-effort="true"]');let effort=trigger?.getAttribute("data-selected-reasoning-effort");if(maximum&&(!effort||String(config.efforts[effort]||"none")==="none"))effort=["ultra","max","xhigh"].find(candidate=>String(config.efforts[candidate]||"none")!=="none")||effort;const themeId=String(config.efforts[effort]||"none"),root=document.documentElement;root.dataset.codexGoldReasoning="false";if(themeId==="none"||!config.themes[themeId])root.removeAttribute("data-codex-reasoning-theme");else root.dataset.codexReasoningTheme=themeId;window.electronBridge?.writeReasoningThemeStatus?.({effort:effort||null,themeId,hasTrigger:!!trigger,maximum,updatedAt:Date.now()})}function reload(){const next=readConfig(),signature=JSON.stringify(next);if(signature===configSignature)return;config=next;configSignature=signature;installStyle();update()}function start(){installStyle();window[observerKey]?.disconnect();clearInterval(window[pollKey]);const observer=new MutationObserver(update);observer.observe(document.documentElement,{subtree:true,childList:true,attributes:true,attributeFilter:["data-max-effort","data-selected-reasoning-effort"]});window[observerKey]=observer;window[pollKey]=setInterval(reload,1500);reload();update()}document.readyState==="loading"?document.addEventListener("DOMContentLoaded",start,{once:true}):start()})();
/* codex-gold-reasoning-config-v1:end */
"@
$unsafeComponentSelectors = 'componentSelectors=['' [class*="bg-token-"]'','' [class*="bg-primary"]'','' [class*="bg-secondary"]'','' aside'','' header'','' nav'','' main'','' section'','' [role="dialog"]'','' [role="menu"]'','' textarea'','' input''].map(part=>selector+part).join('','')'
$safeComponentSelectors = 'componentSelectors=['' [class*="bg-token-"]'','' [class*="bg-primary"]'','' [class*="bg-secondary"]'','' [role="dialog"]'','' [role="menu"]''].map(part=>selector+part).join('',''),layoutSelectors=['' aside'','' header'','' nav'','' main'','' section''].map(part=>selector+part).join('',''),framedControlSelectors=['' button'','' [role="button"]'','' [role="menuitem"]'','' [data-radix-collection-item]''].map(part=>selector+part).join('','')'
$unsafeComponentShadow = 'box-shadow:inset 0 1px 0 rgba(255,255,255,.36),0 0 0 1px "+theme.border+"!important'
$safeComponentShadow = 'box-shadow:inset 0 1px 0 rgba(255,255,255,.36)!important'
if (-not $generatedStableConfigJs.Contains($unsafeComponentSelectors) -or -not $generatedStableConfigJs.Contains($unsafeComponentShadow)) {
  Fail 'stable theme runtime no longer contains the expected component decoration rules'
}
$generatedStableConfigJs = $generatedStableConfigJs.Replace($unsafeComponentSelectors, $safeComponentSelectors).Replace($unsafeComponentShadow, $safeComponentShadow)
$safeComponentRule = 'rules.push(componentSelectors+"{background-image:"+componentBackground+"!important;border-color:"+theme.border+"!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.36)!important}")'
$roundedComponentRule = 'rules.push(componentSelectors+"{background-image:"+componentBackground+"!important;border:1px solid "+theme.border+"!important;border-radius:8px!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.36)!important}")'
$layoutAndComponentRules = 'rules.push(layoutSelectors+"{background-image:"+componentBackground+"!important}");'+$roundedComponentRule+';rules.push(framedControlSelectors+"{border:1px solid "+theme.border+"!important;border-radius:8px!important}")'
if (-not $generatedStableConfigJs.Contains($safeComponentRule)) {
  Fail 'stable theme runtime component rule was not repaired before layout background split'
}
$generatedStableConfigJs = $generatedStableConfigJs.Replace($safeComponentRule, $layoutAndComponentRules)
if ($generatedStableConfigJs.Contains($unsafeComponentSelectors) -or
    $generatedStableConfigJs.Contains($unsafeComponentShadow) -or
    -not $generatedStableConfigJs.Contains($safeComponentSelectors) -or
    -not $generatedStableConfigJs.Contains($safeComponentShadow) -or
    -not $generatedStableConfigJs.Contains($layoutAndComponentRules) -or
    $generatedStableConfigJs.Contains(".join(',').map(")) {
  Fail 'stable theme runtime component decoration repair did not apply cleanly'
}
$conversationTextNeedle = 'rules.push(controlSelectors+"{color:"+theme.text+"!important;border-color:"+theme.border+"!important}")'
$conversationTextReplacement = 'rules.push(controlSelectors+"{color:"+theme.text+"!important;border-color:"+theme.border+"!important}");const conversationSelectors=[" [data-chatgpt-conversation-turn]"," [data-chatgpt-conversation-turn] p"," [data-chatgpt-conversation-turn] li"," [data-chatgpt-conversation-turn] h1"," [data-chatgpt-conversation-turn] h2"," [data-chatgpt-conversation-turn] h3"," [data-chatgpt-conversation-turn] h4"," [data-chatgpt-conversation-turn] h5"," [data-chatgpt-conversation-turn] h6"," [data-chatgpt-conversation-turn] blockquote"," [data-chatgpt-conversation-turn] td"," [data-chatgpt-conversation-turn] th"," [data-chatgpt-conversation-turn] .inline-markdown"," [data-chatgpt-conversation-turn] [class*=\"text-white\"]"," [data-user-message-bubble]"," [data-user-message-bubble] p"," [data-user-message-bubble] li"," [data-virtualized-turn-content] p"," [data-virtualized-turn-content] li"," [data-chatgpt-conversation-turn=\"true\"] :is(p,li,h1,h2,h3,h4,h5,h6,blockquote,td,th,span,div):not(pre *):not(code *)"].map(part=>selector+part).join(",");rules.push(conversationSelectors+"{color:"+theme.text+"!important}")'
if (-not $generatedStableConfigJs.Contains($conversationTextNeedle)) {
  Fail 'stable theme runtime no longer contains the expected control color rule'
}
$generatedStableConfigJs = $generatedStableConfigJs.Replace($conversationTextNeedle, $conversationTextReplacement)
$rendererConfigRead = 'function readConfig(){try{return valid(window.electronBridge?.readReasoningThemeConfig?.())||valid(window.codexReasoningThemeConfig?.read?.())||fallback}catch{return fallback}}'
$preloadConfigRead = 'const electron=require("electron"),readChannel="codex_reasoning_theme:read",statusChannel="codex_reasoning_theme:status";function readConfig(){try{return valid(electron.ipcRenderer.sendSync(readChannel))||fallback}catch{return fallback}}function writeStatus(value){try{electron.ipcRenderer.sendSync(statusChannel,value)}catch{}}writeStatus({phase:"preload",updatedAt:Date.now()});'
$rendererStatusWrite = 'window.electronBridge?.writeReasoningThemeStatus?.({effort:effort||null,themeId,hasTrigger:!!trigger,maximum,updatedAt:Date.now()})'
if (-not $generatedStableConfigJs.Contains($rendererConfigRead) -or -not $generatedStableConfigJs.Contains($rendererStatusWrite)) {
  Fail 'stable theme runtime shape changed before preload conversion'
}
$generatedStablePreloadJs = $generatedStableConfigJs.Replace($rendererConfigRead, $preloadConfigRead).Replace($rendererStatusWrite, 'writeStatus({effort:effort||null,themeId,hasTrigger:!!trigger,maximum,updatedAt:Date.now()})')
$generatedStablePreloadJs = $generatedStablePreloadJs.Replace('/* codex-gold-reasoning-config-v1:start */', '/* codex-gold-reasoning-preload-v1:start */').Replace('/* codex-gold-reasoning-config-v1:end */', '/* codex-gold-reasoning-preload-v1:end */')
$generatedStableMainJs = @'
/* codex-gold-reasoning-main-ipc-v1:start */
;(()=>{const marker="__codexReasoningThemeMainIpc",readChannel="codex_reasoning_theme:read",statusChannel="codex_reasoning_theme:status";if(globalThis[marker])return;globalThis[marker]=true;const{ipcMain}=require("electron"),fs=require("node:fs"),os=require("node:os"),path=require("node:path"),home=process.env.USERPROFILE||os.homedir(),configPath=path.join(home,"AppData","Local","Packages","OpenAI.Codex_2p2nqsd0c76g0","LocalCache","reasoning-theme","theme-settings.json"),statusPath=path.join(home,".codex","reasoning-theme","theme-status.json");ipcMain.on(readChannel,event=>{try{const stat=fs.statSync(configPath);event.returnValue=stat.isFile()&&stat.size<=1048576?JSON.parse(fs.readFileSync(configPath,"utf8")):null}catch{event.returnValue=null}});ipcMain.on(statusChannel,(event,value)=>{try{const text=JSON.stringify(value);if(text.length>16384)throw Error("theme status too large");fs.mkdirSync(path.dirname(statusPath),{recursive:true});fs.writeFileSync(statusPath,text,"utf8");event.returnValue=true}catch{event.returnValue=false}})})();
/* codex-gold-reasoning-main-ipc-v1:end */
'@
$generatedCss = @"
/* codex-reasoning-theme-config-v1:start */
html[data-codex-reasoning-theme] {
  --token-main-surface-primary: var(--codex-theme-surface) !important;
  --token-main-surface-secondary: color-mix(in srgb, var(--codex-theme-end) 70%, var(--codex-theme-accent)) !important;
  --token-main-surface-tertiary: var(--codex-theme-accent) !important;
  --token-sidebar-surface-primary: color-mix(in srgb, var(--codex-theme-accent) 70%, var(--codex-theme-start)) !important;
  --token-sidebar-surface-secondary: color-mix(in srgb, var(--codex-theme-accent) 75%, var(--codex-theme-end)) !important;
  --token-input-background: color-mix(in srgb, var(--codex-theme-surface) 88%, transparent) !important;
  --token-border-default: var(--codex-theme-border) !important;
  --token-border-medium: var(--codex-theme-border) !important;
  --token-foreground: var(--codex-theme-text) !important;
  --token-description-foreground: color-mix(in srgb, var(--codex-theme-text) 76%, var(--codex-theme-accent)) !important;
  --token-text-secondary: color-mix(in srgb, var(--codex-theme-text) 82%, var(--codex-theme-accent)) !important;
  --token-text-tertiary: color-mix(in srgb, var(--codex-theme-text) 68%, var(--codex-theme-accent)) !important;
  color-scheme: var(--codex-theme-color-scheme) !important;
}
html[data-codex-reasoning-theme], html[data-codex-reasoning-theme] body, html[data-codex-reasoning-theme] #root {
  background: radial-gradient(circle at 18% 0%, rgba(255,255,255,.78), transparent 23rem), linear-gradient(var(--codex-theme-angle), var(--codex-theme-start) 0%, var(--codex-theme-accent) 24%, var(--codex-theme-surface) 44%, var(--codex-theme-end) 68%, var(--codex-theme-start) 100%) !important;
  color: var(--codex-theme-text) !important;
}
html[data-codex-reasoning-material="polished"], html[data-codex-reasoning-material="polished"] body, html[data-codex-reasoning-material="polished"] #root {
  background: radial-gradient(circle at 20% 0%, rgba(255,255,255,.92), transparent 25rem), linear-gradient(var(--codex-theme-angle), var(--codex-theme-start) 0%, var(--codex-theme-accent) 25%, var(--codex-theme-surface) 48%, var(--codex-theme-end) 72%, var(--codex-theme-start) 100%) !important;
}
html[data-codex-reasoning-material="satin"], html[data-codex-reasoning-material="satin"] body, html[data-codex-reasoning-material="satin"] #root {
  background: linear-gradient(var(--codex-theme-angle), var(--codex-theme-start) 0%, var(--codex-theme-accent) 34%, var(--codex-theme-surface) 52%, var(--codex-theme-end) 76%, var(--codex-theme-start) 100%) !important;
}
html[data-codex-reasoning-material="carbon"], html[data-codex-reasoning-material="carbon"] body, html[data-codex-reasoning-material="carbon"] #root {
  background: linear-gradient(var(--codex-theme-angle), rgba(255,255,255,.08), transparent 42%), repeating-linear-gradient(45deg, var(--codex-theme-start) 0 8px, var(--codex-theme-surface) 8px 16px) !important;
}
/* codex-reasoning-theme-config-v1:end */
"@
$forbiddenInteractiveSelectors = @(
  'body::before',
  ' button',
  ' aside',
  ' header',
  ' nav',
  ' main',
  ' section',
  ' textarea',
  ' input',
  '[role=',
  '[class*='
)
foreach ($selector in $forbiddenInteractiveSelectors) {
  if ($generatedCss.Contains($selector)) {
    Fail "generated theme CSS may not target interactive components: $selector"
  }
}
$generatedPreload = @"
/* codex-reasoning-theme-runtime-config-v1:start */
;(()=>{const{contextBridge}=require("electron"),fs=require("node:fs"),os=require("node:os"),path=require("node:path"),configPath=path.join(process.env.USERPROFILE||os.homedir(),"AppData","Local","Packages","OpenAI.Codex_2p2nqsd0c76g0","LocalCache","reasoning-theme","theme-settings.json");contextBridge.exposeInMainWorld("codexReasoningThemeConfig",{read:()=>{try{const stat=fs.statSync(configPath);if(!stat.isFile()||stat.size>1048576)return null;return JSON.parse(fs.readFileSync(configPath,"utf8"))}catch{return null}}})})();
/* codex-reasoning-theme-runtime-config-v1:end */
"@
$generatedElectronBridgeProperty = 'readReasoningThemeConfig:()=>{try{const fs=require("node:fs"),os=require("node:os"),path=require("node:path"),configPath=path.join(process.env.USERPROFILE||os.homedir(),"AppData","Local","Packages","OpenAI.Codex_2p2nqsd0c76g0","LocalCache","reasoning-theme","theme-settings.json"),stat=fs.statSync(configPath);if(!stat.isFile()||stat.size>1048576)return null;return JSON.parse(fs.readFileSync(configPath,"utf8"))}catch{return null}},writeReasoningThemeStatus:value=>{try{const fs=require("node:fs"),os=require("node:os"),path=require("node:path"),statusPath=path.join(process.env.USERPROFILE||os.homedir(),"AppData","Local","Packages","OpenAI.Codex_2p2nqsd0c76g0","LocalCache","reasoning-theme","theme-status.json");fs.writeFileSync(statusPath,JSON.stringify(value),"utf8")}catch{}}'
$generatedJsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($generatedJs))
$generatedStableConfigJsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($generatedStableConfigJs))
$generatedStablePreloadJsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($generatedStablePreloadJs))
$generatedStableMainJsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($generatedStableMainJs))
$generatedCssBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($generatedCss))
$generatedPreloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($generatedPreload))
$generatedElectronBridgePropertyBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($generatedElectronBridgeProperty))

$tempRoot = Join-Path $env:TEMP ('codex-gold-reasoning-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$patchedScript = Join-Path $tempRoot 'patch_codex_gold_reasoning_windows_msix.ps1'

$source = Get-Content -Raw -LiteralPath $baseScript

$functionInjection = @'

function Set-GoldPatchedPackageVersion {
  param([string]$WorkPackageRoot)

  $manifestPath = Join-Path $WorkPackageRoot 'AppxManifest.xml'
  [xml]$manifest = Get-Content -Raw -LiteralPath $manifestPath
  $current = [Version]$manifest.Package.Identity.Version
  if ($current.Revision -ge 65535) {
    Fail "cannot increment package revision beyond 65535: $current"
  }
  $next = "$($current.Major).$($current.Minor).$($current.Build).$($current.Revision + 1)"
  $manifest.Package.Identity.Version = $next
  [System.IO.File]::WriteAllText($manifestPath, $manifest.OuterXml, [System.Text.UTF8Encoding]::new($false))
  Write-Log "gold reasoning package version: $current -> $next"
}

function Invoke-GoldReasoningPatch {
  param([string]$ExtractDir)

  $buttonRepairOnly = __CODEX_BUTTON_REPAIR_ONLY__
  $stableConfigOnly = __CODEX_STABLE_CONFIG_ONLY__

  $assetsDir = Join-Path $ExtractDir 'webview\assets'
  if (-not (Test-Path -LiteralPath $assetsDir -PathType Container)) {
    Fail "assets directory not found for gold reasoning patch: $assetsDir"
  }

  $changed = $false
  $blockStart = '/* codex-reasoning-theme-config-v1:start */'
  $blockEnd = '/* codex-reasoning-theme-config-v1:end */'
  $preloadBlockStart = '/* codex-reasoning-theme-runtime-config-v1:start */'
  $preloadBlockEnd = '/* codex-reasoning-theme-runtime-config-v1:end */'
  $runtimePatch = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CODEX_THEME_JS_BASE64__'))
  $stableConfigPatch = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CODEX_STABLE_CONFIG_JS_BASE64__'))
  $stablePreloadPatch = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CODEX_STABLE_PRELOAD_JS_BASE64__'))
  $stableMainPatch = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CODEX_STABLE_MAIN_JS_BASE64__'))
  $themeCss = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CODEX_THEME_CSS_BASE64__'))
  $runtimePreload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CODEX_THEME_PRELOAD_BASE64__'))
  $electronBridgeProperty = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CODEX_ELECTRON_BRIDGE_PROPERTY_BASE64__'))

  if ($stableConfigOnly) {
    $mainTarget = Get-ChildItem -LiteralPath (Join-Path $ExtractDir '.vite\build') -Filter 'main-*.js' -File -ErrorAction SilentlyContinue |
      Sort-Object Length -Descending |
      Select-Object -First 1 -ExpandProperty FullName
    if ([string]::IsNullOrWhiteSpace($mainTarget)) { Fail 'could not find Electron main bundle for theme config IPC' }
    $mainJs = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($mainTarget))
    $mainStart = '/* codex-gold-reasoning-main-ipc-v1:start */'
    $mainEnd = '/* codex-gold-reasoning-main-ipc-v1:end */'
    $mainStartIndex = $mainJs.IndexOf($mainStart, [StringComparison]::Ordinal)
    if ($mainStartIndex -ge 0) {
      $mainEndIndex = $mainJs.IndexOf($mainEnd, $mainStartIndex, [StringComparison]::Ordinal)
      if ($mainEndIndex -lt 0) { Fail 'existing theme main IPC block is missing its end marker' }
      $mainLength = ($mainEndIndex + $mainEnd.Length) - $mainStartIndex
      $mainJs = $mainJs.Remove($mainStartIndex, $mainLength).Insert($mainStartIndex, $stableMainPatch.Trim())
    } else {
      $mainJs = $mainJs + "`n" + $stableMainPatch.Trim()
    }
    [IO.File]::WriteAllBytes($mainTarget, [Text.Encoding]::UTF8.GetBytes($mainJs))
    $changed = $true
  }

  $preloadTarget = Join-Path $ExtractDir '.vite\build\preload.js'
  if (-not (Test-Path -LiteralPath $preloadTarget -PathType Leaf)) {
    Fail "preload target not found for runtime theme config: $preloadTarget"
  }
  $preload = Get-Content -Raw -LiteralPath $preloadTarget
  if (-not $preload.Contains('contextBridge.exposeInMainWorld') -or -not $preload.Contains('electronBridge')) {
    Fail 'preload target shape no longer exposes the expected Electron bridge'
  }
  $preloadStartIndex = $preload.IndexOf($preloadBlockStart, [StringComparison]::Ordinal)
  if ($buttonRepairOnly) {
    $preloadResult = 'preserved'
  } elseif ($stableConfigOnly) {
    if ($preloadStartIndex -ge 0) {
      $preloadEndIndex = $preload.IndexOf($preloadBlockEnd, $preloadStartIndex, [StringComparison]::Ordinal)
      if ($preloadEndIndex -lt 0) { Fail 'existing runtime theme preload block is missing its end marker' }
      $preloadBlockLength = ($preloadEndIndex + $preloadBlockEnd.Length) - $preloadStartIndex
      $preload = $preload.Remove($preloadStartIndex, $preloadBlockLength).TrimEnd()
    }
    $bridgePropertyPattern = ',readReasoningThemeConfig:.*?(?=\};e\.ipcRenderer\.on\(v)'
    if ($preload.Contains('readReasoningThemeConfig:')) {
      $updatedPreload = [regex]::Replace($preload, $bridgePropertyPattern, ',' + $electronBridgeProperty, [Text.RegularExpressions.RegexOptions]::Singleline)
      if ($updatedPreload -eq $preload -and -not $preload.Contains(',' + $electronBridgeProperty + '};e.ipcRenderer.on(v')) {
        Fail 'could not update existing electronBridge theme config reader'
      }
      $preload = $updatedPreload
    } else {
      $bridgeAnchor = 'usesOwlAppShell:()=>x};e.ipcRenderer.on(v'
      if (-not $preload.Contains($bridgeAnchor)) { Fail 'could not find electronBridge object end for theme config reader' }
      $preload = $preload.Replace($bridgeAnchor, 'usesOwlAppShell:()=>x,' + $electronBridgeProperty + '};e.ipcRenderer.on(v')
    }
    Set-Content -LiteralPath $preloadTarget -Value $preload -NoNewline -Encoding UTF8
    $preload = Get-Content -Raw -LiteralPath $preloadTarget
    $stablePreloadStart = '/* codex-gold-reasoning-preload-v1:start */'
    $stablePreloadEnd = '/* codex-gold-reasoning-preload-v1:end */'
    $stablePreloadStartIndex = $preload.IndexOf($stablePreloadStart, [StringComparison]::Ordinal)
    if ($stablePreloadStartIndex -ge 0) {
      $stablePreloadEndIndex = $preload.IndexOf($stablePreloadEnd, $stablePreloadStartIndex, [StringComparison]::Ordinal)
      if ($stablePreloadEndIndex -lt 0) { Fail 'existing stable preload runtime is missing its end marker' }
      $stablePreloadLength = ($stablePreloadEndIndex + $stablePreloadEnd.Length) - $stablePreloadStartIndex
      $preload = $preload.Remove($stablePreloadStartIndex, $stablePreloadLength).Insert($stablePreloadStartIndex, $stablePreloadPatch.Trim())
    } else {
      $preload = $preload + "`n" + $stablePreloadPatch.Trim()
    }
    Set-Content -LiteralPath $preloadTarget -Value $preload -NoNewline -Encoding UTF8
    $changed = $true
    $preloadResult = 'electron-bridge-and-direct-runtime-configured'
  } elseif ($preloadStartIndex -ge 0) {
    $preloadEndIndex = $preload.IndexOf($preloadBlockEnd, $preloadStartIndex, [StringComparison]::Ordinal)
    if ($preloadEndIndex -lt 0) {
      Fail 'existing runtime theme preload block is missing its end marker'
    }
    $preloadBlockLength = ($preloadEndIndex + $preloadBlockEnd.Length) - $preloadStartIndex
    $existingPreloadBlock = $preload.Substring($preloadStartIndex, $preloadBlockLength).Trim()
    if ($existingPreloadBlock -eq $runtimePreload.Trim()) {
      $preloadResult = 'already-patched'
    } else {
      $preload = $preload.Remove($preloadStartIndex, $preloadBlockLength).Insert($preloadStartIndex, $runtimePreload.Trim())
      Set-Content -LiteralPath $preloadTarget -Value $preload -NoNewline -Encoding UTF8
      $changed = $true
      $preloadResult = 'configured'
    }
  } else {
    $preload = $preload + "`n" + $runtimePreload
    Set-Content -LiteralPath $preloadTarget -Value $preload -NoNewline -Encoding UTF8
    $changed = $true
    $preloadResult = 'configured'
  }

  $dropdownTarget = $null
  foreach ($candidate in (Get-ChildItem -LiteralPath $assetsDir -Filter 'model-and-reasoning-dropdown-*.js' -File -ErrorAction SilentlyContinue)) {
    $text = Get-Content -Raw -LiteralPath $candidate.FullName
    if ($text.Contains('function gt(e)') -and $text.Contains('reasoningEffort:O') -and $text.Contains('K=pe(O,se)')) {
      $dropdownTarget = $candidate.FullName
      break
    }
  }
  if ([string]::IsNullOrWhiteSpace($dropdownTarget)) {
    Fail 'could not find model-and-reasoning dropdown target for gold reasoning patch'
  }

  if ($stableConfigOnly) {
    $webviewIndex = Join-Path $ExtractDir 'webview\index.html'
    if (-not (Test-Path -LiteralPath $webviewIndex -PathType Leaf)) {
      Fail "webview entry document not found: $webviewIndex"
    }
    $indexHtml = Get-Content -Raw -LiteralPath $webviewIndex
    $entryMatch = [regex]::Match($indexHtml, 'src=["''](?<src>\./assets/index-[^"'']+\.js)["'']', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $entryMatch.Success) {
      Fail 'could not resolve the webview module entry from webview\index.html'
    }
    $entryRelativePath = $entryMatch.Groups['src'].Value.Substring(2).Replace('/', '\')
    $entryTarget = [IO.Path]::GetFullPath((Join-Path (Join-Path $ExtractDir 'webview') $entryRelativePath))
    $assetsRoot = [IO.Path]::GetFullPath($assetsDir).TrimEnd('\') + '\'
    if (-not $entryTarget.StartsWith($assetsRoot, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $entryTarget -PathType Leaf)) {
      Fail "resolved webview entry is outside assets or missing: $entryTarget"
    }

    $stableStart = '/* codex-gold-reasoning-config-v1:start */'
    $stableEnd = '/* codex-gold-reasoning-config-v1:end */'
    foreach ($appMainCandidate in (Get-ChildItem -LiteralPath $assetsDir -Filter 'app-main-*.js' -File -ErrorAction SilentlyContinue)) {
      $appMain = Get-Content -Raw -LiteralPath $appMainCandidate.FullName
      $appMainStartIndex = $appMain.IndexOf($stableStart, [StringComparison]::Ordinal)
      if ($appMainStartIndex -lt 0) { continue }
      $appMainEndIndex = $appMain.IndexOf($stableEnd, $appMainStartIndex, [StringComparison]::Ordinal)
      if ($appMainEndIndex -lt 0) { Fail 'app-main theme config block is missing its end marker' }
      $appMainLength = ($appMainEndIndex + $stableEnd.Length) - $appMainStartIndex
      $appMain = $appMain.Remove($appMainStartIndex, $appMainLength).TrimEnd()
      Set-Content -LiteralPath $appMainCandidate.FullName -Value $appMain -NoNewline -Encoding UTF8
      $changed = $true
    }

    $entryJs = Get-Content -Raw -LiteralPath $entryTarget
    $entryStartIndex = $entryJs.IndexOf($stableStart, [StringComparison]::Ordinal)
    if ($entryStartIndex -ge 0) {
      $entryEndIndex = $entryJs.IndexOf($stableEnd, $entryStartIndex, [StringComparison]::Ordinal)
      if ($entryEndIndex -lt 0) { Fail 'webview entry theme config block is missing its end marker' }
      $entryLength = ($entryEndIndex + $stableEnd.Length) - $entryStartIndex
      $entryJs = $entryJs.Remove($entryStartIndex, $entryLength).TrimEnd()
      Set-Content -LiteralPath $entryTarget -Value $entryJs -NoNewline -Encoding UTF8
      $changed = $true
    }
  }

  $js = Get-Content -Raw -LiteralPath $dropdownTarget
  if (-not $stableConfigOnly) {
    $legacyStart = ';(()=>{const marker="codex-gold-reasoning-patch"'
    $legacyStartIndex = $js.IndexOf($legacyStart, [StringComparison]::Ordinal)
    if ($legacyStartIndex -ge 0) {
      $legacyEndIndex = $js.IndexOf('})();', $legacyStartIndex, [StringComparison]::Ordinal)
      if ($legacyEndIndex -lt 0) { Fail 'legacy reasoning patch is missing its closing marker' }
      $legacyLength = ($legacyEndIndex + 5) - $legacyStartIndex
      $js = $js.Remove($legacyStartIndex, $legacyLength)
      $changed = $true
    }
  }
  $jsStartIndex = $js.IndexOf($blockStart, [StringComparison]::Ordinal)
  if ($buttonRepairOnly) {
    $jsResult = 'preserved'
  } elseif ($stableConfigOnly) {
    $stableStart = '/* codex-gold-reasoning-config-v1:start */'
    $stableEnd = '/* codex-gold-reasoning-config-v1:end */'
    $stableStartIndex = $js.IndexOf($stableStart, [StringComparison]::Ordinal)
    if ($stableStartIndex -ge 0) {
      $stableEndIndex = $js.IndexOf($stableEnd, $stableStartIndex, [StringComparison]::Ordinal)
      if ($stableEndIndex -lt 0) { Fail 'existing stable config block is missing its end marker' }
      $stableLength = ($stableEndIndex + $stableEnd.Length) - $stableStartIndex
      $js = $js.Remove($stableStartIndex, $stableLength).TrimEnd()
    }
    $legacyStart = ';(()=>{const marker="codex-gold-reasoning-patch"'
    $legacyStartIndex = $js.IndexOf($legacyStart, [StringComparison]::Ordinal)
    if ($legacyStartIndex -ge 0) {
      $legacyEndIndex = $js.IndexOf('})();', $legacyStartIndex, [StringComparison]::Ordinal)
      if ($legacyEndIndex -lt 0) { Fail 'legacy reasoning patch is missing its closing marker' }
      $legacyLength = ($legacyEndIndex + 5) - $legacyStartIndex
      $js = $js.Remove($legacyStartIndex, $legacyLength).TrimEnd()
    }
    Set-Content -LiteralPath $dropdownTarget -Value $js -NoNewline -Encoding UTF8
    $changed = $true
    $jsResult = 'stable-trigger-preserved-runtime-in-preload'
  } elseif ($jsStartIndex -ge 0) {
    $jsEndIndex = $js.IndexOf($blockEnd, $jsStartIndex, [StringComparison]::Ordinal)
    if ($jsEndIndex -lt 0) {
      Fail 'existing theme JavaScript block is missing its end marker'
    }
    $jsBlockLength = ($jsEndIndex + $blockEnd.Length) - $jsStartIndex
    $existingJsBlock = $js.Substring($jsStartIndex, $jsBlockLength).Trim()
    if ($existingJsBlock -eq $runtimePatch.Trim()) {
      $jsResult = 'already-patched'
    } else {
      $js = $js.Remove($jsStartIndex, $jsBlockLength).Insert($jsStartIndex, $runtimePatch.Trim())
      Set-Content -LiteralPath $dropdownTarget -Value $js -NoNewline -Encoding UTF8
      $changed = $true
      $jsResult = 'configured'
    }
  } else {
    $js = $js + "`n" + $runtimePatch
    Set-Content -LiteralPath $dropdownTarget -Value $js -NoNewline -Encoding UTF8
    $changed = $true
    $jsResult = 'configured'
  }

  $cssTarget = Get-ChildItem -LiteralPath $assetsDir -Filter 'app-*.css' -File -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending |
    Select-Object -First 1 -ExpandProperty FullName
  if ([string]::IsNullOrWhiteSpace($cssTarget)) {
    Fail 'could not find app CSS target for gold reasoning patch'
  }

  $css = Get-Content -Raw -LiteralPath $cssTarget
  $legacyCssRemoved = $false
  if (-not $stableConfigOnly) {
    $legacyCssMarker = '/* codex-gold-reasoning-patch css */'
    $legacyCssStart = $css.IndexOf($legacyCssMarker, [StringComparison]::Ordinal)
    if ($legacyCssStart -ge 0) {
      $existingConfigStart = $css.IndexOf($blockStart, $legacyCssStart, [StringComparison]::Ordinal)
      $legacyCssLength = if ($existingConfigStart -ge 0) { $existingConfigStart - $legacyCssStart } else { $css.Length - $legacyCssStart }
      $css = $css.Remove($legacyCssStart, $legacyCssLength).TrimEnd()
      $legacyCssRemoved = $true
      $changed = $true
    }
  }
  $cssStartIndex = $css.IndexOf($blockStart, [StringComparison]::Ordinal)
  if ($stableConfigOnly) {
    if ($cssStartIndex -ge 0) {
      Fail 'stable config mode found the newer configurable CSS instead of the known-good fixed gold CSS'
    }
    if ($css.Contains('/* codex-gold-reasoning-patch css */')) {
      $cssResult = 'stable-preserved'
    } else {
      $cssResult = 'runtime-only-clean-base'
    }
  } elseif ($buttonRepairOnly) {
    if ($cssStartIndex -lt 0) {
      Fail 'button repair requires an existing theme CSS block'
    }
    $cssEndIndex = $css.IndexOf($blockEnd, $cssStartIndex, [StringComparison]::Ordinal)
    if ($cssEndIndex -lt 0) {
      Fail 'existing theme CSS block is missing its end marker'
    }
    $cssBlockLength = ($cssEndIndex + $blockEnd.Length) - $cssStartIndex
    $existingCssBlock = $css.Substring($cssStartIndex, $cssBlockLength)
    $overlayPattern = 'html\[data-codex-reasoning(?:-theme|-material)[^\]]*\]\s+body::before\s*\{.*?\}\s*'
    $overlayCount = [regex]::Matches($existingCssBlock, $overlayPattern, [Text.RegularExpressions.RegexOptions]::Singleline).Count
    if ($overlayCount -lt 1) {
      Fail 'button repair could not find the fullscreen theme overlay rules'
    }
    $repairedCssBlock = [regex]::Replace($existingCssBlock, $overlayPattern, '', [Text.RegularExpressions.RegexOptions]::Singleline)
    if ($repairedCssBlock.Contains('body::before')) {
      Fail 'button repair left an unexpected body::before selector behind'
    }
    $css = $css.Remove($cssStartIndex, $cssBlockLength).Insert($cssStartIndex, $repairedCssBlock.Trim())
    Set-Content -LiteralPath $cssTarget -Value $css -NoNewline -Encoding UTF8
    $changed = $true
    $cssResult = "button-overlay-removed($overlayCount)"
  } elseif ($cssStartIndex -ge 0) {
    $cssEndIndex = $css.IndexOf($blockEnd, $cssStartIndex, [StringComparison]::Ordinal)
    if ($cssEndIndex -lt 0) {
      Fail 'existing theme CSS block is missing its end marker'
    }
    $cssBlockLength = ($cssEndIndex + $blockEnd.Length) - $cssStartIndex
    $existingCssBlock = $css.Substring($cssStartIndex, $cssBlockLength).Trim()
    if ($existingCssBlock -eq $themeCss.Trim()) {
      $cssResult = 'already-patched'
    } else {
      $css = $css.Remove($cssStartIndex, $cssBlockLength).Insert($cssStartIndex, $themeCss.Trim())
      Set-Content -LiteralPath $cssTarget -Value $css -NoNewline -Encoding UTF8
      $changed = $true
      $cssResult = 'configured'
    }
  } else {
    if ($legacyCssRemoved) {
      Set-Content -LiteralPath $cssTarget -Value ($css + "`n" + $themeCss.Trim()) -NoNewline -Encoding UTF8
    } else {
      Add-Content -LiteralPath $cssTarget -Value $themeCss -Encoding UTF8
    }
    $changed = $true
    $cssResult = 'configured'
  }

  if (-not $stableConfigOnly) {
    $finalCss = Get-Content -Raw -LiteralPath $cssTarget
    if ($finalCss.Contains('data-codex-gold-reasoning') -or $finalCss.Contains($legacyCssMarker)) {
      Fail 'legacy fixed-gold CSS remained after the safe configurable theme patch'
    }
  }

  Write-Log "gold reasoning JS patch target: $dropdownTarget"
  Write-Log "gold reasoning CSS patch target: $cssTarget"
  Write-Log "gold reasoning preload target: $preloadTarget"
  if ($changed) {
    return "patched (preload=$preloadResult js=$jsResult css=$cssResult)"
  }
  return "already-patched (preload=$preloadResult js=$jsResult css=$cssResult)"
}
'@
$functionInjection = $functionInjection.Replace('__CODEX_THEME_JS_BASE64__', $generatedJsBase64)
$functionInjection = $functionInjection.Replace('__CODEX_STABLE_CONFIG_JS_BASE64__', $generatedStableConfigJsBase64)
$functionInjection = $functionInjection.Replace('__CODEX_STABLE_PRELOAD_JS_BASE64__', $generatedStablePreloadJsBase64)
$functionInjection = $functionInjection.Replace('__CODEX_STABLE_MAIN_JS_BASE64__', $generatedStableMainJsBase64)
$functionInjection = $functionInjection.Replace('__CODEX_THEME_CSS_BASE64__', $generatedCssBase64)
$functionInjection = $functionInjection.Replace('__CODEX_THEME_PRELOAD_BASE64__', $generatedPreloadBase64)
$functionInjection = $functionInjection.Replace('__CODEX_ELECTRON_BRIDGE_PROPERTY_BASE64__', $generatedElectronBridgePropertyBase64)
$functionInjection = $functionInjection.Replace('__CODEX_BUTTON_REPAIR_ONLY__', $(if ($ButtonRepairOnly) { '$true' } else { '$false' }))
$functionInjection = $functionInjection.Replace('__CODEX_STABLE_CONFIG_ONLY__', $(if ($StableConfigOnly) { '$true' } else { '$false' }))

$anchor = 'function Invoke-PatchAppAsar {'
if (-not $source.Contains($anchor)) {
  Fail 'could not find Invoke-PatchAppAsar anchor in base script'
}
$source = $source.Replace($anchor, $functionInjection + "`r`n" + $anchor)

$patchBlockReplacement = @'
  $goldReasoning = Invoke-GoldReasoningPatch $extractDir
  Write-Log "gold reasoning patch result: $goldReasoning"
'@
$patchBlockPattern = '(?s)  \$patchers = Write-PatcherFiles \$WorkDir.*?  Write-Log "computer-use gate patch result: \$computerUse"'
$sourceAfterPatchBlock = [regex]::Replace($source, $patchBlockPattern, $patchBlockReplacement, 1)
if ($sourceAfterPatchBlock -eq $source) {
  Fail 'could not replace base ASAR patch block'
}
$source = $sourceAfterPatchBlock

$conditionPattern = "(?s)  if \(\`$fast -eq 'already-patched'.*?\`$bundledMarketplaceCopy -eq 'already-patched'\) \{"
$conditionReplacement = "  if (`$goldReasoning -like 'already-patched*') {"
$sourceAfterCondition = [regex]::Replace($source, $conditionPattern, $conditionReplacement, 1)
if ($sourceAfterCondition -eq $source) {
  Fail 'could not replace already-patched condition in base script'
}
$source = $sourceAfterCondition

$layoutAnchor = '  Remove-OldPackageArtifacts $workPackageRoot'
if (-not $source.Contains($layoutAnchor)) {
  Fail 'could not find package layout preparation anchor in base script'
}
$source = $source.Replace($layoutAnchor, $layoutAnchor + "`r`n  Set-GoldPatchedPackageVersion `$workPackageRoot")

Set-Content -LiteralPath $patchedScript -Value $source -Encoding UTF8

$forward = @()
if ($DryRun) { $forward += '-DryRun' }
if ($Install) { $forward += '-Install' }
if ($Launch) { $forward += '-Launch' }
if ($InstallPrerequisites) { $forward += '-InstallPrerequisites' }
if ($NoLaunch -or -not $Launch) { $forward += '-NoLaunch' }
if ($KeepWorkDir) { $forward += '-KeepWorkDir' }
if ($ExistingTrustedCertificateOnly) { $forward += '-ExistingTrustedCertificateOnly' }
$forward += '-ForceRebuild'
if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) { $forward += @('-OutputRoot', $OutputRoot) }

Write-Host "[codex-gold-reasoning] generated transient patch script: $patchedScript"
& powershell -NoProfile -ExecutionPolicy Bypass -File $patchedScript @forward
exit $LASTEXITCODE
