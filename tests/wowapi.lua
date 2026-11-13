-- XML loader, Blizzard template mocks, and the WoW API surface used by the addon.
local H = ...

------------------------------------------------------------------------
-- CreateFrame + templates
------------------------------------------------------------------------
H.xmlTemplates = {}      -- virtual templates from XML (name -> element)
H.luaTemplates = {}      -- mocked Blizzard templates (name -> function(frame))
local FRAME_TYPES = { Frame=1, Button=1, CheckButton=1, Slider=1, StatusBar=1, EditBox=1, Cooldown=1, ScrollFrame=1, GameTooltip=1, Model=1 }

local applyElement, instantiate

local function runOnLoad(f)
  local h = f.__scripts.OnLoad
  if h then H.pcallr(h, f) end
end

local function applyTemplate(f, tname)
  tname = strtrim(tname)
  if tname == "" then return end
  local lt = H.luaTemplates[tname]
  if lt then lt(f) return end
  local el = H.xmlTemplates[tname]
  if not el then
    H.report("Unknown template: " .. tname .. " (for " .. tostring(f.__name) .. ")")
    return
  end
  if el.attr and el.attr.inherits then
    for t in el.attr.inherits:gmatch("[^,]+") do applyTemplate(f, t) end
  end
  applyElement(f, el, true)
end
H.applyTemplate = applyTemplate

function CreateFrame(ftype, name, parent, template)
  assert(FRAME_TYPES[ftype], "CreateFrame: unsupported type " .. tostring(ftype))
  if type(parent) == "string" then parent = _G[parent] end
  local f = H.newObject(ftype, name, parent)
  if template then
    for t in template:gmatch("[^,]+") do applyTemplate(f, t) end
  end
  runOnLoad(f)
  return f
end

------------------------------------------------------------------------
-- XML element application
------------------------------------------------------------------------
local HANDLER_PARAMS = {
  OnEvent = "event", OnClick = "button, down", OnUpdate = "elapsed", OnValueChanged = "value",
  OnEnter = "motion", OnLeave = "motion", OnMouseDown = "button", OnMouseUp = "button",
  OnTextChanged = "userInput", OnSizeChanged = "w, h", OnDragStart = "button", OnDragStop = "button",
  OnVerticalScroll = "offset", OnMouseWheel = "delta", OnAttributeChanged = "name, value", OnChar = "text",
  OnKeyDown = "key", OnKeyUp = "key",
}
local compiled = {}
local function compileHandler(hname, body, where)
  local params = HANDLER_PARAMS[hname]
  local src = "return function(self" .. (params and (", " .. params) or "") .. ", ...)\n" .. body .. "\nend"
  local chunk, err = load(src, "=" .. where .. ":" .. hname)
  if not chunk then H.report("XML script compile error " .. where .. " " .. hname .. ": " .. err) return nil end
  return chunk()
end

local function sub(name, parent)
  if not name then return nil end
  return (name:gsub("%$parent", parent and parent.__name or ""))
end
local function child(el, tag)
  for _, c in ipairs(el.children or {}) do if c.tag == tag then return c end end
end
local function dims(el)
  if not el then return end
  local x, y = el.attr and tonumber(el.attr.x), el.attr and tonumber(el.attr.y)
  local abs = child(el, "AbsDimension")
  if abs then x, y = tonumber(abs.attr.x), tonumber(abs.attr.y) end
  return x, y
end
local function globalText(key)
  if type(_G[key]) == "string" then return _G[key] end
  return key
end

local function applyAnchors(o, el, parent)
  for _, a in ipairs(el.children or {}) do
    if a.tag == "Anchor" then
      local point = a.attr.point
      local relName = a.attr.relativeTo and sub(a.attr.relativeTo, parent)
      local rel = parent
      if relName then
        rel = _G[relName]
        if not rel then H.report("XML anchor: unknown relativeTo " .. relName .. " on " .. tostring(o.__name)) rel = parent end
      end
      local x, y = tonumber(a.attr.x) or 0, tonumber(a.attr.y) or 0
      local off = child(a, "Offset")
      if off then local ox, oy = dims(off); x, y = ox or x, oy or y end
      o:SetPoint(point, rel, a.attr.relativePoint or point, x, y)
    end
  end
end

local function makeRegion(f, el, layer)
  H.gen = H.gen + 1
  local name = sub(el.attr and el.attr.name, f)
  local r
  if el.tag == "Texture" then
    r = f:CreateTexture(name, layer)
    if el.attr and el.attr.file then r:SetTexture(el.attr.file) end
  else
    r = f:CreateFontString(name, layer)
    local inh = el.attr and el.attr.inherits
    if inh then
      if _G[inh] and _G[inh].__fontObject then r:SetFontObject(_G[inh]) else H.report("Unknown font template " .. inh) end
    end
    if el.attr and el.attr.text then r:SetText(globalText(el.attr.text)) end
    if el.attr and el.attr.justifyH then r:SetJustifyH(el.attr.justifyH) end
  end
  local a = el.attr or {}
  if a.parentKey then f[a.parentKey] = r end
  if a.hidden == "true" then r.__shown = false end
  local sx, sy = dims(child(el, "Size"))
  if sx and sx > 0 then r.__w = sx end
  if sy and sy > 0 then r.__h = sy end
  if a.setAllPoints == "true" then r:SetAllPoints(f) end
  local anchors = child(el, "Anchors")
  if anchors then applyAnchors(r, anchors, f) end
  return r
end

function applyElement(f, el, isTemplate)
  H.gen = H.gen + 1
  local a = el.attr or {}
  if a.hidden == "true" then f.__shown = false elseif a.hidden == "false" then f.__shown = true end
  if a.id then f.__id = tonumber(a.id) end
  if a.frameLevel then f.__level = tonumber(a.frameLevel) end
  if a.frameStrata then f.__strata = a.frameStrata end
  if a.text and f.SetText then f:SetText(globalText(a.text)) end
  if a.setAllPoints == "true" and f.__parent then f:SetAllPoints(f.__parent) end
  local sx, sy = dims(child(el, "Size"))
  if sx then f.__w = sx end
  if sy then f.__h = sy end
  local anchors = child(el, "Anchors")
  if anchors then applyAnchors(f, anchors, f.__parent) end

  for _, c in ipairs(el.children or {}) do
    if c.tag == "Layers" then
      for _, layer in ipairs(c.children or {}) do
        local lvl = layer.attr and layer.attr.level or "ARTWORK"
        local VALID = { BACKGROUND=1, BORDER=1, ARTWORK=1, OVERLAY=1, HIGHLIGHT=1 }
        if not VALID[lvl] then H.report("Invalid draw layer '" .. lvl .. "' in " .. tostring(f.__name)) end
        for _, r in ipairs(layer.children or {}) do makeRegion(f, r, lvl) end
      end
    elseif c.tag == "Frames" then
      for _, k in ipairs(c.children or {}) do instantiate(k, f) end
    elseif c.tag == "Scripts" then
      for _, s in ipairs(c.children or {}) do
        local fn
        if s.attr and s.attr["function"] then
          fn = _G[s.attr["function"]]
          if not fn then H.report("XML script function not found: " .. s.attr["function"] .. " for " .. tostring(f.__name)) end
        elseif s.text then
          fn = compileHandler(s.tag, s.text, tostring(f.__name or el.attr and el.attr.name))
        end
        if fn then f.__scripts[s.tag] = fn end
      end
    elseif c.tag == "NormalTexture" or c.tag == "PushedTexture" or c.tag == "HighlightTexture" or c.tag == "CheckedTexture"
        or c.tag == "DisabledCheckedTexture" or c.tag == "DisabledTexture" then
      local r = makeRegion(f, { tag = "Texture", attr = c.attr, children = c.children }, "ARTWORK")
      if not (c.children and child(c, "Anchors")) then r:SetAllPoints(f) end
      local kind = c.tag:gsub("Texture$", "")
      f["__tex" .. kind] = r
    elseif c.tag == "ThumbTexture" then
      f.__thumb = makeRegion(f, { tag = "Texture", attr = c.attr, children = c.children }, "ARTWORK")
    elseif c.tag == "ButtonText" then
      local fs = makeRegion(f, { tag = "FontString", attr = c.attr, children = c.children }, "ARTWORK")
      if not fs.__font then fs:SetFontObject(GameFontNormal) end
      f.__fontstring = fs
    elseif c.tag == "NormalFont" then
      if f.__fontstring and c.attr and _G[c.attr.style] then f.__fontstring:SetFontObject(_G[c.attr.style]) end
      f.__normalFont = c.attr and c.attr.style
    elseif c.tag == "FontString" then         -- EditBox font
      f.__font = c.attr and c.attr.inherits
    elseif c.tag == "Backdrop" then
      f.__backdrop = c.attr
    end
  end
  if f.__fontstring and f.__pendingText then f.__fontstring:SetText(f.__pendingText) end
end

function instantiate(el, parent)
  local tag = el.tag
  local a = el.attr or {}
  if not FRAME_TYPES[tag] then H.report("Unsupported XML element " .. tag) return end
  if a.virtual == "true" then
    H.xmlTemplates[a.name] = el
    return
  end
  if a.parent then parent = _G[a.parent] or parent end
  local name = sub(a.name, parent)
  local f = H.newObject(tag, name, parent)
  if a.parentKey and parent then parent[a.parentKey] = f end
  if a.inherits then
    for t in a.inherits:gmatch("[^,]+") do applyTemplate(f, t) end
  end
  applyElement(f, el, false)
  runOnLoad(f)
  return f
end

------------------------------------------------------------------------
-- XML / TOC loading
------------------------------------------------------------------------
H.addonName = "CompactRaidFrame"
H.addonTable = {}
H.skipFiles = {}
function H.loadLua(root, rel)
  rel = rel:gsub("\\", "/")
  if H.skipFiles[rel] then return end
  local chunk, err = loadfile(root .. "/" .. rel)
  if not chunk then H.report("Lua load error " .. rel .. ": " .. err) return end
  H.pcallr(chunk, H.addonName, H.addonTable)
end
function H.loadXML(root, rel, xmlIndex)
  rel = rel:gsub("\\", "/")
  if H.skipFiles[rel] then return end
  local ui = xmlIndex[rel]
  if not ui then H.report("XML not found " .. rel) return end
  local dir = rel:match("^(.*)/") or ""
  for _, el in ipairs(ui.children or {}) do
    local path = el.attr and el.attr.file and ((dir ~= "" and (dir .. "/") or "") .. el.attr.file:gsub("\\", "/"))
    if el.tag == "Script" then
      H.loadLua(root, path)
    elseif el.tag == "Include" then
      H.loadXML(root, path, xmlIndex)
    else
      instantiate(el, UIParent)
    end
  end
end
function H.loadTOC(root, xmlIndex)
  local svars = {}
  for line in io.lines(root .. "/" .. H.addonName .. ".toc") do
    line = strtrim(line)
    if line:match("^## SavedVariables") then
      for v in line:match(":%s*(.*)$"):gmatch("[^,%s]+") do svars[#svars+1] = v end
    elseif line ~= "" and not line:match("^#") then
      if line:match("%.xml$") then H.loadXML(root, line, xmlIndex) else H.loadLua(root, line) end
    end
  end
  return svars
end

------------------------------------------------------------------------
-- Blizzard templates (mocked)
------------------------------------------------------------------------
local LT = H.luaTemplates
local function tex(f, suffix, w, h, layer)
  H.gen = H.gen + 1
  local t = f:CreateTexture(f.__name and (f.__name .. suffix) or nil, layer or "BACKGROUND")
  if w then t.__w = w end
  if h then t.__h = h end
  return t
end
local function fstr(f, suffix, font)
  local s = f:CreateFontString(f.__name and (f.__name .. suffix) or nil, "ARTWORK", font)
  return s
end

LT.UIDropDownMenuTemplate = function(f)
  f.__w, f.__h = 40, 32
  local left = tex(f, "Left", 25, 64); left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 17)
  local mid = tex(f, "Middle", 115, 64); mid:SetPoint("LEFT", left, "RIGHT", 0, 0)
  local right = tex(f, "Right", 25, 64); right:SetPoint("LEFT", mid, "RIGHT", 0, 0)
  local text = fstr(f, "Text", "GameFontHighlightSmall"); text.__h = 10
  text:SetPoint("RIGHT", right, "RIGHT", -43, 2); text:SetJustifyH("RIGHT")
  local btn = H.newObject("Button", f.__name and (f.__name .. "Button"), f); btn.__w, btn.__h = 24, 24
  btn:SetPoint("TOPRIGHT", right, "TOPRIGHT", -16, -18)
  f.__isDropDown = true
end
local function panelButton(f)
  f.__w = f.__w or 80; f.__h = f.__h or 22
  local fs = f:CreateFontString(f.__name and (f.__name .. "Text") or nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("CENTER", f, "CENTER", 0, 1)
  f.__fontstring = fs
end
LT.UIPanelButtonTemplate = panelButton
LT.UIPanelButtonTemplate2 = panelButton
LT.UIPanelButtonGrayTemplate = panelButton
local function checkTemplate(f)
  f.__w, f.__h = 26, 26
  local text = f:CreateFontString(f.__name and (f.__name .. "Text") or nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("LEFT", f, "RIGHT", -2, 0)
  f.__scripts.OnClick = function(self) end
end
LT.UICheckButtonTemplate = checkTemplate
LT.OptionsCheckButtonTemplate = checkTemplate
LT.InterfaceOptionsCheckButtonTemplate = checkTemplate
LT.SecureUnitButtonTemplate = function(f) f.__protected = true end
LT.SecureHandlerStateTemplate = function(f) f.__protected = true end
LT.SecureHandlerClickTemplate = function(f) f.__protected = true end
LT.SecureHandlerBaseTemplate = function(f) f.__protected = true end
LT.SecureFrameTemplate = function(f) f.__protected = true end
LT.CooldownFrameTemplate = function(f) end
-- 3.3.5a OptionsFrameTemplates.xml (structure per the shipped FrameXML)
LT.OptionsFrameTabButtonTemplate = function(f)
  f.__w, f.__h = 115, 24
  local function piece(suffix, w, active)
    local t = tex(f, suffix, w, 24, "BORDER")
    t.__activeArt = active
    return t
  end
  local ld = piece("LeftDisabled", 20, true); ld:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, -3)
  local md = piece("MiddleDisabled", 88, true); md:SetPoint("LEFT", ld, "RIGHT", 0, 0)
  local rd = piece("RightDisabled", 20, true); rd:SetPoint("LEFT", md, "RIGHT", 0, 0)
  local l = piece("Left", 20); l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  local m = piece("Middle", 88); m:SetPoint("LEFT", l, "RIGHT", 0, 0)
  local r = piece("Right", 20); r:SetPoint("LEFT", m, "RIGHT", 0, 0)
  local text = fstr(f, "Text", "GameFontNormalSmall"); text:SetPoint("CENTER", f, "CENTER", 0, -3)
  f.__fontstring = text
  local hl = tex(f, "HighlightTexture", nil, nil, "HIGHLIGHT")
  hl:SetPoint("LEFT", f, "LEFT", 10, -4); hl:SetPoint("RIGHT", f, "RIGHT", -10, -4)
  f.__scripts.OnLoad = function(self) self:SetFrameLevel(self:GetFrameLevel() + 4) end
  f.__scripts.OnShow = function(self)
    PanelTemplates_TabResize(self, 0)
    _G[self:GetName() .. "HighlightTexture"]:SetWidth(self:GetTextWidth() + 30)
  end
end

------------------------------------------------------------------------
-- Blizzard FrameXML functions (mocked)
------------------------------------------------------------------------
UIParent = H.newObject("Frame", "UIParent", nil)
UIParent:SetPoint("TOPLEFT", H.SCREEN, "TOPLEFT", 0, 0)
UIParent:SetPoint("BOTTOMRIGHT", H.SCREEN, "BOTTOMRIGHT", 0, 0)
WorldFrame = H.newObject("Frame", "WorldFrame", nil)

-- InterfaceOptionsFrame with the 3.3.5a geometry: 648x520, panel container
-- = Categories(175x429 at 22,-40) TOPRIGHT+16 .. RIGHT-22 => 413 x 428.
InterfaceOptionsFrame = H.newObject("Frame", "InterfaceOptionsFrame", UIParent)
InterfaceOptionsFrame.__w, InterfaceOptionsFrame.__h = 648, 520
InterfaceOptionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
InterfaceOptionsFrame.__shown = false
InterfaceOptionsFrameCategories = H.newObject("Frame", "InterfaceOptionsFrameCategories", InterfaceOptionsFrame)
InterfaceOptionsFrameCategories.__w, InterfaceOptionsFrameCategories.__h = 175, 429
InterfaceOptionsFrameCategories:SetPoint("TOPLEFT", InterfaceOptionsFrame, "TOPLEFT", 22, -40)
InterfaceOptionsFramePanelContainer = H.newObject("Frame", "InterfaceOptionsFramePanelContainer", InterfaceOptionsFrame)
InterfaceOptionsFramePanelContainer:SetPoint("TOPLEFT", InterfaceOptionsFrameCategories, "TOPRIGHT", 16, 0)
InterfaceOptionsFramePanelContainer:SetPoint("BOTTOMLEFT", InterfaceOptionsFrameCategories, "BOTTOMRIGHT", 16, 1)
InterfaceOptionsFramePanelContainer:SetPoint("RIGHT", InterfaceOptionsFrame, "RIGHT", -22, 0)

INTERFACEOPTIONS_ADDONCATEGORIES = {}
function InterfaceOptions_AddCategory(panel) table.insert(INTERFACEOPTIONS_ADDONCATEGORIES, panel) end
function InterfaceOptionsFrame_OpenToCategory(panel)
  if type(panel) == "string" then for _, p in ipairs(INTERFACEOPTIONS_ADDONCATEGORIES) do if p.name == panel then panel = p end end end
  InterfaceOptionsFrame:Show()
  for _, p in ipairs(INTERFACEOPTIONS_ADDONCATEGORIES) do if p ~= panel and p:IsShown() then p:Hide() end end
  panel:SetParent(InterfaceOptionsFramePanelContainer)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", InterfaceOptionsFramePanelContainer, "TOPLEFT")
  panel:SetPoint("BOTTOMRIGHT", InterfaceOptionsFramePanelContainer, "BOTTOMRIGHT")
  if panel.refresh then H.pcallr(panel.refresh, panel) end
  panel:Show()
end

function BlizzardOptionsPanel_OnLoad(frame, okay, cancel, default, refresh)
  frame.okay, frame.cancel, frame.default, frame.refresh = okay, cancel, default, refresh
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:SetScript("OnEvent", BlizzardOptionsPanel_OnEvent)
end
function BlizzardOptionsPanel_OnEvent(frame, event) if event == "PLAYER_ENTERING_WORLD" then frame:UnregisterEvent(event) end end
function BlizzardOptionsPanel_RegisterControl(control, parent) parent.controls = parent.controls or {}; table.insert(parent.controls, control) end
CONTROLTYPE_CHECKBOX = 1

-- UIDropDownMenu (3.3.5a semantics: init function gets the frame; Refresh sets
-- the text from the currently populated list)
UIDROPDOWNMENU_MAXBUTTONS = 32
UIDROPDOWNMENU_MENU_LEVEL = 1
DropDownList1 = H.newObject("Frame", "DropDownList1", UIParent)
DropDownList1.__shown = false
DropDownList1.buttons = {}
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_Initialize(frame, initFunction, displayMode, level, menuList)
  assert(frame and frame:GetName(), "Attempted to initialize a dropdown without a name")
  frame.initialize = initFunction
  frame.displayMode = displayMode
  UIDROPDOWNMENU_INIT_MENU = frame
  DropDownList1.dropdown = frame
  DropDownList1.buttons = {}
  if initFunction then initFunction(frame, level or 1, menuList) end
end
function UIDropDownMenu_AddButton(info)
  local b = {}
  for k, v in pairs(info) do b[k] = v end
  table.insert(DropDownList1.buttons, b)
  assert(#DropDownList1.buttons <= UIDROPDOWNMENU_MAXBUTTONS, "too many dropdown buttons")
end
function UIDropDownMenu_SetWidth(frame, width, padding)
  _G[frame:GetName() .. "Middle"]:SetWidth(width)
  frame:SetWidth(width + (padding or 50))
  _G[frame:GetName() .. "Text"]:SetWidth(width - 25)
  frame.noResize = 1
end
function UIDropDownMenu_SetText(frame, text) _G[frame:GetName() .. "Text"]:SetText(text) end
function UIDropDownMenu_GetText(frame) return _G[frame:GetName() .. "Text"]:GetText() end
function UIDropDownMenu_SetSelectedValue(frame, value)
  frame.selectedValue = value
  if DropDownList1.dropdown == frame then
    for _, b in ipairs(DropDownList1.buttons) do
      if value ~= nil and b.value == value then UIDropDownMenu_SetText(frame, b.text) end
    end
  end
end
function UIDropDownMenu_GetSelectedValue(frame) return frame.selectedValue end
-- as 3.3.5a: label and text greyed, the arrow button disabled
function UIDropDownMenu_EnableDropDown(frame)
  frame.__ddDisabled = nil; frame.isDisabled = nil
  local n = frame:GetName()
  if _G[n .. "Label"] then _G[n .. "Label"].__disabled = nil end
  _G[n .. "Text"].__disabled = nil
  _G[n .. "Button"]:Enable()
end
function UIDropDownMenu_DisableDropDown(frame)
  frame.__ddDisabled = true; frame.isDisabled = 1
  local n = frame:GetName()
  if _G[n .. "Label"] then _G[n .. "Label"].__disabled = true end
  _G[n .. "Text"].__disabled = true
  _G[n .. "Button"]:Disable()
end
function UIDropDownMenu_Refresh() end
function ToggleDropDownMenu(level, value, frame)
  UIDropDownMenu_Initialize(frame, frame.initialize, frame.displayMode, level)
  DropDownList1.__shown = true
end
function CloseDropDownMenus() DropDownList1.__shown = false end
-- simulate picking an entry by its value from an open dropdown
function H.pickDropDown(frame, value)
  assert(not frame.__ddDisabled, "dropdown is disabled: " .. tostring(frame:GetName()))
  ToggleDropDownMenu(1, nil, frame)
  for _, b in ipairs(DropDownList1.buttons) do
    if b.value == value then
      assert(not b.disabled, "dropdown entry is disabled: " .. tostring(value))
      local btn = { value = b.value, arg1 = b.arg1, arg2 = b.arg2 }
      H.pcallr(b.func, btn, b.arg1, b.arg2)
      CloseDropDownMenus()
      return true
    end
  end
  error("dropdown has no entry " .. tostring(value))
end

-- PanelTemplates (UIPanelTemplates.lua, unchanged since 1.x)
function PanelTemplates_SetNumTabs(frame, n) frame.numTabs = n end
function PanelTemplates_SetTab(frame, id) frame.selectedTab = id; PanelTemplates_UpdateTabs(frame) end
function PanelTemplates_GetSelectedTab(frame) return frame.selectedTab end
function PanelTemplates_Tab_OnClick(self, frame) PanelTemplates_SetTab(frame, self:GetID()) end
function PanelTemplates_UpdateTabs(frame)
  if frame.selectedTab then
    for i = 1, frame.numTabs do
      local tab = _G[frame:GetName() .. "Tab" .. i]
      if i == frame.selectedTab then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
    end
  end
end
function PanelTemplates_SelectTab(tab)
  local name = tab:GetName()
  _G[name .. "Left"]:Hide(); _G[name .. "Middle"]:Hide(); _G[name .. "Right"]:Hide()
  tab:Disable()
  _G[name .. "LeftDisabled"]:Show(); _G[name .. "MiddleDisabled"]:Show(); _G[name .. "RightDisabled"]:Show()
end
function PanelTemplates_DeselectTab(tab)
  local name = tab:GetName()
  _G[name .. "Left"]:Show(); _G[name .. "Middle"]:Show(); _G[name .. "Right"]:Show()
  tab:Enable()
  _G[name .. "LeftDisabled"]:Hide(); _G[name .. "MiddleDisabled"]:Hide(); _G[name .. "RightDisabled"]:Hide()
end
function PanelTemplates_TabResize(tab, padding)
  local name = tab:GetName()
  local sideWidths = 2 * _G[name .. "Left"]:GetWidth()
  local width = _G[name .. "Text"]:GetStringWidth() + (padding or 24)
  _G[name .. "Middle"]:SetWidth(width)
  _G[name .. "MiddleDisabled"]:SetWidth(width)
  tab:SetWidth(width + sideWidths)
end

-- Unit popup
UnitPopupMenus = { SELF = { "SET_FOCUS", "CANCEL" }, RAID_PLAYER = { "WHISPER", "SET_FOCUS", "CANCEL" }, PARTY = { "SET_FOCUS" }, PLAYER = { "SET_FOCUS" }, TARGET = { "SET_FOCUS" }, PET = {}, VEHICLE = {} }
UnitPopupShown = { {}, {}, {} }
function UnitPopup_HideButtons()
  local dropdownMenu = UIDROPDOWNMENU_INIT_MENU
  for i, v in ipairs(UnitPopupMenus[dropdownMenu.which] or {}) do UnitPopupShown[1][i] = 1 end
end
function UnitPopup_ShowMenu(dropdownMenu, which, unit, name, userData)
  dropdownMenu.which, dropdownMenu.unit, dropdownMenu.userData = which, unit, userData
  UIDROPDOWNMENU_INIT_MENU = dropdownMenu
  UnitPopup_HideButtons()
end

function hooksecurefunc(tbl, name, func)
  if type(tbl) == "string" then tbl, name, func = _G, tbl, name end
  local orig = tbl[name]
  assert(type(orig) == "function", "hooksecurefunc: no function " .. tostring(name))
  tbl[name] = function(...) local r = { orig(...) } func(...) return unpack(r) end
end

H.visibilityDriven = {}
function H.applyVisibilityDriver(frame)
  local values = frame.__stateDrivers and frame.__stateDrivers.visibility
  if not values then return end
  local v = H.evalMacroCondition(values)
  -- secure code: no protection check, and Show/Hide scripts fire as in game
  local was = frame:IsVisible()
  if v == "show" then frame.__shown = true elseif v == "hide" then frame.__shown = false end
  local now = frame:IsVisible()
  if was and not now then
    local h = frame.__scripts and frame.__scripts.OnHide if h then H.pcallr(h, frame) end
    for _, c in ipairs(frame.__children or {}) do if c.__shown then H.fireHide(c) end end
  elseif now and not was then
    H.fireShow(frame)
  end
end
function H.applyVisibilityDrivers()
  for frame in pairs(H.visibilityDriven) do H.applyVisibilityDriver(frame) end
end
function RegisterStateDriver(frame, state, values)
  H.checkProtected(frame, "RegisterStateDriver")
  frame.__stateDrivers = frame.__stateDrivers or {}
  frame.__stateDrivers[state] = values
  if state == "visibility" then
    H.visibilityDriven[frame] = true
    H.applyVisibilityDriver(frame)
  end
end
function UnregisterStateDriver(frame, state)
  H.checkProtected(frame, "UnregisterStateDriver")
  if frame.__stateDrivers then frame.__stateDrivers[state] = nil end
  if state == "visibility" then H.visibilityDriven[frame] = nil end
end
function H.evalMacroCondition(s)
  for clause in (s .. ";"):gmatch("([^;]*);") do
    local conds, value = clause:match("^(.-)([%a]+)$")
    if conds == "" then return value end
    for c in conds:gmatch("%[(.-)%]") do
      local unit = c:match("target=([%w]+)")
      if unit and c:find("exists") and UnitExists(unit) then return value end
    end
  end
end
function RegisterUnitWatch(f) H.checkProtected(f, "RegisterUnitWatch") end
function UnregisterUnitWatch(f) end
function SecureUnitButton_OnLoad(self, unit, menufunc) self:SetAttribute("unit", unit) end
function UnitFrame_Initialize(self, unit) self.unit = unit end
function UnitFrame_OnEnter() end
function UnitFrame_OnLeave() end
function PartyMemberFrame_OnLoad(self) self:RegisterEvent("PARTY_MEMBERS_CHANGED") end
function CooldownFrame_SetTimer(cd, start, duration, enable) cd:Show() end
function CastingBarFrame_SetUnit() end

for i = 1, 4 do
  local f = H.newObject("Button", "PartyMemberFrame" .. i, UIParent)
  f.__protected = true
  f.unit = "party" .. i
  f.healthbar = H.newObject("StatusBar", nil, f)
  f.manabar = H.newObject("StatusBar", nil, f)
  f:SetID(i)
  local pet = H.newObject("Button", "PartyMemberFrame" .. i .. "PetFrame", f)
  pet.healthbar = H.newObject("StatusBar", nil, pet)
  pet.unit = "partypet" .. i
end
PartyMemberFrame1:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -160)
PlayerFrame = H.newObject("Button", "PlayerFrame", UIParent)
PlayerFrame.__protected = true
PlayerFrame:SetSize(232, 100)
PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -19, -4)
PetFrame = H.newObject("Button", "PetFrame", PlayerFrame)
PetFrame.__protected = true
TotemFrame = H.newObject("Frame", "TotemFrame", PlayerFrame)
TotemFrame:SetSize(128, 53)
TotemFrame:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", 99, 38)
RuneFrame = H.newObject("Frame", "RuneFrame", PlayerFrame)    -- shown for Death Knights only
RuneFrame:SetSize(130, 18)
RuneFrame:SetPoint("TOP", PlayerFrame, "BOTTOM", 54, 34)
PartyMemberBackground = H.newObject("Frame", "PartyMemberBackground", UIParent)

GameTooltip = H.newObject("GameTooltip", "GameTooltip", UIParent)
GameTooltip.__shown = false
function GameTooltip:SetOwner(o) self.__owner = o end
function GameTooltip:GetOwner() return self.__owner end
function GameTooltip:IsOwned(o) return self.__owner == o end
function GameTooltip:SetText(t) self.__tttext = t end
function GameTooltip:AddLine(t) end
function GameTooltip:SetUnitBuff() end
function GameTooltip:SetTotem(slot) self.__totem = slot end
function GameTooltip:SetUnitDebuff() end
function GameTooltip_Hide() GameTooltip:Hide() end

DEFAULT_CHAT_FRAME = { messages = {} }
function DEFAULT_CHAT_FRAME:AddMessage(m) table.insert(self.messages, m) end

H.sounds = {}
function PlaySound(name) table.insert(H.sounds, name) end
function PlaySoundFile(path) table.insert(H.sounds, path) ; H.report("PlaySoundFile used: " .. tostring(path)) end

------------------------------------------------------------------------
-- Game state + unit API
------------------------------------------------------------------------
H.state = { raid = {}, party = {}, player = { name = "Kami", class = "PALADIN", guid = "0x01" }, instance = { "Dalaran", "none", 1, "", 0, 0, false } }
local S = H.state
function H.setParty(names)    -- list of {name, class, lfgRole}
  S.raid = {}; S.party = {}
  for i, m in ipairs(names) do S.party[i] = { name = m[1], class = m[2] or "WARRIOR", lfgRole = m[3], guid = "0x10" .. i } end
end
function H.setRaid(members)   -- list of {name, class, subgroup, role}
  S.party = {}; S.raid = {}
  for i, m in ipairs(members) do S.raid[i] = { name = m[1], class = m[2] or "WARRIOR", subgroup = m[3] or 1, role = m[4], guid = "0x20" .. i } end
end
-- pets: owner.pet = { name =, class = } ("pet", "partypetN", "raidpetN")
local function unitInfo(unit)
  if not unit then return nil end
  if unit == "player" then return S.player end
  if unit == "pet" then return S.player.pet end
  local n = unit:match("^raid(%d+)$")
  if n then return S.raid[tonumber(n)] end
  n = unit:match("^party(%d+)$")
  if n then return S.party[tonumber(n)] end
  n = unit:match("^raidpet(%d+)$")
  if n then local o = S.raid[tonumber(n)] return o and o.pet end
  n = unit:match("^partypet(%d+)$")
  if n then local o = S.party[tonumber(n)] return o and o.pet end
  return nil
end
H.unitInfo = unitInfo
function GetNumRaidMembers() return #S.raid end
function GetNumPartyMembers() return #S.party end
function GetRealNumRaidMembers() return #S.raid end
function UnitExists(u) return unitInfo(u) and 1 or nil end
function UnitName(u) local i = unitInfo(u) return i and i.name end
function GetUnitName(u) return UnitName(u) end
function UnitGUID(u) local i = unitInfo(u) return i and i.guid end
function UnitClass(u) local i = unitInfo(u) if i then return i.class, i.class end end
function UnitIsUnit(a, b)
  local ia, ib = unitInfo(a), unitInfo(b)
  return (ia and ia == ib) and 1 or nil
end
function UnitInRaid(u)       -- 0-based, as on 3.3.5a
  local i = unitInfo(u)
  for idx, m in ipairs(S.raid) do if m == i then return idx - 1 end end
  if u == "player" and #S.raid > 0 then return 0 end
end
function UnitInParty(u) return unitInfo(u) and 1 or nil end
function GetRaidRosterInfo(i)
  local m = S.raid[i]
  if not m then return nil end
  return m.name, (i == 1) and 2 or 0, m.subgroup, 80, m.class, m.class, "Dalaran", 1, nil, m.role, nil
end
-- per-unit overrides: info.offline, info.dead, info.power, info.maxPower, info.powerType ({id, token})
function UnitIsConnected(u) local i = unitInfo(u) return (i and not i.offline) and 1 or nil end
function UnitIsDeadOrGhost(u) local i = unitInfo(u) return (i and i.dead) and 1 or nil end
function UnitHealth(u) local i = unitInfo(u) return (i and not i.dead) and 10000 or 0 end
function UnitHealthMax(u) return UnitExists(u) and 10000 or 0 end
function UnitPower(u) local i = unitInfo(u) if not i then return 0 end return i.power or 5000 end
function UnitPowerMax(u) local i = unitInfo(u) if not i then return 0 end return i.maxPower or 10000 end
function UnitPowerType(u) local i = unitInfo(u) local t = i and i.powerType if t then return t[1], t[2] end return 0, "MANA" end
-- per-unit auras: info.buffs / info.debuffs = { { spellId =, caster =, count =, type =, dispellable = }, ... }
local function auraList(u, key, filter)
  local i = unitInfo(u)
  local list = i and i[key]
  if not list then return nil end
  if filter == "RAID" then
    local f = {}
    for _, a in ipairs(list) do if a.dispellable then f[#f + 1] = a end end
    list = f
  end
  return list
end
local function auraReturns(a)
  if not a then return nil end
  return GetSpellInfo(a.spellId), "", "Interface\\Icons\\Spell" .. a.spellId, a.count or 0, a.type,
    a.duration or 0, a.expires or 0, a.caster or "player", nil, nil, a.spellId
end
function UnitBuff(u, index, filter) local l = auraList(u, "buffs", filter) return auraReturns(l and l[index]) end
function UnitDebuff(u, index, filter) local l = auraList(u, "debuffs", filter) return auraReturns(l and l[index]) end
function UnitThreatSituation() return 0 end
function UnitDetailedThreatSituation() return nil end
function GetThreatStatusColor() return 1, 0, 0 end
function UnitSelectionColor() return 0, 1, 0 end
function UnitIsFriend() return 1 end
function UnitIsPlayer(u) return UnitExists(u) end
function UnitIsEnemy() return nil end
function UnitPlayerControlled() return 1 end
function UnitIsTapped() return nil end
function UnitInVehicle() return nil end
function UnitHasVehicleUI() return nil end
function UnitCreatureFamily() return nil end
function UnitGroupRolesAssigned(u)      -- 3.3.5a: three booleans (LFG roles)
  local i = unitInfo(u)
  local r = i and i.lfgRole
  return r == "TANK", r == "HEALER", r == "DAMAGER"
end
-- totems: H.state.totems[slot] = { name =, start =, duration =, icon = } (1 fire, 2 earth, 3 water, 4 air)
-- runes: H.state.runes[id] = { start =, duration = } while recharging; H.state.runeTypes[id] (1 blood, 2 unholy, 3 frost, 4 death)
FIRE_TOTEM_SLOT, EARTH_TOTEM_SLOT, WATER_TOTEM_SLOT, AIR_TOTEM_SLOT, MAX_TOTEMS = 1, 2, 3, 4, 4
H.destroyedTotems = {}
function GetTotemInfo(slot)
  local t = (S.totems or {})[slot]
  if not t then return nil, "", 0, 0, "" end
  return 1, t.name, t.start, t.duration, t.icon
end
function DestroyTotem(slot)
  table.insert(H.destroyedTotems, slot)
  if S.totems then S.totems[slot] = nil end
end
local DEFAULT_RUNE_TYPES = { 1, 1, 2, 2, 3, 3 }
function GetRuneType(id) return (S.runeTypes or {})[id] or DEFAULT_RUNE_TYPES[id] end
function GetRuneCooldown(id)
  local r = (S.runes or {})[id]
  if r and H.now < r.start + r.duration then return r.start, r.duration, false end
  return 0, 10, true
end
COMBAT_TEXT_RUNE_BLOOD, COMBAT_TEXT_RUNE_UNHOLY, COMBAT_TEXT_RUNE_FROST, COMBAT_TEXT_RUNE_DEATH = "Blood Rune", "Unholy Rune", "Frost Rune", "Death Rune"
function UnitAffectingCombat() return H.inCombat and 1 or nil end
function InCombatLockdown() return H.inCombat and 1 or nil end
function IsRaidLeader() return #S.raid > 0 and 1 or nil end
function IsPartyLeader() return 1 end
function IsRaidOfficer() return 1 end
function UnitIsRaidOfficer() return nil end
function GetPartyLeaderIndex() return 0 end
function IsItemInRange() return 1 end
function CheckInteractDistance() return 1 end
function GetPlayerMapPosition() return 0, 0 end
function GetInstanceInfo() return unpack(S.instance) end
function IsInInstance() return S.instance[2] ~= "none", S.instance[2] end
function GetMapInfo() return "Dalaran" end
function GetRaidTargetIndex() return nil end
function SetRaidTarget() end
function GetReadyCheckStatus() return nil end
function GetReadyCheckTimeLeft() return 0 end
function HasLFGRestrictions() return nil end
function GetSpellInfo(id) return "Spell" .. tostring(id), "", "Interface\\Icons\\X" end
function GetItemInfo() return nil end
function GetLocale() return H.locale or "enUS" end
function GetTime() return H.now end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function GetCursorPosition() return H.cursorX or 0, H.cursorY or 0 end
function GetBattlefieldInstanceRunTime() return 0 end
function GetBuildInfo() return "3.3.5", "12340", "Jun 24 2010", 30300 end
function PromoteToAssistant() end
function DemoteAssistant() end
function ConvertToRaid() end
function DoReadyCheck() end
function UnitIsPartyLeader() return nil end
function GetCVar() return "0" end
function GetCVarBool() return nil end
function SetCVar() end

-- Blizzard globals the addon reads
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
PowerBarColor = { MANA = { r = 0, g = 0, b = 1 } }
DebuffTypeColor = { none = { r = 0.8, g = 0, b = 0 } }
READY_CHECK_READY_TEXTURE, READY_CHECK_NOT_READY_TEXTURE, READY_CHECK_WAITING_TEXTURE = "r", "n", "w"
RED_FONT_COLOR = { r = 1, g = 0.1, b = 0.1 }
for k, v in pairs({
  SAVE = "Save", DELETE = "Delete", CANCEL = "Cancel", DEFAULTS = "Defaults", PRIMARY = "Primary", CREATE = "Create",
  SHOW_DEBUFFS = "Show Debuffs", NONE = "None", GROUP = "Group", ROLE = "Role", AUCTION_TIME_LEFT1 = "Short",
  CALENDAR_TYPE_PVP = "PvP", ERR_NOT_IN_COMBAT = "You can't do that while in combat", CANNOT_COOPERATE_LABEL = "*",
  LOW = "Low", HIGH = "High", HIDE = "Hide", LOCK = "Lock", PARTY = "Party", CONVERT_TO_RAID = "Convert to Raid",
  READY_CHECK = "Ready Check", PLAYER_OFFLINE = "Offline", DEAD = "Dead", RAID_TARGET_ICON = "Raid Target Icon",
  PARTY_IN_PUBLIC_GROUP_MESSAGE = "x", PARTY_PHASED_MESSAGE = "y",
}) do _G[k] = v end
MAX_RAID_MEMBERS = 40
MAX_PARTY_MEMBERS = 4
MEMBERS_PER_RAID_GROUP = 5

return H
