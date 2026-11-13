-- Minimal mock of the WoW 3.3.5a UI runtime (Lua 5.1 flavour on texlua 5.3),
-- enough to load CompactRaidFrame end to end, drive events, and lay out frames.
local H = {}            -- harness API (returned)
H.errors = {}
H.blocked = {}          -- protected calls made during combat lockdown
H.missingMethods = {}
H.inCombat = false
H.now = 1000
H.gen = 0

------------------------------------------------------------------------
-- Lua 5.1 / WoW global helpers
------------------------------------------------------------------------
unpack = table.unpack
loadstring = load
tinsert, tremove, tconcat, sort = table.insert, table.remove, table.concat, table.sort
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
strsub, strupper, strlower, strlen, strfind, strmatch, strrep, strbyte, strchar, gsub, format =
  string.sub, string.upper, string.lower, string.len, string.find, string.match, string.rep, string.byte, string.char, string.gsub, string.format
gmatch = string.gmatch
string.gfind = string.gmatch
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s, n)
  local out, pos = {}, 1
  while true do
    local a, b = string.find(s, sep, pos, true)
    if not a then out[#out+1] = s:sub(pos) break end
    out[#out+1] = s:sub(pos, a - 1); pos = b + 1
  end
  return unpack(out)
end
floor, ceil, abs, max, min, sqrt = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt
mod = math.fmod
math.mod = math.fmod
bit = { bor = bit32.bor, band = bit32.band, bxor = bit32.bxor, lshift = bit32.lshift, rshift = bit32.rshift, bnot = bit32.bnot }
getn = function(t) return #t end
table.getn = getn
date, time = os.date, os.time
debugstack = function() return debug.traceback() end
function geterrorhandler() return function(err) H.errors[#H.errors+1] = tostring(err) end end
seterrorhandler = function() end
securecall = function(f, ...) if type(f) == "string" then f = _G[f] end return f(...) end
issecure = function() return false end
issecurevariable = function() return false end

-- 5.3 string.format is stricter than 5.1 for %d with floats; mimic 5.1 truncation
do
  local realformat = string.format
  local function fix(fmt, ...)
    local args = { ... }
    local i = 0
    for spec in fmt:gmatch("%%[%-%+ #0]*%d*%.?%d*([%a%%])") do
      if spec ~= "%" then
        i = i + 1
        if (spec == "d" or spec == "i") and type(args[i]) == "number" then
          args[i] = math.floor(args[i] + 0) // 1
          args[i] = math.tointeger(args[i]) or args[i]
        end
      end
    end
    return realformat(fmt, unpack(args, 1, select("#", ...)))
  end
  string.format = fix
  format = fix
end

------------------------------------------------------------------------
-- Error capture
------------------------------------------------------------------------
local function report(err)
  H.errors[#H.errors+1] = tostring(err)
end
H.report = report
local function pcallr(f, ...)
  local ok, err = xpcall(f, debug.traceback, ...)
  if not ok then report(err) end
  return ok, err
end
H.pcallr = pcallr

------------------------------------------------------------------------
-- Fonts (for text-width estimates)
------------------------------------------------------------------------
local FONT_SIZES = {
  GameFontNormalLarge = 16, GameFontHighlightLarge = 16,
  GameFontNormal = 12, GameFontHighlight = 12, GameFontDisable = 12,
  GameFontNormalLeft = 12, GameFontHighlightLeft = 12, GameFontDisableLeft = 12, GameFontNormalLeftRed = 12,
  GameFontNormalSmall = 10, GameFontHighlightSmall = 10, GameFontDisableSmall = 10, GameFontRedSmall = 10,
  GameFontNormalMed3 = 13, NumberFontNormalSmall = 10, ChatFontNormal = 14, SystemFont_Shadow_Small = 10,
}
H.FONT_SIZES = FONT_SIZES
for name, size in pairs(FONT_SIZES) do
  _G[name] = { __fontObject = name, size = size, GetFont = function() return "Fonts\\FRIZQT__.TTF", size, "" end }
end

-- rough FRIZQT__ advance widths (em fractions)
local function charWidth(c)
  if c == " " then return 0.28 end
  if c:match("[ilI.,:;'!|]") then return 0.28 end
  if c:match("[mwMW]") then return 0.85 end
  if c:match("%u") then return 0.66 end
  if c:match("%d") then return 0.56 end
  if c:byte() and c:byte() >= 0xE0 then return 1.0 end    -- lead byte of a 3-byte char (CJK, Hangul)
  if c:byte() and c:byte() >= 0xC0 then return 0.6 end    -- lead byte of a 2-byte char (Cyrillic, accents)
  if c:byte() and c:byte() >= 0x80 then return 0 end      -- continuation byte
  return 0.53
end
local function textWidth(text, size)
  text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local w = 0
  for i = 1, #text do w = w + charWidth(text:sub(i, i)) end
  return w * size
end
H.textWidth = textWidth

------------------------------------------------------------------------
-- Object model
------------------------------------------------------------------------
local allObjects = {}
H.allObjects = allObjects
local eventRegistry = {}   -- event -> ordered list of frames
local eventOrder = {}

local Methods = {}         -- objectType -> method table
local function methodsFor(t) Methods[t] = Methods[t] or {}; return Methods[t] end

local function newObject(otype, name, parent)
  H.gen = H.gen + 1
  local o = { __type = otype, __name = name, __parent = parent, __shown = true, __points = {}, __scripts = {},
              __attrs = {}, __children = {}, __regions = {}, __alpha = 1, __level = 0 }
  if parent then
    if otype == "Texture" or otype == "FontString" then
      parent.__regions[#parent.__regions+1] = o
    else
      parent.__children[#parent.__children+1] = o
      o.__level = (parent.__level or 0) + 1
    end
  end
  setmetatable(o, { __index = function(t, k)
      local m = Methods[otype] and Methods[otype][k]
      if m then return m end
      for _, base in ipairs(H.INHERIT[otype] or {}) do
        m = Methods[base] and Methods[base][k]
        if m then return m end
      end
      return nil
    end })
  if name then _G[name] = o end
  allObjects[#allObjects+1] = o
  return o
end
H.newObject = newObject

H.INHERIT = {
  Frame = { "Region" }, Button = { "Frame", "Region" }, CheckButton = { "Button", "Frame", "Region" },
  Slider = { "Frame", "Region" }, StatusBar = { "Frame", "Region" }, EditBox = { "Frame", "Region" },
  Cooldown = { "Frame", "Region" }, ScrollFrame = { "Frame", "Region" }, GameTooltip = { "Frame", "Region" },
  Texture = { "Region" }, FontString = { "Region" }, Model = { "Frame", "Region" },
}

-- protection: explicit (secure templates) or implicit (parent of / anchor target of a protected frame)
local function isProtected(o, seen)
  seen = seen or {}
  if seen[o] then return false end
  seen[o] = true
  if o.__protected then return true end
  for _, c in ipairs(o.__children or {}) do if isProtected(c, seen) then return true end end
  for f in pairs(o.__anchoredBy or {}) do if isProtected(f, seen) then return true end end
  return false
end
H.isProtected = isProtected
local function checkProtected(o, what)
  if H.inCombat and o.__type ~= "Texture" and o.__type ~= "FontString" and isProtected(o) then
    H.blocked[#H.blocked+1] = (o.__name or tostring(o)) .. ":" .. what .. "\n" .. debug.traceback("", 3)
  end
end
H.checkProtected = checkProtected

-- Region (common to frames, textures, fontstrings)
local R = methodsFor("Region")
function R:GetName() return self.__name end
function R:GetParent() return self.__parent end
function R:GetObjectType() return self.__type end
function R:IsObjectType(t) if self.__type == t then return true end for _, b in ipairs(H.INHERIT[self.__type] or {}) do if b == t then return true end end return false end
function R:Show() checkProtected(self, "Show"); local was = self:IsVisible(); self.__shown = true; if not was and self:IsVisible() then H.fireShow(self) end end
function R:Hide() checkProtected(self, "Hide"); local was = self:IsVisible(); self.__shown = false; if was then H.fireHide(self) end end
function R:IsShown() return self.__shown and 1 or nil end
function R:IsVisible()
  local o = self
  while o do if not o.__shown then return nil end o = o.__parent end
  return 1
end
function R:SetAlpha(a) self.__alpha = a end
function R:GetAlpha() return self.__alpha or 1 end
local VALID_POINTS = { TOPLEFT=1, TOP=1, TOPRIGHT=1, LEFT=1, CENTER=1, RIGHT=1, BOTTOMLEFT=1, BOTTOM=1, BOTTOMRIGHT=1 }
function R:SetPoint(point, rel, relPoint, x, y)
  H.gen = H.gen + 1
  checkProtected(self, "SetPoint")
  assert(VALID_POINTS[point], "bad point " .. tostring(point))
  local nargs = select("#", rel, relPoint, x, y)
  if type(rel) == "number" then           -- SetPoint(point, x, y)
    rel, relPoint, x, y = nil, nil, rel, relPoint
    rel = self.__parent
  elseif rel == nil and relPoint == nil and x == nil then
    rel = self.__parent
  elseif type(rel) == "string" then
    local name = rel
    rel = _G[name]
    assert(rel, "SetPoint: unknown relative frame " .. name)
  elseif rel == nil then
    rel = H.SCREEN
  end
  relPoint = relPoint or point
  if type(relPoint) == "number" then error("SetPoint: bad relPoint") end
  self.__points[point] = { rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
  if rel and rel ~= H.SCREEN then rel.__anchoredBy = rel.__anchoredBy or {}; rel.__anchoredBy[self] = true end
end
function R:ClearAllPoints()
  -- like the client, keep reporting the last laid-out rect until new points are set
  local l, r = H.hspan(self)
  local b, t = H.vspan(self)
  if l and b then self.__lastRect = { l, r, b, t } end
  H.gen = H.gen + 1; checkProtected(self, "ClearAllPoints"); self.__points = {}
end
function R:SetAllPoints(rel)
  rel = rel or self.__parent
  if type(rel) == "string" then rel = _G[rel] end
  self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
  self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end
function R:GetNumPoints() local n = 0 for _ in pairs(self.__points) do n = n + 1 end return n end
function R:GetPoint(i)
  local n = 0
  for _, p in ipairs({ "TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT" }) do
    local a = self.__points[p]
    if a then n = n + 1 if n == (i or 1) then return p, a.rel, a.relPoint, a.x, a.y end end
  end
end
function R:SetWidth(w) H.gen = H.gen + 1; checkProtected(self, "SetWidth"); self.__w = w end
function R:SetHeight(h) H.gen = H.gen + 1; checkProtected(self, "SetHeight"); self.__h = h end
function R:SetSize(w, h) self:SetWidth(w); self:SetHeight(h) end
function R:GetWidth() local l, r = H.hspan(self) return (l and r) and (r - l) or (self.__w or 0) end
function R:GetHeight() local b, t = H.vspan(self) return (b and t) and (t - b) or (self.__h or 0) end
function R:GetSize() return self:GetWidth(), self:GetHeight() end
function R:GetLeft() return (H.hspan(self)) end
function R:GetRight() return select(2, H.hspan(self)) end
function R:GetBottom() return (H.vspan(self)) end
function R:GetTop() return select(2, H.vspan(self)) end
function R:GetCenter() local l, r = H.hspan(self) local b, t = H.vspan(self) if l and b then return (l + r) / 2, (b + t) / 2 end end
function R:GetRect() local l, r = H.hspan(self) local b, t = H.vspan(self) if l and b then return l, b, r - l, t - b end end
function R:SetDrawLayer(l) self.__layer = l end
function R:GetDrawLayer() return self.__layer end
function R:SetVertexColor(...) self.__vertex = { ... } end
function R:SetParent(p)
  checkProtected(self, "SetParent")
  if type(p) == "string" then p = _G[p] end
  local old = self.__parent
  if old then
    local list = (self.__type == "Texture" or self.__type == "FontString") and old.__regions or old.__children
    for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
  end
  self.__parent = p
  if p then
    local list = (self.__type == "Texture" or self.__type == "FontString") and p.__regions or p.__children
    list[#list+1] = self
  end
end

-- Texture
local T = methodsFor("Texture")
function T:SetTexture(a, ...) self.__texture = a end
function T:GetTexture() return self.__texture end
function T:SetTexCoord(...) self.__texcoord = { ... } end
function T:SetGradient() end
function T:SetBlendMode(m) self.__blend = m end
function T:SetDesaturated(d) self.__desat = d end

-- FontString
local FS = methodsFor("FontString")
function FS:SetText(t) H.gen = H.gen + 1; self.__text = t end
function FS:GetText() return self.__text end
function FS:SetFormattedText(fmt, ...) H.gen = H.gen + 1; self.__text = format(fmt, ...) end
function FS:SetFontObject(f) H.gen = H.gen + 1; self.__font = f end
function FS:GetFontObject() return self.__font end
function FS:SetFont(path, size, flags) H.gen = H.gen + 1; self.__fontsize = size end
function FS:GetFont() local s = self.__fontsize or (self.__font and self.__font.size) or 12 return "Fonts\\FRIZQT__.TTF", s, "" end
function FS:SetJustifyH(j) self.__justifyH = j end
function FS:SetJustifyV(j) self.__justifyV = j end
function FS:SetTextColor(...) self.__color = { ... } end
function FS:GetStringWidth() return textWidth(self.__text, select(2, self:GetFont())) end
function FS:SetWordWrap(w) self.__nowrap = not w end
function FS:SetNonSpaceWrap() end
function FS:SetShadowOffset() end
function FS:SetShadowColor() end

-- Frame
local F = methodsFor("Frame")
function F:SetScript(handler, func)
  if handler == "OnUpdate" or handler:match("^On") then self.__scripts[handler] = func end
end
function F:GetScript(handler) return self.__scripts[handler] end
function F:HookScript(handler, func)
  local old = self.__scripts[handler]
  self.__scripts[handler] = old and function(...) old(...) return func(...) end or func
end
function F:HasScript() return true end
function F:RegisterEvent(e)
  if not eventRegistry[e] then eventRegistry[e] = {}; eventOrder[e] = {} end
  if not eventRegistry[e][self] then eventRegistry[e][self] = true; table.insert(eventOrder[e], self) end
end
function F:UnregisterEvent(e)
  if eventRegistry[e] and eventRegistry[e][self] then
    eventRegistry[e][self] = nil
    for i, f in ipairs(eventOrder[e]) do if f == self then table.remove(eventOrder[e], i) break end end
  end
end
function F:UnregisterAllEvents() for e in pairs(eventRegistry) do self:UnregisterEvent(e) end end
function F:IsEventRegistered(e) return eventRegistry[e] and eventRegistry[e][self] and 1 or nil end
function F:SetAttribute(k, v) checkProtected(self, "SetAttribute"); self.__attrs[k] = v; local h = self.__scripts.OnAttributeChanged if h then pcallr(h, self, k, v) end end
function F:GetAttribute(k) return self.__attrs[k] end
function F:SetFrameLevel(l) self.__level = l end
function F:GetFrameLevel()      -- like the client: one above the parent unless set
  if self.__level then return self.__level end
  local p = self.__parent
  return (p and p.GetFrameLevel) and (p:GetFrameLevel() + 1) or 1
end
function F:SetFrameStrata(s) self.__strata = s end
function F:GetFrameStrata() return self.__strata or "MEDIUM" end
function F:CreateTexture(name, layer, inherits)
  if name then name = name:gsub("%$parent", self.__name or "") end
  local t = newObject("Texture", name, self)
  t.__layer = layer
  return t
end
function F:CreateFontString(name, layer, inherits)
  if name then name = name:gsub("%$parent", self.__name or "") end
  local fs = newObject("FontString", name, self)
  fs.__layer = layer
  if inherits then
    assert(_G[inherits] and _G[inherits].__fontObject, "CreateFontString: unknown font object " .. tostring(inherits))
    fs.__font = _G[inherits]
  end
  return fs
end
function F:SetBackdrop(b) self.__backdrop = b end
function F:GetChildren() return unpack(self.__children) end
function F:GetRegions() return unpack(self.__regions) end
function F:GetNumChildren() return #self.__children end
function F:SetFrameRef(k, f) self.__frameRefs = self.__frameRefs or {}; self.__frameRefs[k] = f end
function F:IsProtected() return isProtected(self) and 1 or nil, self.__protected and 1 or nil end
function F:StartMoving() checkProtected(self, "StartMoving") end
function F:StartSizing() checkProtected(self, "StartSizing") end
function F:StopMovingOrSizing() checkProtected(self, "StopMovingOrSizing") end
function F:SetScale(s) self.__scale = s end
function F:GetScale() return self.__scale or 1 end
function F:GetEffectiveScale() return 1 end
function F:SetID(id) self.__id = id end
function F:GetID() return self.__id or 0 end
function F:EnableMouse() end
function F:SetMovable() end
function F:SetResizable() end
function F:SetMinResize(w, h) self.__minResize = { w, h } end
function F:SetMaxResize(w, h) self.__maxResize = { w, h } end
function F:SetClampedToScreen() end
function F:SetClampRectInsets() end
function F:SetToplevel() end
function F:RegisterForDrag() end
function F:SetHitRectInsets() end
function F:SetBackdropColor(...) self.__bdcolor = { ... } end
function F:SetBackdropBorderColor(...) self.__bdbcolor = { ... } end
function F:EnableKeyboard() end
function F:Raise() end
function F:Lower() end
function F:SetUserPlaced() end
function F:IsMouseOver() return false end

-- Button
local B = methodsFor("Button")
local function buttonText(self)
  if not self.__fontstring then
    self.__fontstring = self:CreateFontString(self.__name and (self.__name .. "Text") or nil, "ARTWORK", "GameFontNormal")
    self.__fontstring:SetPoint("CENTER", self, "CENTER", 0, 0)
  end
  return self.__fontstring
end
function B:SetText(t) buttonText(self):SetText(t) end
function B:GetText() return self.__fontstring and self.__fontstring:GetText() end
function B:SetFormattedText(fmt, ...) buttonText(self):SetText(format(fmt, ...)) end
function B:GetFontString() return self.__fontstring end
function B:SetFontString(fs) self.__fontstring = fs end
function B:GetTextWidth() return self.__fontstring and self.__fontstring:GetStringWidth() or 0 end
function B:Enable() if self.__disabled then self.__disabled = nil; local h = self.__scripts.OnEnable if h then pcallr(h, self) end end end
function B:Disable() if not self.__disabled then self.__disabled = true; local h = self.__scripts.OnDisable if h then pcallr(h, self) end end end
-- 3.3.5a style: 1 when enabled, 0 when disabled (the variant that breaks `if btn:IsEnabled()`)
function B:IsEnabled() return self.__disabled and 0 or 1 end
for _, kind in ipairs({ "Normal", "Pushed", "Highlight", "Disabled", "Checked", "DisabledChecked" }) do
  B["Set" .. kind .. "Texture"] = function(self, tex)
    if type(tex) == "string" then local t = self:CreateTexture(nil, "ARTWORK"); t:SetTexture(tex); t:SetAllPoints(self); tex = t end
    self["__tex" .. kind] = tex
  end
  B["Get" .. kind .. "Texture"] = function(self)
    if not self["__tex" .. kind] then local t = self:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(self); self["__tex" .. kind] = t end
    return self["__tex" .. kind]
  end
end
function B:SetNormalFontObject(f) end
function B:SetHighlightFontObject(f) end
function B:SetDisabledFontObject(f) end
function B:LockHighlight() end
function B:UnlockHighlight() end
function B:RegisterForClicks() checkProtected(self, "RegisterForClicks") end
function B:SetMotionScriptsWhileDisabled() end
function B:Click(button)
  if self.__disabled then return end
  if self.__type == "CheckButton" then self.__checked = not self.__checked end
  local h = self.__scripts.OnClick
  if h then pcallr(h, self, button or "LeftButton", false) end
end

-- CheckButton
local CB = methodsFor("CheckButton")
function CB:SetChecked(c) self.__checked = (c and c ~= 0) and true or false end
function CB:GetChecked() return self.__checked and 1 or nil end

-- Slider
local SL = methodsFor("Slider")
function SL:SetMinMaxValues(a, b) self.__min, self.__max = a, b; local v = self.__value or 0; if v < a or v > b then self:SetValue(v) end end
function SL:GetMinMaxValues() return self.__min or 0, self.__max or 0 end
function SL:SetValue(v)
  v = math.max(self.__min or v, math.min(self.__max or v, v))
  if self.__step and self.__step > 0 then v = (self.__min or 0) + math.floor((v - (self.__min or 0)) / self.__step + 0.5) * self.__step end
  if v ~= self.__value then
    self.__value = v
    local h = self.__scripts.OnValueChanged
    if h then pcallr(h, self, v) end
  end
end
function SL:GetValue() return self.__value or 0 end
function SL:SetValueStep(s) self.__step = s end
function SL:SetOrientation() end
function SL:SetThumbTexture(t) end
function SL:GetThumbTexture() return self.__thumb end
function SL:Enable() end
function SL:Disable() end

-- StatusBar
local SB = methodsFor("StatusBar")
function SB:SetMinMaxValues(a, b) self.__min, self.__max = a, b end
function SB:GetMinMaxValues() return self.__min or 0, self.__max or 1 end
function SB:SetValue(v) self.__value = v end
function SB:GetValue() return self.__value or 0 end
function SB:SetStatusBarTexture(t)
  if not self.__sbtex then self.__sbtex = self:CreateTexture(nil, "ARTWORK"); self.__sbtex:SetAllPoints(self) end
  self.__sbtex:SetTexture(t)
end
function SB:GetStatusBarTexture() if not self.__sbtex then self:SetStatusBarTexture(nil) end return self.__sbtex end
function SB:SetStatusBarColor(r, g, b) self.__sbcolor = { r, g, b } end
function SB:GetStatusBarColor() local c = self.__sbcolor or { 1, 1, 1 } return c[1], c[2], c[3] end

-- EditBox
local EB = methodsFor("EditBox")
function EB:SetText(t) self.__text = t; local h = self.__scripts.OnTextChanged if h then pcallr(h, self, false) end end
function EB:GetText() return self.__text or "" end
function EB:SetFocus() end
function EB:ClearFocus() end
function EB:SetMaxLetters() end
function EB:SetAutoFocus() end

-- Cooldown
local CD = methodsFor("Cooldown")
function CD:SetCooldown(s, d) self.__cd = { s, d } end
function CD:SetReverse() end

------------------------------------------------------------------------
-- Show/Hide propagation (OnShow/OnHide for newly visible/hidden subtrees)
------------------------------------------------------------------------
local function walkVisible(o, fn)
  if not o.__shown then return end
  fn(o)
  for _, c in ipairs(o.__children or {}) do walkVisible(c, fn) end
end
function H.fireShow(o)
  if o.__type == "Texture" or o.__type == "FontString" then return end
  walkVisible(o, function(f) local h = f.__scripts and f.__scripts.OnShow if h then pcallr(h, f) end end)
end
function H.fireHide(o)
  if o.__type == "Texture" or o.__type == "FontString" then return end
  local function walk(f)
    if not f.__shown then return end
    local h = f.__scripts and f.__scripts.OnHide if h then pcallr(h, f) end
    for _, c in ipairs(f.__children or {}) do walk(c) end
  end
  local h = o.__scripts and o.__scripts.OnHide if h then pcallr(h, o) end
  for _, c in ipairs(o.__children or {}) do walk(c) end
end

------------------------------------------------------------------------
-- Layout solver
------------------------------------------------------------------------
H.SCREEN = { __name = "SCREEN", __points = {}, __w = 1920, __h = 1080 }
local function pointCoord(o, point)
  -- absolute coordinate of `point` on o
  local l, r = H.hspan(o)
  local b, t = H.vspan(o)
  if not (l and b) then return nil end
  local x = point:find("LEFT") and l or point:find("RIGHT") and r or (l + r) / 2
  local y = point:find("TOP") and t or point:find("BOTTOM") and b or (b + t) / 2
  return x, y
end
local resolving = {}
local function relCoord(o, a)
  if a.rel == H.SCREEN then
    local x = a.relPoint:find("LEFT") and 0 or a.relPoint:find("RIGHT") and 1920 or 960
    local y = a.relPoint:find("TOP") and 1080 or a.relPoint:find("BOTTOM") and 0 or 540
    return x + a.x, y + a.y
  end
  local x, y = pointCoord(a.rel, a.relPoint)
  if not x then return nil end
  return x + a.x, y + a.y
end
local function implicitWidth(o)
  if o.__w and o.__w > 0 then return o.__w end
  if o.__type == "FontString" then return o:GetStringWidth() end
  if o.__type == "Button" and o.__fontstring and (not o.__w or o.__w == 0) then return 0 end
  return o.__w
end
local function implicitHeight(o, width)
  if o.__h and o.__h > 0 then return o.__h end
  if o.__type == "FontString" then
    local size = select(2, o:GetFont())
    local lines = 1
    if width and width > 0 then
      local tw = o:GetStringWidth()
      lines = math.max(1, math.ceil(tw / width - 0.001))
    end
    return lines * (size + 2)
  end
  return o.__h
end
function H.hspan(o)
  if o == H.SCREEN then return 0, 1920 end
  local c = o.__hcache
  if c and c[1] == H.gen then return c[2], c[3] end
  local l, r = H.hspanRaw(o)
  o.__hcache = { H.gen, l, r }
  return l, r
end
function H.hspanRaw(o)
  if resolving[o] then error("anchor loop on " .. tostring(o.__name)) end
  resolving[o] = true
  local P = o.__points
  local l, r, c
  for _, p in ipairs({ "TOPLEFT", "LEFT", "BOTTOMLEFT" }) do if P[p] then l = l or relCoord(o, P[p]) end end
  for _, p in ipairs({ "TOPRIGHT", "RIGHT", "BOTTOMRIGHT" }) do if P[p] then r = r or relCoord(o, P[p]) end end
  for _, p in ipairs({ "TOP", "CENTER", "BOTTOM" }) do if P[p] then c = c or relCoord(o, P[p]) end end
  local w = implicitWidth(o)
  resolving[o] = nil
  if not next(P) and o.__lastRect then return o.__lastRect[1], o.__lastRect[2] end
  -- like the client: anchors win over the explicit size, and a centre anchor
  -- combined with one edge fixes the other edge (2*centre - edge)
  if l and r then return l, r end
  if l and c then return l, 2 * c - l end
  if r and c then return 2 * c - r, r end
  if l and w then return l, l + w end
  if r and w then return r - w, r end
  if c and w then return c - w / 2, c + w / 2 end
  return nil
end
function H.vspan(o)
  if o == H.SCREEN then return 0, 1080 end
  local c = o.__vcache
  if c and c[1] == H.gen then return c[2], c[3] end
  local b, t = H.vspanRaw(o)
  o.__vcache = { H.gen, b, t }
  return b, t
end
function H.vspanRaw(o)
  if resolving[o] then error("anchor loop on " .. tostring(o.__name)) end
  resolving[o] = true
  local P = o.__points
  local t, b, c
  for _, p in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT" }) do if P[p] then local _, y = relCoord(o, P[p]); t = t or y end end
  for _, p in ipairs({ "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do if P[p] then local _, y = relCoord(o, P[p]); b = b or y end end
  for _, p in ipairs({ "LEFT", "CENTER", "RIGHT" }) do if P[p] then local _, y = relCoord(o, P[p]); c = c or y end end
  resolving[o] = nil
  local width
  local l, r = H.hspan(o)
  if l and r then width = r - l end
  local h = implicitHeight(o, width)
  if not next(P) and o.__lastRect then return o.__lastRect[3], o.__lastRect[4] end
  if t and b then return b, t end
  if t and c then return 2 * c - t, t end
  if b and c then return b, 2 * c - b end
  if t and h then return t - h, t end
  if b and h then return b, b + h end
  if c and h then return c - h / 2, c + h / 2 end
  return nil
end

------------------------------------------------------------------------
-- Events / updates
------------------------------------------------------------------------
function H.FireEvent(event, ...)
  local list = eventOrder[event]
  if not list then return end
  local copy = {}
  for i, f in ipairs(list) do copy[i] = f end
  for _, f in ipairs(copy) do
    if eventRegistry[event] and eventRegistry[event][f] then
      local h = f.__scripts.OnEvent
      if h then pcallr(h, f, event, ...) end
    end
  end
end
function H.RunUpdates(elapsed, n)
  for _ = 1, (n or 1) do
    H.now = H.now + elapsed
    if H.applyVisibilityDrivers then H.applyVisibilityDrivers() end
    local copy = {}
    for i, o in ipairs(allObjects) do copy[i] = o end
    for _, o in ipairs(copy) do
      local h = o.__scripts and o.__scripts.OnUpdate
      if h and o:IsVisible() then pcallr(h, o, elapsed) end
    end
  end
end

return H
