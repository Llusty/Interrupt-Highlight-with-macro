local _, IH = ...

local function Position(button)
    local angle = math.rad(IH.db.minimap.angle or 220)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

function IH:InitializeMinimap()
    local button = CreateFrame("Button", "InterruptHighlightMinimapButton", Minimap)
    button:SetSize(32, 32); button:SetFrameStrata("MEDIUM"); button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background"); background:SetSize(24, 24); background:SetPoint("CENTER")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\InterruptHighlight\\Media\\icon"); icon:SetSize(20, 20); icon:SetPoint("CENTER")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(54, 54); border:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then IH:SetEnabled(not IH.db.enabled) else IH:OpenOptions() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Interrupt Highlight")
        GameTooltip:AddLine("Left-click: options", 1, 1, 1); GameTooltip:AddLine("Right-click: enable/disable", 1, 1, 1); GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter(); local scale = Minimap:GetEffectiveScale()
        local cx, cy = GetCursorPosition(); cx, cy = cx / scale, cy / scale
        IH.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)); Position(self)
    end) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    Position(button)
    if self.db.minimap.hide then button:Hide() end
    self.minimapButton = button
end
