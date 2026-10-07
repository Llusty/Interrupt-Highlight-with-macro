local ADDON_NAME, IH = ...

IH.name = ADDON_NAME
IH.version = "1.0.0"
IH.startupScanScheduled = false
IH.startupScanDone = false
IH.startupScanAttempts = 0
IH.startupScanPending = false
IH.startupFullScanDone = false
IH.startupFullScanPending = false
IH.recoveryScanCount = 0
IH.recoveryScanPending = false
IH.recoveryScanDeferred = false
IH.firstCombatRecoveryRequested = false
IH.defaults = {
    enabled = true,
    mode = "ALL",
    onlyInRange = false,
    highlightCooldownManager = true,
    style = "MODERN",
    glowScale = 1.0,
    generatedMacros = {},
    color = { r = 0.15, g = 0.75, b = 1.0 },
    minimap = { hide = false, angle = 220 },
}

local function CopyDefaults(source, destination)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(destination[key]) ~= "table" then destination[key] = {} end
            CopyDefaults(value, destination[key])
        elseif destination[key] == nil then
            destination[key] = value
        end
    end
end

function IH:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff55d6ffInterrupt Highlight:|r " .. message)
end

function IH:SetEnabled(enabled)
    self.db.enabled = enabled and true or false
    if self.Evaluate then self:Evaluate(true) end
end

function IH:SetMode(mode)
    self.db.mode = mode == "TARGET" and "TARGET" or "ALL"
    if self.Evaluate then self:Evaluate(true) end
end

function IH:SetOnlyInRange(enabled)
    self.db.onlyInRange = enabled and true or false
    self:Evaluate(true)
end

function IH:SetHighlightCooldownManager(enabled)
    self.db.highlightCooldownManager = enabled and true or false
    if self.RefreshCooldownManagerCache then self:RefreshCooldownManagerCache() end
    if self.HideAllGlows then self:HideAllGlows() end
    self:Evaluate(true)
end

function IH:SetStyle(style)
    if style == "INTERRUPT" then style = "MODERN" end
    if not self.styles[style] then return end
    self.db.style = style
    self:HideAllGlows()
    self:Evaluate(true)
end

function IH:SetGlowScale(scale)
    scale = tonumber(scale) or 1
    self.db.glowScale = math.max(0, math.min(1.5, scale))
    if self.RefreshGlowGeometry then self:RefreshGlowGeometry() end
    self:Evaluate(true)
end

function IH:SetColor(r, g, b)
    self.db.color.r = math.max(0, math.min(1, tonumber(r) or 1))
    self.db.color.g = math.max(0, math.min(1, tonumber(g) or 1))
    self.db.color.b = math.max(0, math.min(1, tonumber(b) or 1))
    if self.UpdateColorSwatch then self:UpdateColorSwatch() end
    self:HideAllGlows()
    self:Evaluate(true)
end

function IH:OpenOptions()
    if Settings and Settings.OpenToCategory and self.settingsCategory then
        Settings.OpenToCategory(self.settingsCategory:GetID())
    else
        self.optionsPanel:Show()
    end
end

local RECOVERY_SCAN_DELAY = 1.5

local function HasCachedInterrupt()
    return #(IH.interruptRecords or {}) > 0
end

function IH:PerformStartupScan()
    if self.startupFullScanDone then return end
    if InCombatLockdown and InCombatLockdown() then
        self.startupScanPending = true
        self.startupFullScanPending = true
        if self.UpdateScanStatus then self:UpdateScanStatus() end
        return
    end
    if not self:RequestFullButtonScan(false) then
        self.startupScanPending = true
        self.startupFullScanPending = true
        return
    end

    self.startupScanPending = false
    self.startupFullScanPending = false
    self.startupFullScanDone = true
    self.startupScanDone = true
    self.startupScanAttempts = 1
    local interrupts = #(self.interruptRecords or {})
    local firstSetup = not self.db.initialScanDone
    if firstSetup then
        self.db.initialScanDone = true
        self:Print(("scan complete — %d action buttons, %d interrupts."):format(
            self.cachedActionButtons or 0, interrupts))
    end

    self.recoveryScanDeferred = false
    if interrupts == 0 then
        self:Print("no interrupt action found. Place your interrupt on an action bar, then use /ih scan or Scan action bars in settings.")
    end
    if self.RefreshMacroCandidates then self:RefreshMacroCandidates() end
    if self.RefreshCooldownManagerCache then self:RefreshCooldownManagerCache() end
    if self.Evaluate then self:Evaluate(true) end
    if self.UpdateScanStatus then self:UpdateScanStatus() end
end

function IH:PerformRecoveryScan()
    self.recoveryScanPending = false
    if HasCachedInterrupt() then
        self.recoveryScanDeferred = false
        if self.UpdateScanStatus then self:UpdateScanStatus() end
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        self.recoveryScanDeferred = true
        if self.UpdateScanStatus then self:UpdateScanStatus() end
        return
    end

    self.recoveryScanDeferred = false
    -- Lifecycle recovery is cache-only. Global frame enumeration is reserved
    -- for the guaranteed startup pass and explicit user scans.
    self:RefreshButtonCache()
    if self.RefreshCooldownManagerCache then self:RefreshCooldownManagerCache() end
    if HasCachedInterrupt() then self:Evaluate(true) end
    if self.UpdateScanStatus then self:UpdateScanStatus() end
end

function IH:ScheduleRecoveryScan(reason)
    if HasCachedInterrupt() or self.recoveryScanPending then return false end
    -- Startup owns discovery through its final bounded attempt. Events during
    -- that window are covered by the next scheduled startup scan.
    if not self.startupScanDone then
        self.recoveryScanDeferred = true
        self.recoveryScanReason = reason
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        self.recoveryScanDeferred = true
        self.recoveryScanReason = reason
        if self.UpdateScanStatus then self:UpdateScanStatus() end
        return true
    end
    self.recoveryScanPending = true
    self.recoveryScanReason = reason
    C_Timer.After(RECOVERY_SCAN_DELAY, function() IH:PerformRecoveryScan() end)
    if self.UpdateScanStatus then self:UpdateScanStatus() end
    return true
end

function IH:ResumeDeferredRecoveryScan()
    if not self.recoveryScanDeferred then return end
    self.recoveryScanDeferred = false
    self:ScheduleRecoveryScan(self.recoveryScanReason or "PLAYER_REGEN_ENABLED")
end

function IH:ScheduleStartupScan()
    if self.startupScanScheduled then return end
    self.startupScanScheduled = true
    C_Timer.After(4.5, function() IH:PerformStartupScan() end)
end

SLASH_INTERRUPTHIGHLIGHT1 = "/ih"
SLASH_INTERRUPTHIGHLIGHT2 = "/interrupthighlight"
SlashCmdList.INTERRUPTHIGHLIGHT = function(input)
    input = (input or ""):lower():match("^%s*(.-)%s*$")
    if input == "on" then
        IH:SetEnabled(true)
        IH:Print("enabled")
    elseif input == "off" then
        IH:SetEnabled(false)
        IH:Print("disabled")
    elseif input == "test" then
        IH:TestGlow()
    elseif input == "scan" then
        IH:RefreshMacroCandidates()
        IH:RequestFullButtonScan(true)
        IH:RefreshCooldownManagerCache()
        IH:Evaluate(true)
    elseif input == "status" then
        IH:RefreshMacroCandidates()
        IH:RefreshButtonCache()
        IH:RefreshCooldownManagerCache()
        IH:RendererStatus()
    elseif input == "reset" then
        wipe(IH.db)
        CopyDefaults(IH.defaults, IH.db)
        IH:UpdateColorSwatch()
        if IH.RefreshGlowGeometry then IH:RefreshGlowGeometry() end
        IH:HideAllGlows()
        IH:Evaluate(true)
        IH:Print("settings reset")
    elseif input:match("^color%s+") then
        local r, g, b = input:match("^color%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)$")
        if r then
            IH:SetColor(r, g, b)
            IH:Print(("color set to %.2f %.2f %.2f"):format(IH.db.color.r, IH.db.color.g, IH.db.color.b))
        else
            IH:Print("usage: /ih color R G B (values from 0 to 1)")
        end
    else
        IH:OpenOptions()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InterruptHighlightDB = InterruptHighlightDB or {}
        CopyDefaults(IH.defaults, InterruptHighlightDB)
        IH.db = InterruptHighlightDB
        IH.db.debug = nil -- Retire persisted development logging settings.
        if type(IH.db.generatedMacros) ~= "table" then IH.db.generatedMacros = {} end
        if IH.db.style == "INTERRUPT" then IH.db.style = "MODERN" end
        IH:InitializeOptions()
        IH:InitializeMinimap()
    elseif event == "PLAYER_LOGIN" then
        IH:InitializeRenderer()
        IH:InitializeDetection()
        if IH.InitializeCooldownManager then IH:InitializeCooldownManager() end
        IH:ScheduleStartupScan()
    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_CooldownViewer" then
        if IH.OnCooldownViewerLoaded then IH:OnCooldownViewerLoaded() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        IH:ScheduleStartupScan()
    end
end)
