local _, IH = ...

IH.styles = {
    CLASSIC = "Classic WoW Glow",
    MODERN = "Modern WoW Glow",
    ASSISTED = "Blizzard Assisted Highlight",
}

local overlays, buttonsBySpell = {}, {}
local candidateButtons, candidateSet, interruptRecords, macroCandidateRecords = {}, {}, {}, {}
local fullScanQueued = false
local testOverrideUntil = 0
local testButtons = {}
local buttonSlots = {}
local buttonSpells = {}
local ownedMacroButtons = {}
local spellFallbackTargets = {}
local rangeSpellIDs = {}
local rangeActionSlots = {}
local enabledRangeSpellIDs = {}
local lastRangeSource

local function SetRangeSource(source)
    if source == lastRangeSource then return end
    lastRangeSource = source
    IH.lastRangeSource = source
end

local function ActionFromButton(button)
    local action = button and button.action
    if action == nil and button and button.GetAttribute then
        local ok, value = pcall(button.GetAttribute, button, "action")
        if ok then action = value end
    end
    local ok, numericAction = pcall(tonumber, action)
    if not ok then return nil end
    action = numericAction
    if action and action > 0 then return action end
end

local function SpellFromAction(action)
    local actionType, id = GetActionInfo(action)
    if actionType == "spell" then return id end
    if actionType == "macro" then
        local ownedSpellID = IH.GetOwnedGeneratedSpellForMacro and IH:GetOwnedGeneratedSpellForMacro(id)
        if ownedSpellID then return ownedSpellID, true end
        local a, _, c = GetMacroSpell(id)
        return c or (type(a) == "number" and a or nil)
    end
end

local function IsActionButton(frame)
    if not frame then return false end
    if not ActionFromButton(frame) then return false end
    if not frame.GetObjectType then return true end
    local ok, objectType = pcall(frame.GetObjectType, frame)
    return not ok or objectType == "CheckButton" or objectType == "Button"
end

local function AddCandidate(button)
    if IsActionButton(button) and not candidateSet[button] then
        candidateSet[button] = true
        candidateButtons[#candidateButtons + 1] = button
    end
end

local STANDARD_BUTTONS = {
    { "ActionButton", 12 }, { "MultiBarBottomLeftButton", 12 },
    { "MultiBarBottomRightButton", 12 }, { "MultiBarRightButton", 12 },
    { "MultiBarLeftButton", 12 }, { "MultiBar5Button", 12 },
    { "MultiBar6Button", 12 }, { "MultiBar7Button", 12 },
    { "PetActionButton", 10 }, { "StanceButton", 10 },
}

local function AddStandardButtons()
    for _, definition in ipairs(STANDARD_BUTTONS) do
        for index = 1, definition[2] do AddCandidate(_G[definition[1] .. index]) end
    end
end

local function IsInterruptSlot(slot, spellID)
    if C_ActionBar and C_ActionBar.IsInterruptAction then
        local ok, result = pcall(C_ActionBar.IsInterruptAction, slot)
        if ok and result then return true end
    end
    return spellID and IH.interruptSpells and IH.interruptSpells[spellID] or false
end

local function RebuildRecords()
    wipe(buttonsBySpell)
    wipe(interruptRecords)
    wipe(macroCandidateRecords)
    wipe(buttonSlots)
    wipe(buttonSpells)
    wipe(ownedMacroButtons)
    for _, button in ipairs(candidateButtons) do
        local slot = ActionFromButton(button)
        if slot then
            buttonSlots[button] = slot
            local spellID, ownedMacro = SpellFromAction(slot)
            local actionType, directSpellID = GetActionInfo(slot)
            buttonSpells[button] = spellID
            ownedMacroButtons[button] = ownedMacro and true or nil
            if spellID then
                buttonsBySpell[spellID] = buttonsBySpell[spellID] or {}
                buttonsBySpell[spellID][#buttonsBySpell[spellID] + 1] = button
                local override = C_Spell and C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spellID)
                if override and override ~= spellID then
                    buttonsBySpell[override] = buttonsBySpell[override] or {}
                    buttonsBySpell[override][#buttonsBySpell[override] + 1] = button
                end
            end
            local castStop = IH.additionalMacroCastStops and
                ((spellID and IH.additionalMacroCastStops[spellID]) or
                (actionType == "spell" and directSpellID and IH.additionalMacroCastStops[directSpellID]))
            -- Cast-stop metadata never promotes an action to a runtime
            -- interrupt. A slot is included only when Blizzard classifies it
            -- as an interrupt (or it matches the true-interrupt fallback).
            if not castStop and IsInterruptSlot(slot, spellID) then
                interruptRecords[#interruptRecords + 1] = {
                    button = button, slot = slot, spellID = spellID, ownedMacro = ownedMacro,
                }
            end

            -- This is intentionally independent from interruptRecords. Every
            -- cached action button is inspected directly, including actions
            -- for which C_ActionBar.IsInterruptAction returns false.
            if castStop then
                macroCandidateRecords[#macroCandidateRecords + 1] = {
                    button = button, slot = slot, spellID = directSpellID,
                    castStopType = castStop.category, label = castStop.label,
                }
            end
        end
    end
    IH.cachedActionButtons = #candidateButtons
    IH.interruptRecords = interruptRecords
    IH.macroCandidateRecords = macroCandidateRecords
    if IH.RefreshDetectedAbilities then IH:RefreshDetectedAbilities() end
end

local function AddPulse(frame, texture, duration)
    local group = texture:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.48); alpha:SetToAlpha(1); alpha:SetDuration(duration or 0.5)
    frame.animation = group
end

local function AddFlipBook(frame, texture, duration, rows, columns, frames, frameWidth, frameHeight)
    local group = texture:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local flip = group:CreateAnimation("FlipBook")
    local ok = pcall(function()
        flip:SetDuration(duration)
        flip:SetOrder(1)
        flip:SetFlipBookRows(rows)
        flip:SetFlipBookColumns(columns)
        flip:SetFlipBookFrames(frames)
        if frameWidth and flip.SetFlipBookFrameWidth then flip:SetFlipBookFrameWidth(frameWidth) end
        if frameHeight and flip.SetFlipBookFrameHeight then flip:SetFlipBookFrameHeight(frameHeight) end
    end)
    if ok then frame.animation = group; return true end
    AddPulse(frame, texture, 0.5)
    return false
end

local function TryAtlas(texture, atlas)
    local ok = pcall(texture.SetAtlas, texture, atlas, false)
    return ok and texture:GetTexture() ~= nil
end

local function AddFallbackBorder(frame)
    frame.textures = {}
    for i = 1, 4 do
        local line = frame:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(1, 1, 1, 1)
        frame.textures[i] = line
    end
    frame.textures[1]:SetPoint("TOPLEFT", -4, 4); frame.textures[1]:SetPoint("TOPRIGHT", 4, 4); frame.textures[1]:SetHeight(4)
    frame.textures[2]:SetPoint("BOTTOMLEFT", -4, -4); frame.textures[2]:SetPoint("BOTTOMRIGHT", 4, -4); frame.textures[2]:SetHeight(4)
    frame.textures[3]:SetPoint("TOPLEFT", -4, 4); frame.textures[3]:SetPoint("BOTTOMLEFT", -4, -4); frame.textures[3]:SetWidth(4)
    frame.textures[4]:SetPoint("TOPRIGHT", 4, 4); frame.textures[4]:SetPoint("BOTTOMRIGHT", 4, -4); frame.textures[4]:SetWidth(4)
    AddPulse(frame, frame.textures[1], 0.42)
end

local function UpdateOverlayGeometry(frame)
    if not frame or not frame.button then return end
    local scale = tonumber(IH.db and IH.db.glowScale) or 1
    scale = math.max(0, math.min(1.5, scale))
    local width = math.max(frame.button:GetWidth(), 36)
    local height = math.max(frame.button:GetHeight(), 36)
    if frame.mainTexture then
        frame.mainTexture:SetSize(width * frame.baseSize * scale, height * frame.baseSize * scale)
    elseif frame.atlasFallback then
        -- Keep the real fallback border at four pixels; only its footprint moves.
        local x = math.max(0.5, 4 + width * frame.baseSize * (scale - 1) * 0.5)
        local y = math.max(0.5, 4 + height * frame.baseSize * (scale - 1) * 0.5)
        for _, texture in ipairs(frame.textures) do texture:ClearAllPoints() end
        frame.textures[1]:SetPoint("TOPLEFT", -x, y); frame.textures[1]:SetPoint("TOPRIGHT", x, y)
        frame.textures[2]:SetPoint("BOTTOMLEFT", -x, -y); frame.textures[2]:SetPoint("BOTTOMRIGHT", x, -y)
        frame.textures[3]:SetPoint("TOPLEFT", -x, y); frame.textures[3]:SetPoint("BOTTOMLEFT", -x, -y)
        frame.textures[4]:SetPoint("TOPRIGHT", x, y); frame.textures[4]:SetPoint("BOTTOMRIGHT", x, -y)
    end
end

local function CreateOverlay(button, style, parent)
    local frame = CreateFrame("Frame", nil, parent or button)
    frame:SetAllPoints(button)
    frame:SetFrameLevel(button:GetFrameLevel() + 8)
    frame.textures = {}
    frame.button = button
    frame.baseSize = style == "CLASSIC" and 1.20 or 1.65

    if style == "CLASSIC" then
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetPoint("CENTER")
        texture:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
        frame.textures[1] = texture
        frame.mainTexture = texture
        -- IconAlertAnts is a 256x256 sheet containing 22 used 48x48 cells
        -- arranged in five columns. Explicit cell dimensions are essential:
        -- a naive 256/5 split includes sheet padding and bleeds adjacent cells.
        frame.flipBookReady = AddFlipBook(frame, texture, 0.37, 5, 5, 22, 48, 48)
    else
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetPoint("CENTER")
        local atlas = style == "MODERN" and "UI-HUD-ActionBar-Proc-Loop-Flipbook"
            or "rotationhelper_ants_flipbook"
        if TryAtlas(texture, atlas) then
            frame.textures[1] = texture
            frame.mainTexture = texture
            frame.flipBookReady = AddFlipBook(frame, texture, 1, 6, 5, 30)
        else
            texture:Hide()
            AddFallbackBorder(frame)
            frame.atlasFallback = atlas
        end
    end
    UpdateOverlayGeometry(frame)
    frame:Hide()
    return frame
end

function IH:RefreshGlowGeometry()
    for _, entry in pairs(overlays) do
        UpdateOverlayGeometry(entry.testFrame)
        for _, layer in pairs(entry.layers or {}) do UpdateOverlayGeometry(layer) end
    end
end

local function ApplyColor(frame, color)
    local r, g, b = color.r or 1, color.g or 0.82, color.b or 0.12
    for _, texture in ipairs(frame.textures or {}) do
        pcall(texture.SetDesaturated, texture, true)
        texture:SetVertexColor(r, g, b, 1)
    end
end

local function PlayOverlay(frame)
    ApplyColor(frame, IH.db.color or IH.defaults.color)
    frame:Show()
    if frame.animation and not frame.animation:IsPlaying() then frame.animation:Play() end
end

function IH:RefreshButtonCache()
    AddStandardButtons()
    RebuildRecords()
end

function IH:RequestFullButtonScan(announce)
    if InCombatLockdown and InCombatLockdown() then
        fullScanQueued = true
        if announce then self:Print("scan queued until combat ends") end
        return false
    end
    AddStandardButtons()
    local frame, visited = EnumerateFrames(), 0
    while frame and visited < 10000 do
        AddCandidate(frame)
        visited = visited + 1
        frame = EnumerateFrames(frame)
    end
    RebuildRecords()
    if self.RefreshMacroCandidates then self:RefreshMacroCandidates() end
    if self.RefreshCooldownManagerCache then self:RefreshCooldownManagerCache() end
    fullScanQueued = false
    self.fullScanCount = (self.fullScanCount or 0) + 1
    self.lastScanVisited = visited
    if announce then
        self:Print(("scan complete — %d action buttons, %d interrupts."):format(#candidateButtons, #interruptRecords))
        if #interruptRecords == 0 then
            self:Print("Place an interrupt on an action bar and use /ih scan or the Scan button in settings.")
        end
    end
    if self.UpdateScanStatus then self:UpdateScanStatus() end
    return true
end

function IH:RunQueuedButtonScan()
    if not fullScanQueued then return end
    if self.startupScanPending then
        self:PerformStartupScan()
    else
        self:RequestFullButtonScan(true)
    end
end

function IH:HideAllGlows()
    for _, entry in pairs(overlays) do
        if entry.testFrame and entry.testFrame.animation then entry.testFrame.animation:Stop() end
        if entry.testFrame then entry.testFrame:Hide() end
        for _, layer in pairs(entry.layers or {}) do
            if layer.animation then layer.animation:Stop() end
            layer:Hide()
        end
        if entry.gate then entry.gate:Hide() end
    end
end

local function EnsureEntry(button)
    local entry = overlays[button]
    if not entry or entry.style ~= IH.db.style then
        if entry then
            if entry.testFrame then entry.testFrame:Hide() end
            if entry.gate then entry.gate:Hide() end
        end
        local gate = CreateFrame("Frame", nil, button)
        gate:SetAllPoints(button)
        gate:SetFrameLevel(button:GetFrameLevel() + 7)
        gate:Hide()
        entry = { style = IH.db.style, gate = gate, layers = {}, rangeGates = {} }
        overlays[button] = entry
    end
    return entry
end

local function ShowTest(buttons)
    local wanted, shown = {}, 0
    for _, button in ipairs(buttons or {}) do
        if IH.db.highlightCooldownManager or not spellFallbackTargets[button] then
            local entry = EnsureEntry(button)
            if not entry.testFrame then entry.testFrame = CreateOverlay(button, IH.db.style, button) end
            wanted[entry], shown = true, shown + 1
            entry.gate:Hide()
            PlayOverlay(entry.testFrame)
        end
    end
    for _, entry in pairs(overlays) do
        if not wanted[entry] and entry.testFrame then entry.testFrame:Hide() end
    end
    return shown
end

function IH:IsTestOverrideActive()
    return testOverrideUntil > 0 and GetTime() < testOverrideUntil
end

function IH:ShowTestButtons()
    if self:IsTestOverrideActive() then ShowTest(testButtons) end
end

local function ApplyCooldownGate(gate, slot, spellID, ownedMacro)
    local function SpellFallback()
        if not (ownedMacro or spellFallbackTargets[gate.interruptHighlightTarget]) or not spellID
            or not C_Spell or not C_Spell.GetSpellCooldownDuration
            or not gate.SetAlphaFromBoolean then
            gate:SetAlpha(0)
            return false
        end
        local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if not ok or not duration or not duration.IsActive then gate:SetAlpha(0); return false end
        gate:SetAlphaFromBoolean(duration:IsActive(), 0, 1)
        return true
    end
    if not slot or not C_ActionBar or not C_ActionBar.GetActionCooldownDuration
        or not gate.SetAlphaFromBoolean then return SpellFallback() end
    local ok, duration = pcall(C_ActionBar.GetActionCooldownDuration, slot, true)
    if not ok or not duration or not duration.IsActive then return SpellFallback() end
    -- IsActive may itself be secret. The widget consumes it directly: an
    -- active real cooldown gets alpha 0, while zero/inactive/expired gets 1.
    gate:SetAlphaFromBoolean(duration:IsActive(), 0, 1)
    return true
end

-- C_ActionBar.IsActionInRange is documented as boolean?/nil. Keep the API
-- call and boolean coercion protected so a future restricted value fails
-- closed instead of being compared or used as Lua control flow.
local function ActionSlotInRange(slot, unit)
    if not slot or not unit or not C_ActionBar or not C_ActionBar.IsActionInRange then return nil end
    local ok, value = pcall(C_ActionBar.IsActionInRange, slot, unit)
    if not ok or type(value) == "nil" then return nil end
    local usable, ordinary = pcall(function() return value and true or false end)
    if not usable then return nil end
    return ordinary
end

local function QualifyActionSlots(slots, unit)
    local checked, anyInRange = {}, false
    for _, slot in ipairs(slots or {}) do
        checked[#checked + 1] = slot
        local inRange = ActionSlotInRange(slot, unit)
        if inRange == true then anyInRange = true end
    end
    return anyInRange, checked
end

local function AddUniqueSpellID(result, seen, spellID)
    local ok, numericID = pcall(tonumber, spellID)
    if ok and numericID and numericID > 0 and not seen[numericID] then
        seen[numericID] = true
        result[#result + 1] = numericID
    end
end

-- Resolve the player's usable interrupt spell independently of action bars.
-- The effective spell is preferred, followed by the canonical and base IDs;
-- clients may expose only one of these variants to the range API.
local function InterruptRangeSpellIDs(canonicalSpellID)
    local canonicalID = canonicalSpellID
    if IH.interruptSpells and not IH.interruptSpells[canonicalID] then
        for knownID in pairs(IH.interruptSpells) do
            local effectiveID
            if C_Spell and C_Spell.GetOverrideSpell then
                local ok, value = pcall(C_Spell.GetOverrideSpell, knownID)
                if ok then effectiveID = value end
            end
            if canonicalID == effectiveID then canonicalID = knownID; break end
            if C_Spell and C_Spell.GetBaseSpell then
                local ok, value = pcall(C_Spell.GetBaseSpell, canonicalSpellID)
                if ok and value == knownID then canonicalID = knownID; break end
            end
        end
    end

    local result, seen = {}, {}
    local effectiveID
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, value = pcall(C_Spell.GetOverrideSpell, canonicalID)
        if ok then effectiveID = value end
    end
    AddUniqueSpellID(result, seen, effectiveID)
    AddUniqueSpellID(result, seen, canonicalID)
    if C_Spell and C_Spell.GetBaseSpell then
        local ok, value = pcall(C_Spell.GetBaseSpell, effectiveID or canonicalID)
        if ok then AddUniqueSpellID(result, seen, value) end
    end
    if C_SpellBook and C_SpellBook.FindBaseSpellByID then
        local ok, value = pcall(C_SpellBook.FindBaseSpellByID, effectiveID or canonicalID)
        if ok then AddUniqueSpellID(result, seen, value) end
    end
    return result, canonicalID
end

local function IsInterruptInRangeForUnit(canonicalSpellID, unitToken)
    if not canonicalSpellID or not unitToken or not C_Spell or not C_Spell.IsSpellInRange then
        return nil, nil
    end
    local candidates = InterruptRangeSpellIDs(canonicalSpellID)
    for _, rangeSpellID in ipairs(candidates) do
        if C_Spell.EnableSpellRangeCheck and not enabledRangeSpellIDs[rangeSpellID] then
            local ok = pcall(C_Spell.EnableSpellRangeCheck, rangeSpellID, true)
            if ok then enabledRangeSpellIDs[rangeSpellID] = true end
        end
        local ok, inRange = pcall(C_Spell.IsSpellInRange, rangeSpellID, unitToken)
        if ok and type(inRange) ~= "nil" then return inRange, rangeSpellID end
    end
    return nil, candidates[1]
end

function IH:IsInterruptInRangeForUnit(canonicalSpellID, unitToken)
    return IsInterruptInRangeForUnit(canonicalSpellID, unitToken)
end

local function RangeResultLabel(value)
    local ok, label = pcall(function() return value and "in-range" or "out-of-range" end)
    return ok and label or "result-restricted"
end

local function ApplyRangeGate(gate, slot, unit, spellID, ownedMacro, matchingSlots)
    if not IH.db.onlyInRange then
        gate:SetAlpha(1)
        SetRangeSource("off")
        return true
    end
    local target = gate.interruptHighlightTarget
    local canonicalSpellID = rangeSpellIDs[target] or spellID
    local inRange, usedSpellID = IsInterruptInRangeForUnit(canonicalSpellID, unit)
    if type(inRange) ~= "nil" and gate.SetAlphaFromBoolean then
        -- The possibly restricted result goes directly to the secure widget
        -- gate and is never required as Lua control flow.
        gate:SetAlphaFromBoolean(inRange, 1, 0)
        SetRangeSource(("%s: %s -> spell %s %s"):format(tostring(spellID or canonicalSpellID),
            unit, tostring(usedSpellID), RangeResultLabel(inRange)))
        return true
    end

    -- Spell-native nil means unknown. Retain action-slot range strictly as a
    -- compatibility fallback; successful operation never requires a slot.
    local slots = matchingSlots
    if not slots or #slots == 0 then slots = slot and { slot } or {} end
    if #slots == 0 or not unit or not gate.SetAlphaFromBoolean then
        gate:SetAlpha(0)
        SetRangeSource(("%s: %s -> spell range unknown"):format(
            tostring(spellID or canonicalSpellID), tostring(unit)))
        return false
    end
    local inRange, checked = QualifyActionSlots(slots, unit)
    if #checked == 0 then gate:SetAlpha(0); return false end
    gate:SetAlphaFromBoolean(inRange, 1, 0)
    local labels = table.concat(checked, ",")
    SetRangeSource(("%s: %s -> spell range unknown; fallback slot%s %s %s"):format(
        tostring(spellID or canonicalSpellID), unit, #checked == 1 and "" or "s", labels,
        inRange and "in-range" or "out-of-range"))
    return true
end

local function ShowRuntimeButtons(buttons, casts)
    local wanted = {}
    for _, button in ipairs(buttons or {}) do
        local entry = EnsureEntry(button)
        wanted[entry] = true
        if entry.testFrame then entry.testFrame:Hide() end
        entry.gate:Show()
        entry.gate.interruptHighlightTarget = button
        ApplyCooldownGate(entry.gate, buttonSlots[button], buttonSpells[button], ownedMacroButtons[button])

        local wantedUnits = {}
        for _, cast in ipairs(casts or {}) do
            local unit = cast.unit
            local rangeGate = entry.rangeGates[unit]
            if not rangeGate then
                rangeGate = CreateFrame("Frame", nil, entry.gate)
                rangeGate:SetAllPoints(button)
                entry.rangeGates[unit] = rangeGate
            end
            local layer = entry.layers[unit]
            if not layer then
                layer = CreateOverlay(button, IH.db.style, rangeGate)
                entry.layers[unit] = layer
            end
            wantedUnits[unit] = true
            rangeGate:Show()
            rangeGate.interruptHighlightTarget = button
            ApplyRangeGate(rangeGate, buttonSlots[button], unit, buttonSpells[button],
                ownedMacroButtons[button], rangeActionSlots[button])
            PlayOverlay(layer)
            if layer.SetAlphaFromBoolean and type(cast.notInterruptible) ~= "nil" then
                layer:SetAlphaFromBoolean(cast.notInterruptible, 0, 1)
            else
                -- Unsupported clients fail closed; never inspect the flag.
                layer:SetAlpha(0)
            end
        end
        for unit, layer in pairs(entry.layers) do
            if not wantedUnits[unit] then
                if layer.animation then layer.animation:Stop() end
                layer:Hide()
                if entry.rangeGates[unit] then entry.rangeGates[unit]:Hide() end
            end
        end
    end
    for _, entry in pairs(overlays) do
        if not wanted[entry] and entry.gate then entry.gate:Hide() end
    end
end

function IH:ShowForSpell(spellID, casts)
    local buttons = buttonsBySpell[spellID]
    if not buttons or #buttons == 0 then buttons = self:GetDetectedInterruptButtons() end
    local combined, seen = {}, {}
    for _, button in ipairs(buttons or {}) do
        if not seen[button] then seen[button] = true; combined[#combined + 1] = button end
    end
    if self.db.highlightCooldownManager and self.GetCooldownManagerTargets then
        for _, target in ipairs(self:GetCooldownManagerTargets(spellID)) do
            if not seen[target] then seen[target] = true; combined[#combined + 1] = target end
        end
    end
    ShowRuntimeButtons(combined, casts)
end

function IH:RegisterHighlightTarget(frame, slot, spellID, allowSpellCooldownFallback, rangeSpellID, matchingSlots)
    if not frame then return end
    buttonSlots[frame] = slot
    buttonSpells[frame] = spellID
    ownedMacroButtons[frame] = nil
    spellFallbackTargets[frame] = allowSpellCooldownFallback and true or nil
    rangeSpellIDs[frame] = rangeSpellID
    rangeActionSlots[frame] = matchingSlots
end

function IH:GetDetectedInterruptButtons()
    local result, seen = {}, {}
    for _, record in ipairs(interruptRecords) do
        local button = record.button
        if button and not seen[button] then seen[button] = true; result[#result + 1] = button end
    end
    return result
end

function IH:TestGlow()
    if not self.rendererReady then self:InitializeRenderer() else self:RefreshButtonCache() end
    local buttons = self:GetDetectedInterruptButtons()
    if #buttons == 0 then
        self:RequestFullButtonScan(false)
        buttons = self:GetDetectedInterruptButtons()
    end
    if self.db.highlightCooldownManager and self.GetAllCooldownManagerTargets then
        local seen = {}; for _, button in ipairs(buttons) do seen[button] = true end
        for _, target in ipairs(self:GetAllCooldownManagerTargets()) do
            if not seen[target] then seen[target] = true; buttons[#buttons + 1] = target end
        end
    end
    wipe(testButtons)
    for _, button in ipairs(buttons) do testButtons[#testButtons + 1] = button end
    testOverrideUntil = GetTime() + 5
    local shown = ShowTest(testButtons)
    if shown == 0 then
        self:Print("test: no interrupt highlight target was detected")
        return
    end
    self:Print(("test: showing %s on %d interrupt button(s) for 5 seconds"):format(self.styles[self.db.style], shown))
    C_Timer.After(5, function()
        if GetTime() >= testOverrideUntil then
            testOverrideUntil = 0
            wipe(testButtons)
            self:HideAllGlows()
            self:Evaluate(true)
        end
    end)
end

function IH:RendererStatus()
    local buttons = self:GetDetectedInterruptButtons()
    local fallbacks = 0
    for _, entry in pairs(overlays) do
        if entry.testFrame and entry.testFrame.atlasFallback then fallbacks = fallbacks + 1 end
    end
    self:Print(("enabled=%s, mode=%s, only in range=%s, range=%s, cooldown manager=%s, CDM=%s, cache=%d, refresh=%s, secret items skipped=%d, style=%s, glow size=%d%%, action buttons=%d, true interrupts=%d, spellbook cast-stops=%d, startup guaranteed scan=%s, attempts=%d, recovery scans=%d, recovery pending=%s, renderer=%s, atlas fallbacks=%d"):format(
        self.db.enabled and "yes" or "no", self.db.mode == "TARGET" and "Target only" or "All visible enemies",
        self.db.onlyInRange and "on" or "off", self.lastRangeSource or "idle",
        self.db.highlightCooldownManager and "on" or "off",
        self.cooldownManagerEnabled and "enabled" or "disabled",
        self.cooldownManagerInterruptIcons or 0,
        self.cooldownManagerRefreshPending and "pending-combat" or "ready",
        self.cooldownManagerSecretItemsSkipped or 0,
        self.styles[self.db.style] or "unknown",
        math.floor((self.db.glowScale or 1) * 100 + 0.5), self.cachedActionButtons or 0, #buttons,
        #(self.spellbookCastStopRecords or {}),
        self.startupFullScanDone and "done" or "pending", self.startupScanAttempts or 0,
        self.recoveryScanCount or 0, (self.recoveryScanPending or self.recoveryScanDeferred) and "yes" or "no",
        self.rendererReady and "ready" or "not ready", fallbacks))

end

function IH:InitializeRenderer()
    self:RefreshButtonCache()
    if self.RefreshMacroCandidates then self:RefreshMacroCandidates() end
    self.rendererReady = true
end

IH._DiscoveryTestHooks = {
    AddCandidate = AddCandidate,
    RebuildRecords = RebuildRecords,
    ApplyCooldownGate = ApplyCooldownGate,
    ApplyRangeGate = ApplyRangeGate,
    ActionSlotInRange = ActionSlotInRange,
    QualifyActionSlots = QualifyActionSlots,
    InterruptRangeSpellIDs = InterruptRangeSpellIDs,
    IsInterruptInRangeForUnit = IsInterruptInRangeForUnit,
    UpdateOverlayGeometry = UpdateOverlayGeometry,
    Reset = function()
        wipe(candidateButtons); wipe(candidateSet); wipe(interruptRecords); wipe(macroCandidateRecords); wipe(buttonsBySpell); wipe(buttonSlots); wipe(buttonSpells); wipe(ownedMacroButtons); wipe(spellFallbackTargets); wipe(rangeSpellIDs); wipe(rangeActionSlots); wipe(enabledRangeSpellIDs); lastRangeSource = nil
    end,
    GetTestOverrideUntil = function() return testOverrideUntil end,
}
