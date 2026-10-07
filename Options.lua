local _, IH = ...

local function MakeCheckbox(parent, label, x, y, getter, setter)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetPoint("TOPLEFT", x, y); box.Text:SetText(label)
    box:SetScript("OnShow", function(self) self:SetChecked(getter()) end)
    box:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    return box
end

local function AddTooltip(frame, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Interrupt Highlight")
        GameTooltip:AddLine(type(text) == "function" and text() or text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MakeSlider(parent, name, label, description, x, y, low, high, step, getter, setter)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", x, y); title:SetText(label)
    local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3); note:SetText(description)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 4, -12); slider:SetWidth(260)
    slider:SetMinMaxValues(low, high); slider:SetValueStep(step); slider:SetObeyStepOnDrag(true)
    _G[name .. "Low"]:SetText(low .. "%"); _G[name .. "High"]:SetText(high .. "%")
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        _G[name .. "Text"]:SetText(value .. "%")
        if not self.settingValue then setter(value) end
    end)
    slider.settingValue = true; slider:SetValue(getter()); slider.settingValue = false
    slider:SetScript("OnShow", function(self)
        self.settingValue = true; self:SetValue(getter()); self.settingValue = false
    end)
end

local function MakeDropdown(parent, label, x, y, values, getter, setter)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", x, y); title:SetText(label)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6); dropdown:SetWidth(260)
    dropdown:SetupMenu(function(_, root)
        for _, item in ipairs(values) do
            root:CreateRadio(item[2], function() return getter() == item[1] end, function() setter(item[1]) end)
        end
    end)
end

local function CreateAbilityRow(parent, index, description)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(540, 54); row:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16 - (index - 1) * 58)
    local icon = CreateFrame("Button", nil, row)
    icon:SetSize(40, 40); icon:SetPoint("TOPLEFT", 0, -2); icon:RegisterForDrag("LeftButton")
    icon.texture = icon:CreateTexture(nil, "ARTWORK"); icon.texture:SetAllPoints()
    local name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2); name:SetWidth(250); name:SetJustifyH("LEFT")
    local note = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5); note:SetWidth(330); note:SetJustifyH("LEFT")
    local action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    action:SetPoint("TOPRIGHT", -2, -6); action:SetSize(160, 24)
    row.icon, row.nameText, row.note, row.action = icon, name, note, action
    return row
end

function IH:InitializeOptions()
    local panel = CreateFrame("Frame", "InterruptHighlightOptionsPanel", UIParent)
    panel.name = "Interrupt Highlight"; self.optionsPanel = panel
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8); scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(580, 720)
    scroll:SetScrollChild(content); self.optionsContent = content

    local heading = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -16); heading:SetText("Interrupt Highlight")
    local version = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    version:SetPoint("LEFT", heading, "RIGHT", 10, 0); version:SetText(self.version)
    MakeCheckbox(content, "Enable highlighting", 16, -55, function() return IH.db.enabled end, function(v) IH:SetEnabled(v) end)
    local detectionHeading = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    detectionHeading:SetPoint("TOPLEFT", 16, -85); detectionHeading:SetText("Detection")
    MakeDropdown(content, "Enemies to watch", 16, -112, {
        { "TARGET", "Target only" }, { "ALL", "All visible enemies" },
    }, function() return IH.db.mode end, function(v) IH:SetMode(v) end)
    local range = MakeCheckbox(content, "Only in range", 16, -180,
        function() return IH.db.onlyInRange end, function(v) IH:SetOnlyInRange(v) end)
    AddTooltip(range, "Highlight only when your interrupt spell is in range of the casting enemy.")
    local cooldownManager = MakeCheckbox(content, "Highlight Cooldown Manager", 300, -180,
        function() return IH.db.highlightCooldownManager end,
        function(v) IH:SetHighlightCooldownManager(v) end)
    AddTooltip(cooldownManager, "Highlight true interrupt abilities shown in Blizzard's Cooldown Manager.")

    local glowHeading = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    glowHeading:SetPoint("TOPLEFT", 16, -215); glowHeading:SetText("Glow")
    local styles = {}; for key, name in pairs(self.styles) do styles[#styles + 1] = { key, name } end
    table.sort(styles, function(a, b) return a[2] < b[2] end)
    MakeDropdown(content, "Glow style", 16, -242, styles, function() return IH.db.style end, function(v) IH:SetStyle(v) end)

    local colorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    colorLabel:SetPoint("TOPLEFT", 16, -315); colorLabel:SetText("Glow color")
    local color = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    color:SetPoint("TOPLEFT", 16, -335); color:SetSize(140, 24); color:SetText("Choose color")
    color:SetScript("OnClick", function()
        local old = { r = IH.db.color.r, g = IH.db.color.g, b = IH.db.color.b }
        ColorPickerFrame:SetupColorPickerAndShow({ r = old.r, g = old.g, b = old.b,
            swatchFunc = function() IH:SetColor(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function() IH:SetColor(old.r, old.g, old.b) end })
    end)
    local swatchBorder = content:CreateTexture(nil, "BORDER")
    swatchBorder:SetPoint("LEFT", color, "RIGHT", 10, 0); swatchBorder:SetSize(24, 24)
    swatchBorder:SetColorTexture(0.12, 0.12, 0.12, 1)
    local swatch = content:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", swatchBorder, "TOPLEFT", 2, -2)
    swatch:SetPoint("BOTTOMRIGHT", swatchBorder, "BOTTOMRIGHT", -2, 2)
    self.colorSwatch = swatch
    function self:UpdateColorSwatch()
        local c = self.db and self.db.color or self.defaults.color; swatch:SetColorTexture(c.r, c.g, c.b, 1)
    end
    self:UpdateColorSwatch()
    local colorNote = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    colorNote:SetPoint("LEFT", swatchBorder, "RIGHT", 8, 0); colorNote:SetText("Tint supported by all included styles")
    MakeSlider(content, "InterruptHighlightGlowSizeSlider", "Glow size",
        "Changes how far the glow extends around the action button.", 16, -380, 0, 150, 1,
        function() return math.floor((IH.db.glowScale or 1) * 100 + 0.5) end,
        function(value) IH:SetGlowScale(value / 100) end)

    local test = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    test:SetPoint("TOPLEFT", 16, -460); test:SetSize(140, 24); test:SetText("Test glow")
    test:SetScript("OnClick", function() IH:TestGlow() end)
    local scanHeading = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    scanHeading:SetPoint("TOPLEFT", 16, -500); scanHeading:SetText("Action bar scan")
    local scan = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    scan:SetPoint("TOPLEFT", 16, -522); scan:SetSize(140, 24); scan:SetText("Scan action bars")
    scan:SetScript("OnClick", function() IH:RequestFullButtonScan(true) end)
    local scanStatus = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scanStatus:SetPoint("LEFT", scan, "RIGHT", 12, 0); scanStatus:SetJustifyH("LEFT"); self.scanStatus = scanStatus

    local abilitiesHeading = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    abilitiesHeading:SetPoint("TOPLEFT", 16, -570); abilitiesHeading:SetText("Detected interrupt / cast-stop abilities")
    local macroHeading = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    macroHeading:SetPoint("TOPLEFT", abilitiesHeading, "BOTTOMLEFT", 0, -12)
    macroHeading:SetText("Generated focus macros")
    local macroDescription = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    macroDescription:SetPoint("TOPLEFT", macroHeading, "BOTTOMLEFT", 0, -5)
    macroDescription:SetWidth(540); macroDescription:SetJustifyH("LEFT"); macroDescription:SetWordWrap(true)
    macroDescription:SetText("The generated macro first casts the ability on a valid hostile Focus target. If no valid Focus exists, it temporarily uses Focus to remember your current target, selects an enemy, casts the interrupt or stun, restores your previous target, clears the temporary Focus, and resumes auto-attack.")
    local empty = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", macroDescription, "BOTTOMLEFT", 0, -16); empty:SetText("No interrupt abilities detected yet."); self.abilitiesEmpty = empty
    self.abilityRows = {}
    function self:RefreshMacroRows()
        if not self.optionsContent then return end
        local abilities = self:BuildDetectedAbilities()
        for index, ability in ipairs(abilities) do
            local row = self.abilityRows[index] or CreateAbilityRow(content, index, macroDescription)
            self.abilityRows[index] = row; row:Show(); row.ability = ability
            row.icon.texture:SetTexture(ability.icon); row.nameText:SetText(ability.name)
            local state = self:GetGeneratedMacroState(ability)
            local kindNote = ability.kind == "castStop" and ((ability.label or "Cast stop") .. ". ") or "True interrupt. "
            if state == "READY" then
                row.action:SetText("Refresh macro"); row.action:Enable()
                row.note:SetText(kindNote .. "Macro ready. Drag the icon to an action bar.")
            elseif state == "UPDATE" then
                row.action:SetText("Update macro"); row.action:Enable()
                row.note:SetText(kindNote .. "Update the Interrupt Highlight macro template.")
            elseif state == "MODIFIED" then
                row.action:SetText("Restore generated macro"); row.action:Enable()
                row.note:SetText(kindNote .. "Macro modified. Restore replaces this macro's current contents.")
            else
                row.action:SetText("Create macro"); row.action:Enable()
                row.note:SetText(kindNote .. "Create a focus macro for this ability.")
            end
            row.action:SetScript("OnClick", function()
                local currentState = IH:GetGeneratedMacroState(row.ability)
                if currentState == "READY" then
                    IH:RefreshGeneratedMacro(row.ability)
                elseif currentState == "MODIFIED" then
                    IH:RestoreGeneratedMacro(row.ability)
                else
                    IH:CreateOrUpdateGeneratedMacro(row.ability)
                end
            end)
            AddTooltip(row.action, function()
                local currentState = IH:GetGeneratedMacroState(row.ability)
                if currentState == "READY" then
                    return "Reapply the current Interrupt Highlight template and icon to this macro. The macro remains on your action bar."
                elseif currentState == "MODIFIED" then
                    return "This will replace the current contents of " .. row.ability.name ..
                        "'s confirmed Interrupt Highlight macro with the generated template."
                end
                if currentState ~= "UPDATE" then
                    return "Creates a character-specific focus macro. It prioritizes a valid hostile Focus target and can temporarily use Focus to restore your previous target."
                end
                return "Create or update the generated Interrupt Highlight macro."
            end)
            row.icon:SetScript("OnDragStart", function() IH:PickupGeneratedMacro(row.ability) end)
            AddTooltip(row.icon, function()
                return IH:GetGeneratedMacroState(row.ability) == "READY"
                    and "Drag this icon to an action bar to place the generated macro."
                    or "Create the macro first, then drag this icon to an action bar."
            end)
        end
        for index = #abilities + 1, #self.abilityRows do self.abilityRows[index]:Hide() end
        empty:SetShown(#abilities == 0); content:SetHeight(math.max(720, 660 + macroDescription:GetStringHeight() + #abilities * 58))
    end
    self.RefreshDetectedAbilities = self.RefreshMacroRows
    function self:UpdateScanStatus()
        local records = self.interruptRecords or {}; local abilities = self.detectedAbilities or {}
        local castStops = #(self.spellbookCastStopRecords or {})
        scanStatus:SetText(("Detected: %d action buttons, %d true interrupt%s, %d cooldown-manager interrupt icon%s, %d spellbook cast-stop%s, %d unique abilit%s\nCDM: %s; cache: %d; refresh: %s; secret items skipped: %d\nStartup: guaranteed scan: %s; recovery: %d; pending: %s"):format(
            self.cachedActionButtons or 0, #records, #records == 1 and "" or "s",
            self.cooldownManagerInterruptIcons or 0, self.cooldownManagerInterruptIcons == 1 and "" or "s",
            castStops, castStops == 1 and "" or "s", #abilities, #abilities == 1 and "y" or "ies",
            self.cooldownManagerEnabled and "enabled" or "disabled",
            self.cooldownManagerInterruptIcons or 0,
            self.cooldownManagerRefreshPending and "pending-combat" or "ready",
            self.cooldownManagerSecretItemsSkipped or 0,
            self.startupFullScanDone and "done" or "pending", self.recoveryScanCount or 0,
            (self.startupFullScanPending or self.recoveryScanPending or self.recoveryScanDeferred) and "yes" or "no"))
        self:RefreshMacroRows()
    end
    panel:SetScript("OnShow", function() IH:UpdateScanStatus() end); self:UpdateScanStatus()
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category); self.settingsCategory = category
end
