local _, IH = ...

local INTERRUPTS = {
    [1766] = true, [6552] = true, [2139] = true, [47528] = true,
    [57994] = true, [96231] = true, [106839] = true, [116705] = true,
    [147362] = true, [183752] = true, [187707] = true, [351338] = true,
}
IH.interruptSpells = INTERRUPTS

-- Macro-generator-only abilities. These never enter the runtime interrupt
-- pipeline, even when an action-bar API classifies one unexpectedly.
IH.additionalMacroCastStops = {
    [221562] = { category = "stun", class = "DEATHKNIGHT", label = "Cast stop (stun)" }, -- Asphyxiate
    [5211]   = { category = "stun", class = "DRUID", label = "Cast stop (stun)" },       -- Mighty Bash
    [22570]  = { category = "stun", class = "DRUID", label = "Cast stop (stun)" },       -- Maim
    [211881] = { category = "stun", class = "DEMONHUNTER", spec = "HAVOC", label = "Cast stop (stun)" }, -- Fel Eruption
    [19577]  = { category = "stun", class = "HUNTER", label = "Cast stop (stun)" },      -- Intimidation
    [853]    = { category = "stun", class = "PALADIN", label = "Cast stop (stun)" },     -- Hammer of Justice
    [1833]   = { category = "stun", class = "ROGUE", label = "Cast stop (stun)" },       -- Cheap Shot
    [408]    = { category = "stun", class = "ROGUE", label = "Cast stop (stun)" },       -- Kidney Shot
    [107570] = { category = "stun", class = "WARRIOR", label = "Cast stop (stun)" },     -- Storm Bolt
}

local nameplateUnits = {}
local lastEvaluation = 0
local cooldownElapsed = 0

-- Cast start/end is ordinary control flow, but notInterruptible may be a
-- secret boolean in combat. Return it untouched; the renderer passes it to
-- Region:SetAlphaFromBoolean and Lua never tests or negates it.
local function ReadCast(unit)
    if not UnitExists(unit) or UnitIsFriend("player", unit) then return nil end

    local name, notInterruptible
    name, _, _, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
    if type(name) == "nil" then
        name, _, _, _, _, _, notInterruptible = UnitChannelInfo(unit)
    end
    if type(name) == "nil" then return nil end
    return { unit = unit, notInterruptible = notInterruptible }
end

local function CollectCasts()
    local result = {}
    local targetCast = ReadCast("target")
    if targetCast then result[#result + 1] = targetCast end
    if IH.db.mode == "TARGET" then return result end

    for unit in pairs(nameplateUnits) do
        if not UnitIsUnit(unit, "target") then
            local cast = ReadCast(unit)
            if cast then result[#result + 1] = cast end
        end
    end
    return result
end

function IH:FindPlayerInterrupt()
    for spellID in pairs(INTERRUPTS) do
        if IsPlayerSpell(spellID) then return spellID end
    end
end

local function UpdateCooldownTicker(hasCasts)
    local frame = IH.detectionFrame
    if not frame then return end
    if hasCasts then
        frame:SetScript("OnUpdate", function(_, elapsed)
            cooldownElapsed = cooldownElapsed + elapsed
            if cooldownElapsed < 0.20 then return end
            cooldownElapsed = 0
            IH:Evaluate(true)
        end)
    else
        cooldownElapsed = 0
        frame:SetScript("OnUpdate", nil)
    end
end

function IH:Evaluate(force)
    if not self.db or not self.rendererReady then return end
    local now = GetTime()
    if not force and now - lastEvaluation < 0.05 then return end
    lastEvaluation = now

    if self:IsTestOverrideActive() then
        UpdateCooldownTicker(false)
        self:ShowTestButtons()
        return
    end
    if not self.db.enabled then
        UpdateCooldownTicker(false)
        self:HideAllGlows()
        return
    end

    local casts = CollectCasts()
    local spellID = self:FindPlayerInterrupt()
    if #casts > 0 and spellID then
        -- Cooldown readiness and notInterruptible remain renderer-owned alpha
        -- gates. Their possibly secret booleans are never inspected here.
        self:ShowForSpell(spellID, casts)
        UpdateCooldownTicker(true)
    else
        UpdateCooldownTicker(false)
        self:HideAllGlows()
    end
end

function IH:InitializeDetection()
    local frame = CreateFrame("Frame")
    self.detectionFrame = frame
    local events = {
        "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
        "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "ACTIONBAR_SLOT_CHANGED",
        "ACTIONBAR_PAGE_CHANGED", "SPELLS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
        "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
        "UPDATE_BINDINGS", "UPDATE_MACROS", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    }
    -- Talent event names vary across Retail revisions; unsupported names are
    -- harmless while SPELLS_CHANGED remains the universal refresh path.
    for _, event in ipairs(events) do pcall(frame.RegisterEvent, frame, event) end
    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" and unit then nameplateUnits[unit] = true
        elseif event == "NAME_PLATE_UNIT_REMOVED" and unit then nameplateUnits[unit] = nil
        elseif event == "UPDATE_MACROS" then
            IH:ScheduleMacroStateRefresh()
        elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED"
            or event == "SPELLS_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED"
            or event == "UPDATE_BINDINGS" then
            if event == "SPELLS_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED"
                or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
                IH:RefreshMacroCandidates()
            end
            IH:RefreshButtonCache()
            if IH.RefreshCooldownManagerCache then IH:RefreshCooldownManagerCache() end
            IH:ScheduleRecoveryScan(event)
        elseif event == "PLAYER_ENTERING_WORLD" then
            IH:RefreshMacroCandidates()
            if IH.RefreshCooldownManagerCache then IH:RefreshCooldownManagerCache() end
            IH:ScheduleRecoveryScan(event)
        elseif event == "PLAYER_REGEN_DISABLED" then
            if #(IH.interruptRecords or {}) == 0 and not IH.firstCombatRecoveryRequested then
                IH.firstCombatRecoveryRequested = true
                IH.recoveryScanDeferred = true
                IH.recoveryScanReason = event
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            IH:RunQueuedButtonScan()
            if IH.startupFullScanPending then IH:PerformStartupScan() end
            if IH.ResumeCooldownManagerRefresh then IH:ResumeCooldownManagerRefresh() end
            IH:ResumeDeferredRecoveryScan()
        end
        IH:Evaluate(true)
    end)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates(false)) do
            if plate.namePlateUnitToken then nameplateUnits[plate.namePlateUnitToken] = true end
        end
    end
    self:Evaluate(true)
end

IH._DetectionTestHooks = {
    ReadCast = ReadCast,
    CollectCasts = CollectCasts,
    AddNameplate = function(unit) nameplateUnits[unit] = true end,
    RemoveNameplate = function(unit) nameplateUnits[unit] = nil end,
    Reset = function() wipe(nameplateUnits); cooldownElapsed = 0 end,
}
