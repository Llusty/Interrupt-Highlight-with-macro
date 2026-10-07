local _, IH = ...

local CURRENT_TEMPLATE_VERSION = 2
local additionalMacroCastStops = IH.additionalMacroCastStops or {
    [221562] = { category = "stun", class = "DEATHKNIGHT", label = "Cast stop (stun)" },
}
IH.additionalMacroCastStops = additionalMacroCastStops

local function SpellInfo(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, info.iconID end
    end
    if GetSpellInfo then local name, _, icon = GetSpellInfo(spellID); return name, icon end
end

-- Template versions share macro text; the newer version records ownership metadata.
local function TemplateV1(spellName)
    return ("#showtooltip %s\n/cast [@focus,exists,nodead,harm] %s\n/stopmacro [@focus,exists,nodead,harm]\n/focus target\n/cleartarget\n/targetenemy\n/cast %s\n/target focus\n/clearfocus\n/startattack"):format(spellName, spellName, spellName)
end
local templates = { [1] = TemplateV1, [2] = TemplateV1 }
local function DesiredBody(spellName) return templates[CURRENT_TEMPLATE_VERSION](spellName) end

local function BodySignature(body)
    local hash = 5381
    for index = 1, #body do hash = (hash * 33 + body:byte(index)) % 4294967296 end
    return ("%d:%08x"):format(#body, hash)
end

local function KnownTemplateVersion(spellName, body)
    for version = CURRENT_TEMPLATE_VERSION, 1, -1 do
        if body == templates[version](spellName) then return version end
    end
end

local function BodyLimit() return tonumber(MAX_MACRO_LENGTH) or 255 end
local function CharacterLimit() return tonumber(MAX_CHARACTER_MACROS) or 18 end

local function CurrentMacro(index)
    if not index or index <= 0 then return nil end
    local name, icon, body = GetMacroInfo(index)
    if name then return { index = index, name = name, icon = icon, body = body or "" } end
end

local function FindByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    return CurrentMacro(GetMacroIndexByName(name))
end

local function IsCharacterMacro(macro)
    local accountCount = GetNumMacros()
    return macro and macro.index > (tonumber(accountCount) or 0)
end

local function TechnicalNames(spellID)
    local names, maxLength = {}, tonumber(MAX_MACRO_NAME_LENGTH) or 16
    local base = ("IH" .. tostring(spellID)):sub(1, maxLength)
    names[#names + 1] = base
    for code = string.byte("A"), string.byte("Z") do
        names[#names + 1] = base:sub(1, maxLength - 1) .. string.char(code)
    end
    for number = 2, 99 do
        local suffix = tostring(number)
        names[#names + 1] = base:sub(1, maxLength - #suffix) .. suffix
    end
    return names
end

local function SaveOwnership(spellID, ability, macro, templateVersion, duplicateCount)
    local previous = IH.db.generatedMacros[spellID] or IH.db.generatedMacros[tostring(spellID)]
    IH.db.generatedMacros[tostring(spellID)] = nil
    IH.db.generatedMacros[spellID] = {
        name = macro.name, body = macro.body, bodySignature = BodySignature(macro.body),
        templateVersion = templateVersion,
        kind = ability and (ability.kind == "castStop" and "castStop" or "trueInterrupt") or
            (previous and previous.kind) or "trueInterrupt",
        duplicateCount = duplicateCount and duplicateCount > 1 and duplicateCount or nil,
    }
    return IH.db.generatedMacros[spellID]
end

local function ResolveOwned(spellID, spellName, ability)
    local records = IH.db and IH.db.generatedMacros
    if not records then return nil end
    local record = records[spellID] or records[tostring(spellID)]

    -- A recorded exact name is authoritative ownership history. Body changes
    -- produce MODIFIED; they do not revoke ownership or trigger a duplicate.
    if record and type(record.name) == "string" then
        local macro = FindByName(record.name)
        if IsCharacterMacro(macro) then
            if records[tostring(spellID)] and not records[spellID] then
                records[spellID], records[tostring(spellID)] = record, nil
            end
            return macro, record, record.duplicateCount
        end
    end

    -- Without a usable record, name alone is insufficient. Adopt only exact
    -- known generated bodies, in deterministic base/A-Z/2-99 order.
    local matches = {}
    for _, name in ipairs(TechnicalNames(spellID)) do
        local macro = FindByName(name)
        if IsCharacterMacro(macro) then
            local version = KnownTemplateVersion(spellName, macro.body)
            if version then matches[#matches + 1] = { macro = macro, version = version } end
        end
    end
    if #matches == 0 then return nil end
    local chosen = matches[1]
    record = SaveOwnership(spellID, ability, chosen.macro, chosen.version, #matches)
    return chosen.macro, record, #matches
end

local function SpellAvailable(spellID)
    return (IsPlayerSpell and IsPlayerSpell(spellID)) or (IsSpellKnown and IsSpellKnown(spellID)) or false
end

local function PositiveSpellID(value)
    value = tonumber(value)
    return value and value > 0 and value or nil
end

local function SpellBookPlayerBank()
    return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
end

local function SpellBookContains(spellID)
    local bank = SpellBookPlayerBank()
    if not spellID then return false end
    if not bank or not C_SpellBook or not C_SpellBook.IsSpellInSpellBook then
        return SpellAvailable(spellID)
    end
    local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, spellID, bank, true)
    return ok and known and true or false
end

local function FindMappedSpell(api, spellID)
    if not api then return nil end
    local ok, mapped = pcall(api, spellID)
    return ok and PositiveSpellID(mapped) or nil
end

local function ResolveCastStop(canonicalSpellID)
    canonicalSpellID = PositiveSpellID(canonicalSpellID)
    if not canonicalSpellID then return nil, false end

    local override = FindMappedSpell(C_Spell and C_Spell.GetOverrideSpell, canonicalSpellID)
    local bookOverride = FindMappedSpell(C_SpellBook and C_SpellBook.FindSpellOverrideByID, canonicalSpellID)
    local effectiveSpellID = override or bookOverride or canonicalSpellID
    local baseSpellID = FindMappedSpell(C_SpellBook and C_SpellBook.FindBaseSpellByID, effectiveSpellID)
    local known = SpellBookContains(canonicalSpellID) or SpellBookContains(effectiveSpellID)
        or SpellBookContains(bookOverride) or SpellBookContains(baseSpellID)
    return effectiveSpellID, known
end

function IH:RefreshMacroCandidates()
    local records = {}
    for canonicalSpellID, definition in pairs(additionalMacroCastStops) do
        local effectiveSpellID, known = ResolveCastStop(canonicalSpellID)
        local name, icon = SpellInfo(effectiveSpellID or canonicalSpellID)
        if known then
            records[#records + 1] = {
                spellID = canonicalSpellID, effectiveSpellID = effectiveSpellID or canonicalSpellID,
                name = name, icon = icon, castStopType = definition.category, label = definition.label,
                class = definition.class, spec = definition.spec,
            }
        end
        self.castStopDiagnostics = self.castStopDiagnostics or {}
        self.castStopDiagnostics[canonicalSpellID] = {
            known = known, effectiveSpellID = effectiveSpellID or canonicalSpellID, name = name,
        }
    end
    table.sort(records, function(a, b) return a.spellID < b.spellID end)
    self.spellbookCastStopRecords = records
    if self.BuildDetectedAbilities then self:BuildDetectedAbilities() end
    if self.RefreshMacroRows and self.optionsPanel and self.optionsPanel:IsShown() then
        self:RefreshMacroRows()
    end
    return records
end

-- Macro ownership is derived from the live macro API. Keep this path separate
-- from action-bar discovery so UPDATE_MACROS never causes a global frame scan.
function IH:RefreshMacroOwnershipStates()
    if self.BuildDetectedAbilities then self:BuildDetectedAbilities() end
    if self.RefreshMacroRows and self.optionsPanel and self.optionsPanel:IsShown() then
        self:RefreshMacroRows()
    end
end

function IH:ScheduleMacroStateRefresh()
    self.macroRefreshSerial = (self.macroRefreshSerial or 0) + 1
    local serial = self.macroRefreshSerial
    local refresh = function()
        if serial ~= IH.macroRefreshSerial then return end
        IH:RefreshMacroOwnershipStates()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.05, refresh) else refresh() end
end

function IH:GetOwnedGeneratedSpellForMacro(macroID)
    local macro = CurrentMacro(tonumber(macroID))
    if not macro then return nil end
    for rawSpellID in pairs(self.db and self.db.generatedMacros or {}) do
        local spellID = tonumber(rawSpellID)
        local effectiveSpellID = spellID and additionalMacroCastStops[spellID] and ResolveCastStop(spellID)
        local name = spellID and SpellInfo(effectiveSpellID or spellID)
        local owned = spellID and name and ResolveOwned(spellID, name)
        if owned and owned.index == macro.index then return spellID end
    end
end

local function TechnicalName(spellID)
    for _, name in ipairs(TechnicalNames(spellID)) do if not FindByName(name) then return name end end
end

local function MacroState(ability)
    local macro, record, duplicateCount = ResolveOwned(ability.spellID, ability.name, ability)
    if not macro then return "CREATE" end
    local wanted = DesiredBody(ability.name)
    local iconMatches = tostring(macro.icon or "") == tostring(ability.icon or "")
    if macro.body == wanted and iconMatches then
        SaveOwnership(ability.spellID, ability, macro, CURRENT_TEMPLATE_VERSION, duplicateCount)
        return "READY", macro, duplicateCount
    end
    if KnownTemplateVersion(ability.name, macro.body)
        or (type(record.body) == "string" and macro.body == record.body)
        or (type(record.bodySignature) == "string" and BodySignature(macro.body) == record.bodySignature) then
        return "UPDATE", macro, duplicateCount
    end
    return "MODIFIED", macro, duplicateCount
end

local function CombatBlocked()
    if InCombatLockdown and InCombatLockdown() then
        IH:Print("macro actions are unavailable during combat."); return true
    end
    return false
end

local function SaveEditedMacro(ability, index, expectedBody, duplicateCount)
    if not index then IH:Print("the macro could not be saved."); return false end
    local saved = CurrentMacro(index)
    if not saved or saved.body ~= expectedBody then
        IH:Print("the macro was not saved completely; ownership was not recorded."); return false
    end
    SaveOwnership(ability.spellID, ability, saved, CURRENT_TEMPLATE_VERSION, duplicateCount)
    IH:ScheduleMacroStateRefresh()
    return true
end

function IH:GetGeneratedMacroBody(spellName) return DesiredBody(spellName) end
function IH:GetGeneratedMacroState(ability) return MacroState(ability) end

function IH:RefreshGeneratedMacro(ability)
    if InCombatLockdown and InCombatLockdown() then
        self:Print("macros can only be refreshed outside combat.")
        return false
    end
    local state, macro, duplicateCount = MacroState(ability)
    if state ~= "READY" or not macro then
        self:Print("only a ready Interrupt Highlight macro can be refreshed.")
        return false
    end
    local body = DesiredBody(ability.name)
    if #body > BodyLimit() then return false end
    return SaveEditedMacro(ability,
        EditMacro(macro.index, macro.name, ability.icon, body, 1), body, duplicateCount)
end

function IH:CreateOrUpdateGeneratedMacro(ability)
    if CombatBlocked() then return false end
    local body = DesiredBody(ability.name)
    if #body > BodyLimit() then
        self:Print(("macro for %s is too long (%d/%d characters); it was not created."):format(ability.name, #body, BodyLimit()))
        return false
    end
    local state, macro, duplicateCount = MacroState(ability)
    if state == "READY" then
        self:ScheduleMacroStateRefresh()
        return true
    elseif state == "MODIFIED" then
        self:Print("this generated macro was modified; use Restore generated macro to replace its contents.")
        return false
    elseif state == "UPDATE" then
        return SaveEditedMacro(ability, EditMacro(macro.index, macro.name, ability.icon, body, 1), body, duplicateCount)
    end
    local _, characterCount = GetNumMacros()
    if (tonumber(characterCount) or 0) >= CharacterLimit() then
        self:Print("no free character macro slots."); return false
    end
    local name = TechnicalName(ability.spellID)
    if not name then self:Print("could not find a safe technical name for the generated macro."); return false end
    return SaveEditedMacro(ability, CreateMacro(name, ability.icon, body, true), body)
end

function IH:RestoreGeneratedMacro(ability)
    if CombatBlocked() then return false end
    local state, macro, duplicateCount = MacroState(ability)
    if state ~= "MODIFIED" or not macro then
        self:Print("only a confirmed, modified Interrupt Highlight macro can be restored."); return false
    end
    local body = DesiredBody(ability.name)
    if #body > BodyLimit() then return false end
    return SaveEditedMacro(ability, EditMacro(macro.index, macro.name, ability.icon, body, 1), body, duplicateCount)
end

function IH:PickupGeneratedMacro(ability)
    if CombatBlocked() then return false end
    local state, macro = MacroState(ability)
    if state ~= "READY" or not macro then
        self:Print("create or update the generated macro before dragging it."); return false
    end
    PickupMacro(macro.index); return true
end

function IH:BuildDetectedAbilities()
    local result, bySpell = {}, {}
    local function Add(spellID, slot, kind, label, effectiveSpellID, suppliedName, suppliedIcon)
        spellID = tonumber(spellID)
        if not spellID or bySpell[spellID] then return end
        effectiveSpellID = tonumber(effectiveSpellID) or spellID
        local name, spellIcon = suppliedName, suppliedIcon
        if not name then name, spellIcon = SpellInfo(effectiveSpellID) end
        if not name then return end
        local actionIcon = slot and GetActionTexture and GetActionTexture(slot)
        local ability = { spellID = spellID, name = name, icon = spellIcon or actionIcon or 134400,
            effectiveSpellID = effectiveSpellID, kind = kind or "trueInterrupt", label = label }
        bySpell[spellID] = ability; result[#result + 1] = ability
    end
    for _, record in ipairs(self.interruptRecords or {}) do Add(record.spellID, record.slot, "trueInterrupt") end
    for _, record in ipairs(self.spellbookCastStopRecords or {}) do
        local definition = additionalMacroCastStops[tonumber(record.spellID)]
        if definition then
            Add(record.spellID, nil, "castStop", record.label or definition.label,
                record.effectiveSpellID, record.name, record.icon)
        end
    end
    -- Cached action-bar metadata is only a supplementary source. It may
    -- contribute a row only after the same canonical spell is confirmed as
    -- known; it never replaces spellbook discovery.
    for _, record in ipairs(self.macroCandidateRecords or {}) do
        local spellID = tonumber(record.spellID)
        local definition = spellID and additionalMacroCastStops[spellID]
        local effectiveSpellID, known
        if definition then effectiveSpellID, known = ResolveCastStop(spellID) end
        if known then Add(spellID, record.slot, "castStop", record.label or definition.label, effectiveSpellID) end
    end
    for rawSpellID, record in pairs(self.db and self.db.generatedMacros or {}) do
        local spellID = tonumber(rawSpellID)
        local definition = spellID and additionalMacroCastStops[spellID]
        local effectiveSpellID, castStopKnown
        if definition then effectiveSpellID, castStopKnown = ResolveCastStop(spellID) end
        if spellID and (castStopKnown or (not definition and SpellAvailable(spellID))) then
            local kind = record.kind
            if kind ~= "castStop" and kind ~= "trueInterrupt" then
                kind = definition and "castStop" or "trueInterrupt"
            end
            Add(spellID, nil, kind, definition and definition.label, effectiveSpellID)
        end
    end
    table.sort(result, function(a, b)
        if a.kind ~= b.kind then return a.kind == "trueInterrupt" end
        return a.name < b.name
    end)
    self.detectedAbilities = result; return result
end

IH._MacroTestHooks = {
    DesiredBody = DesiredBody, BodySignature = BodySignature, KnownTemplateVersion = KnownTemplateVersion,
    ResolveOwned = ResolveOwned, ConfirmOwned = ResolveOwned, TechnicalName = TechnicalName,
    MacroState = MacroState, BodyLimit = BodyLimit, CharacterLimit = CharacterLimit,
    SpellAvailable = SpellAvailable, ResolveCastStop = ResolveCastStop,
    SpellBookContains = SpellBookContains, CurrentTemplateVersion = CURRENT_TEMPLATE_VERSION,
}
