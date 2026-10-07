local _, IH = ...

local VIEWER_NAMES = {
    "EssentialCooldownViewer", "UtilityCooldownViewer",
    "BuffIconCooldownViewer", "BuffBarCooldownViewer",
}

local records, targetsBySpell = {}, {}
local refreshQueued = false

local function IsUsablePublicValue(value)
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return value ~= nil
end

local function IsCooldownViewerEnabled()
    if not GetCVarBool then return true end
    local ok, enabled = pcall(GetCVarBool, "cooldownViewerEnabled")
    if not ok or not IsUsablePublicValue(enabled) then return false end
    return enabled and true or false
end

local function ClearCache()
    -- Hide before forgetting the frames. This path deliberately never reads an
    -- item spell ID, so disabling Blizzard's viewer is safe even in combat.
    if IH.HideAllGlows then IH:HideAllGlows() end
    wipe(records); wipe(targetsBySpell)
    IH.cooldownManagerInterruptIcons = 0
    IH.cooldownManagerSecretItemsSkipped = 0
    IH.cooldownManagerRefreshPending = false
    if IH.UpdateScanStatus then IH:UpdateScanStatus() end
end

local function EffectiveSpellID(spellID)
    if not IsUsablePublicValue(spellID) then return nil end
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, override = pcall(C_Spell.GetOverrideSpell, spellID)
        if ok and IsUsablePublicValue(override) then return override end
    end
    return spellID
end

local function CanonicalInterrupt(spellID)
    if not IsUsablePublicValue(spellID) then return nil end
    for canonicalID in pairs(IH.interruptSpells or {}) do
        local effectiveID = EffectiveSpellID(canonicalID)
        if spellID == canonicalID or spellID == effectiveID then return canonicalID, effectiveID end
        if C_Spell and C_Spell.GetBaseSpell then
            local ok, base = pcall(C_Spell.GetBaseSpell, spellID)
            if ok and IsUsablePublicValue(base) and base == canonicalID then return canonicalID, effectiveID end
        end
    end
end

local function BaseSpellID(spellID, canonicalID)
    if not IsUsablePublicValue(spellID) then return canonicalID end
    if C_Spell and C_Spell.GetBaseSpell then
        local ok, base = pcall(C_Spell.GetBaseSpell, spellID)
        if ok and IsUsablePublicValue(base) then return base end
    end
    if C_SpellBook and C_SpellBook.FindBaseSpellByID then
        local ok, base = pcall(C_SpellBook.FindBaseSpellByID, spellID)
        if ok and IsUsablePublicValue(base) then return base end
    end
    return canonicalID or spellID
end

local function ReadItemSpellID(item)
    for _, method in ipairs({ "GetSpellID", "GetBaseSpellID" }) do
        if item and type(item[method]) == "function" then
            local ok, spellID = pcall(item[method], item)
            if ok and IsUsablePublicValue(spellID) then return spellID end
            if ok then
                IH.cooldownManagerSecretItemsSkipped = (IH.cooldownManagerSecretItemsSkipped or 0) + 1
                return nil
            end
        end
    end
    if item and type(item.GetCooldownID) == "function" and C_CooldownViewer
        and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local okID, cooldownID = pcall(item.GetCooldownID, item)
        if okID and IsUsablePublicValue(cooldownID) then
            local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
            if okInfo and IsUsablePublicValue(info) then
                local spellID = info.spellID
                if not IsUsablePublicValue(spellID) then spellID = info.overrideSpellID end
                if IsUsablePublicValue(spellID) then return spellID end
                IH.cooldownManagerSecretItemsSkipped = (IH.cooldownManagerSecretItemsSkipped or 0) + 1
            end
        end
    end
end

local function MatchingActionSlots(canonicalID, effectiveID)
    local result, seen = {}, {}
    for _, record in ipairs(IH.interruptRecords or {}) do
        local recordCanonical, recordEffective = CanonicalInterrupt(record.spellID)
        if recordCanonical == canonicalID or record.spellID == canonicalID
            or record.spellID == effectiveID or recordEffective == effectiveID then
            local slot = tonumber(record.slot)
            if slot and not seen[slot] then
                seen[slot] = true
                result[#result + 1] = slot
            end
        end
    end
    table.sort(result)
    return result
end

local function AddTarget(frame, spellID)
    local canonicalID, effectiveID = CanonicalInterrupt(spellID)
    if not canonicalID then return end
    local slots = MatchingActionSlots(canonicalID, effectiveID)
    local slot = slots[1]
    local baseSpellID = BaseSpellID(effectiveID or spellID, canonicalID)
    local record = { frame = frame, spellID = effectiveID or spellID, canonicalID = canonicalID,
        baseSpellID = baseSpellID, slot = slot, slots = slots }
    records[#records + 1] = record
    for _, id in ipairs({ canonicalID, effectiveID, spellID }) do
        if id then
            targetsBySpell[id] = targetsBySpell[id] or {}
            targetsBySpell[id][#targetsBySpell[id] + 1] = frame
        end
    end
    IH:RegisterHighlightTarget(frame, slot, record.spellID, true, baseSpellID, slots)
end

function IH:RefreshCooldownManagerCache()
    if not self.db or not self.db.highlightCooldownManager then
        self.cooldownManagerEnabled = IsCooldownViewerEnabled()
        ClearCache()
        return false
    end
    self.cooldownManagerEnabled = IsCooldownViewerEnabled()
    if not self.cooldownManagerEnabled then
        ClearCache()
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        self.cooldownManagerRefreshPending = true
        if self.UpdateScanStatus then self:UpdateScanStatus() end
        return false
    end
    self.cooldownManagerRefreshPending = false
    self.cooldownManagerSecretItemsSkipped = 0
    wipe(records); wipe(targetsBySpell)
    local seen = {}
    for _, name in ipairs(VIEWER_NAMES) do
        local viewer = _G[name]
        local pool = viewer and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            for item in pool:EnumerateActive() do
                if item and not seen[item] then
                    seen[item] = true
                    AddTarget(item, ReadItemSpellID(item))
                end
            end
        end
    end
    self.cooldownManagerInterruptIcons = #records
    if self.UpdateScanStatus then self:UpdateScanStatus() end
    return true
end

function IH:GetCooldownManagerTargets(spellID)
    return targetsBySpell[spellID] or {}
end

function IH:GetAllCooldownManagerTargets()
    local result = {}
    for _, record in ipairs(records) do result[#result + 1] = record.frame end
    return result
end

function IH:QueueCooldownManagerRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        IH:RefreshCooldownManagerCache()
        IH:Evaluate(true)
    end)
end

function IH:OnCooldownViewerLoaded()
    self:QueueCooldownManagerRefresh()
end

function IH:OnCooldownViewerCVarChanged()
    self.cooldownManagerEnabled = IsCooldownViewerEnabled()
    if not self.cooldownManagerEnabled then
        ClearCache()
        if self.Evaluate then self:Evaluate(true) end
        return
    end
    self:QueueCooldownManagerRefresh()
end

function IH:ResumeCooldownManagerRefresh()
    if not self.cooldownManagerRefreshPending then return end
    self:QueueCooldownManagerRefresh()
end

function IH:InitializeCooldownManager()
    if self.cooldownManagerInitialized then return end
    self.cooldownManagerInitialized = true
    if EventRegistry and EventRegistry.RegisterCallback then
        for _, event in ipairs({
            "CooldownViewerSettings.OnDataChanged",
            "CooldownViewerSettings.OnShow",
            "CooldownViewerSettings.OnHide",
        }) do
            EventRegistry:RegisterCallback(event, function() IH:QueueCooldownManagerRefresh() end, self)
        end
    end
    if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
        CVarCallbackRegistry:RegisterCallback("cooldownViewerEnabled", function()
            IH:OnCooldownViewerCVarChanged()
        end, self)
    else
        local cvarFrame = CreateFrame("Frame")
        pcall(cvarFrame.RegisterEvent, cvarFrame, "CVAR_UPDATE")
        cvarFrame:SetScript("OnEvent", function(_, _, name)
            if name == "cooldownViewerEnabled" then IH:OnCooldownViewerCVarChanged() end
        end)
        self.cooldownManagerCVarFrame = cvarFrame
    end
    self:RefreshCooldownManagerCache()
end

IH._CooldownManagerTestHooks = {
    CanonicalInterrupt = CanonicalInterrupt,
    IsUsablePublicValue = IsUsablePublicValue,
    IsCooldownViewerEnabled = IsCooldownViewerEnabled,
    ClearCache = ClearCache,
    ReadItemSpellID = ReadItemSpellID,
    MatchingActionSlots = MatchingActionSlots,
    MatchingActionSlot = function(canonicalID, effectiveID)
        return MatchingActionSlots(canonicalID, effectiveID)[1]
    end,
    GetRecords = function() return records end,
}
