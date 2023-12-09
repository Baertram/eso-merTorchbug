local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")

local strformat = string.format
local strsub = string.sub
local strfind = string.find
local strlen = string.len

local tos = tostring
local ton = tonumber
local tins = table.insert
local trem = table.remove

local EM = EVENT_MANAGER


local constantsSplitSepparator = "_"
local noSoundValue             = SOUNDS["NONE"]
local globalInspectorDialogTabKey = tbug.panelNames[10].key --"dialogs"

local isSplittableString = tbug.isSplittableString
local findUpperCaseCharsAndReturnOffsetsTab = tbug.findUpperCaseCharsAndReturnOffsetsTab

local tbug_slashCommand = tbug.slashCommand
local tbug_slashCommandSCENEMANAGER = tbug.slashCommandSCENEMANAGER



local DEFAULT_SCALE_PERCENT = 180
local function GetKeyOrTexture(keyCode, textureOptions, scalePercent, useDisabledIcon)
    if textureOptions == KEYBIND_TEXTURE_OPTIONS_EMBED_MARKUP then
        if ZO_Keybindings_ShouldUseIconKeyMarkup(keyCode) then
            return ZO_Keybindings_GenerateIconKeyMarkup(keyCode, scalePercent or DEFAULT_SCALE_PERCENT, useDisabledIcon)
        end
        return ZO_Keybindings_GenerateTextKeyMarkup(GetKeyName(keyCode))
    else
        return GetKeyName(keyCode)
    end
end
local keyShiftStr = GetKeyOrTexture(KEY_SHIFT, KEYBIND_TEXTURE_OPTIONS_EMBED_MARKUP, 100, false)
local keyShiftAndLMBRMB = keyShiftStr .. "+|t100.000000%:100.000000%:/esoui/art/miscellaneous/icon_lmbrmb.dds|t"

local getterOrSetterStr = "%s()"
local getterOrSetterWithControlStr = "%s:%s()"

local checkForSpecialDataEntryAsKey = tbug.checkForSpecialDataEntryAsKey

local DEFAULT_TEXT_COLOR = ZO_ColorDef:New(GetInterfaceColor(INTERFACE_COLOR_TYPE_TEXT_COLORS, INTERFACE_TEXT_COLOR_NORMAL))
local DEFAULT_TEXT_HIGHLIGHT = ZO_ColorDef:New(GetInterfaceColor(INTERFACE_COLOR_TYPE_TEXT_COLORS, INTERFACE_TEXT_COLOR_CONTEXT_HIGHLIGHT))
local DISABLED_TEXT_COLOR = ZO_ColorDef:New(GetInterfaceColor(INTERFACE_COLOR_TYPE_TEXT_COLORS, INTERFACE_TEXT_COLOR_DISABLED))

local eventsInspector
local tbug_checkIfInspectorPanelIsShown = tbug.checkIfInspectorPanelIsShown
local tbug_refreshInspectorPanel = tbug.refreshInspectorPanel
local clickToIncludeAgainStr = " (Click to include)"

local tbug_endsWith = tbug.endsWith
local customKeysForInspectorRows = tbug.customKeysForInspectorRows
local customKey__Object = customKeysForInspectorRows.object

local RT = tbug.RT
local rtSpecialReturnValues = tbug.RTSpecialReturnValues
local localizationStringKeyText = rtSpecialReturnValues[RT.LOCAL_STRING]
local globalInspector

local setDrawLevel = tbug.SetDrawLevel
local cleanTitle = tbug.CleanTitle
local getRelevantNameForCall = tbug.getRelevantNameForCall

--======================================================================================================================
--= CONTEXT MENU FUNCTIONS                                                                                     -v-
--======================================================================================================================

local function addTextToChat(textToAdd, getName)
    if getName == true then
        textToAdd = getRelevantNameForCall(textToAdd)
    end
    StartChatInput(textToAdd, CHAT_CHANNEL_SAY, nil)
end

------------------------------------------------------------------------------------------------------------------------
--CONTEXT MENU -> INSPECTOR ROW edit FIELD VALUE
--LibCustomMenu custom context menu "OnClick" handling function for inspector row context menu entries
function tbug.setEditValueFromContextMenu(p_self, p_row, p_data, p_oldValue)
--df("tbug:setEditValueFromContextMenu - newValue: " ..tos(p_data.value) .. ", oldValue: " ..tos(p_oldValue))
    if p_self then
        local editBox = p_self.editBox
        if editBox then
            local currentVal = p_data.value
            if p_row and p_data and p_oldValue ~= nil and p_oldValue ~= currentVal then
                p_self.editData = p_data
                local newVal
                if currentVal == nil then
                    newVal = "nil"
                else
                    newVal = tos(currentVal)
                end
                editBox:SetText(newVal)
                p_row.cVal:SetText(newVal)
            end
            if editBox.panel and editBox.panel.valueEditConfirm then
                editBox.panel:valueEditConfirm(editBox)
            end
        end
    end
    ClearMenu()
end
local setEditValueFromContextMenu = tbug.setEditValueFromContextMenu

------------------------------------------------------------------------------------------------------------------------
--CONTEXT MENU -> CHAT EDIT BOX
--Set the chat's edit box text from a context menu entry
function tbug.setChatEditTextFromContextMenu(p_self, p_row, p_data, copyRawData, copySpecialFuncStr, isKey, isItemLinkSpecialFunc)
--d("[tbug]setChatEditTextFromContextMenu - copySpecialFuncStr: " ..tos(copySpecialFuncStr) .. ", isItemLinkSpecialFunc: " ..tos(isItemLinkSpecialFunc))
    copyRawData = copyRawData or false
    isItemLinkSpecialFunc = isItemLinkSpecialFunc or false
    isKey = isKey or false
    if p_self and p_row and p_data then
        local controlOfInspectorRow = p_self.subject
        local key = p_data.key
        local value = p_data.value
        local prop = p_data.prop
        local dataPropOrKey = (prop ~= nil and prop.name) or key
        local getterName = (prop ~= nil and (prop.getOrig or prop.get))
        local setterName = (prop ~= nil and (prop.setOrig or prop.set))
        local dataEntry = p_data.dataEntry or p_data
        local dataTypeId = dataEntry and dataEntry.typeId

        --For special function strings
        local bagId, slotIndex
        local isBagOrSlotIndex = false
        local itemLink

        --For the editBox text
        local chatMessageText

        --Copy only raw data?
        if copyRawData == true then
            local valueToCopy = value
            --Copy raw value?
            if not isKey then
                local valueType = type(value)
                if valueType == "userdata" then
                    --Get name of the "userdata" from global table _G
                    local objectName = tbug.glookup(value)
                    if objectName ~= nil and objectName ~= "" and objectName ~= value then
                        valueToCopy = objectName
                    end
                else
                    if dataTypeId == RT.SAVEDINSPECTORS_TABLE then
                        valueToCopy = p_data.tooltipLine
                    end
                end
            end
            chatMessageText = (isKey == true and tos(checkForSpecialDataEntryAsKey(p_data))) or tos(valueToCopy)
        else
            --Check the row's key value (prop.name)
            if dataPropOrKey then
                --Do not use the masterlist as it is not sorted for the non-control insepctor (e.g. table inspector)
                if dataPropOrKey == "bagId" then
                    isBagOrSlotIndex = true
                    bagId = value
                    --Get the slotIndex of the control
                    slotIndex = tbug.getPropOfControlAtIndex(p_self.list.data, p_row.index+1, "slotIndex", true)
                elseif dataPropOrKey == "slotIndex" then
                    isBagOrSlotIndex = true
                    slotIndex = value
                    --Get the bagId of the control
                    bagId = tbug.getPropOfControlAtIndex(p_self.list.data, p_row.index-1, "bagId", true)
                elseif dataPropOrKey == "itemLink" then
                    itemLink = value
                elseif dataPropOrKey == "itemLink plain text" then
                    itemLink = value:gsub("%s+", "") --remove spaces in the possible plain text itemLink
                end
            end

--d(">isBagOrSlotIndex: " ..tostring(isBagOrSlotIndex))
            --Copy special strings
            if copySpecialFuncStr ~= nil and copySpecialFuncStr ~= "" then
                if isItemLinkSpecialFunc == true then
                    if isBagOrSlotIndex == true then
                        if bagId and slotIndex then
                            local itemLink = GetItemLink(bagId, slotIndex)
                            chatMessageText = "/tb " .. tos(copySpecialFuncStr) .. "('"..itemLink.."')"
                        end
                    end
                else
                    if copySpecialFuncStr == "itemlink" then
                        if isBagOrSlotIndex == true then
                            if bagId and slotIndex then
                                --local itemLink = GetItemLink(bagId, slotIndex)
                                chatMessageText = "/tb GetItemLink("..tos(bagId)..", "..tos(slotIndex)..")"
                            end
                        end
                    elseif copySpecialFuncStr == "itemname" then
                        if isBagOrSlotIndex == true then
                            if bagId and slotIndex then
                                local itemName = GetItemName(bagId, slotIndex)
                                if itemName and itemName ~= "" then
                                    itemName = ZO_CachedStrFormat("<<C:1>>", itemName)
                                end
                                chatMessageText = tos(itemName)
                            end
                        end
                    elseif copySpecialFuncStr == "special" then
                        if isBagOrSlotIndex == true then
                            if bagId and slotIndex then
                                chatMessageText = tos(bagId)..","..tos(slotIndex)
                            end
                        elseif itemLink ~= nil then
                            chatMessageText = "/tb GetItemLinkXXX('"..itemLink.."')"
                        end
                    elseif copySpecialFuncStr == "getterName" then
                        if getterName then chatMessageText = strformat(getterOrSetterStr, tos(getterName)) end
                    elseif copySpecialFuncStr == "setterName" then
                        if setterName then chatMessageText = strformat(getterOrSetterStr, tos(setterName)) end
                    elseif copySpecialFuncStr == "control:getter" then
                        if getterName then
                            local ctrlName = (controlOfInspectorRow.GetName and controlOfInspectorRow:GetName()) or "???"
                            chatMessageText = strformat(getterOrSetterWithControlStr, ctrlName, tos(getterName))
                        end
                    elseif copySpecialFuncStr == "control:setter" then
                        if setterName then
                            local ctrlName = (controlOfInspectorRow.GetName and controlOfInspectorRow:GetName()) or "???"
                            chatMessageText = strformat(getterOrSetterWithControlStr, ctrlName, tos(setterName))
                        end
                    end
                end
            end

        end
        if chatMessageText and chatMessageText ~= "" then
            --CHAT_SYSTEM:StartTextEntry(chatMessageText, CHAT_CHANNEL_SAY, nil, false)
            StartChatInput(chatMessageText, CHAT_CHANNEL_SAY, nil)
        end
        local editBox = p_self.editBox
        if editBox then
            if editBox.panel and editBox.panel.valueEditCancel then
                editBox.panel:valueEditCancel(editBox)
            end
        end
        ClearMenu()
    end
end
local setChatEditTextFromContextMenu = tbug.setChatEditTextFromContextMenu

function tbug.setSearchBoxTextFromContextMenu(p_self, p_row, p_data, searchString)
    if p_self and p_row and p_data and searchString and searchString ~= "" then
        --todo get the search box of the active tab and set the search text now
--d("[tbug]setSearchBoxTextFromContextMenu-searchString: " ..tos(searchString))
        local inspector = p_self.inspector
        if inspector ~= nil then
            local filterEdit = tbug.getFilterEdit(inspector)
            if filterEdit ~= nil then
                local currentFilterMode = tbug.getFilterMode(inspector)
                --Change the filterMode to string (str)
                if currentFilterMode ~= 1 then
                    local filterModeButton = tbug.getFilterModeButton(inspector)
                    inspector.updateFilterModeButton(1, filterModeButton)
                end
                filterEdit:SetText(searchString)
            end
        end
    end
end
local setSearchBoxTextFromContextMenu = tbug.setSearchBoxTextFromContextMenu
------------------------------------------------------------------------------------------------------------------------
--CONTROL OUTLINE
local blinksDonePerControl = {}
local function hideOutlineNow(p_controlToOutline, removeAllOutlines)
    removeAllOutlines = removeAllOutlines or false
    if removeAllOutlines == true then
        ControlOutline_ReleaseAllOutlines()
    else
        if ControlOutline_IsControlOutlined(p_controlToOutline) then ControlOutline_ReleaseOutlines(p_controlToOutline) end
    end
end

function tbug.hideOutline(p_self, p_row, p_data, removeAllOutlines)
    local controlToRemoveOutlines = p_self.subject
    if controlToRemoveOutlines ~= nil or removeAllOutlines == true then
        hideOutlineNow(controlToRemoveOutlines, removeAllOutlines)
    end
end
local hideOutline = tbug.hideOutline

local function blinkOutlineNow(p_controlToOutline, p_uniqueBlinkName, p_blinkCountTotal)
    --Hide the outline control at first call, if it is currently shown
    if blinksDonePerControl[p_controlToOutline] == 0 then
        hideOutlineNow(p_controlToOutline)
    end
    --Show/Hide the outline now (toggles on each call to this update function of the RegisterForUpdate event)
    --but only if the control is currently shown (else we cannot see the outline)
    if not p_controlToOutline:IsHidden() then
        ControlOutline_ToggleOutline(p_controlToOutline)
    end

    --Increase blinks done
    blinksDonePerControl[p_controlToOutline] = blinksDonePerControl[p_controlToOutline] + 1

    --End blinking and unregister updater
    if blinksDonePerControl[p_controlToOutline] >= p_blinkCountTotal then
        EM:UnregisterForUpdate(p_uniqueBlinkName)
        blinksDonePerControl[p_controlToOutline] = nil
        hideOutlineNow(p_controlToOutline)
    end
end

local function outlineWithChildControlsNow(control, withChildren)
    withChildren = withChildren or false
    if control == nil then return end
    if withChildren == true then
        hideOutlineNow(control)
        ControlOutline_OutlineParentChildControls(control)
    else
        if ControlOutline_IsControlOutlined(control) then return end
        ControlOutline_ToggleOutline(control)
    end
end
function tbug.outlineControl(p_self, p_row, p_data, withChildren)
    local controlToOutline = p_self.subject
    outlineWithChildControlsNow(controlToOutline, withChildren)
end
local outlineControl = tbug.outlineControl


function tbug.blinkControlOutline(p_self, p_row, p_data, blinkCount)
--d("[TBUG]Blink control outline - blinkCount: " ..tos(blinkCount))
--Debugging
--tbug._blinkControlOutline = {}
--tbug._blinkControlOutline.self = p_self
--tbug._blinkControlOutline.data =p_data
--tbug._blinkControlOutline.row = p_row
    local controlToOutline = p_self.subject
    if controlToOutline ~= nil then
        local controlToOutlineName = controlToOutline.GetName and controlToOutline:GetName()
        if not controlToOutlineName then return end
        local uniqueBlinkName = "TBUG_BlinkOutline_" .. controlToOutlineName
        EM:UnregisterForUpdate(uniqueBlinkName)
        blinksDonePerControl[controlToOutline] = 0
        EM:RegisterForUpdate(uniqueBlinkName, 550, function()
            local blinkCountTotal = blinkCount * 2 --duplicate the blink count to respect each "on AND off" as 1 blink
            blinkOutlineNow(controlToOutline, uniqueBlinkName, blinkCountTotal)
        end)
    end
end
local blinkControlOutline = tbug.blinkControlOutline


------------------------------------------------------------------------------------------------------------------------
--SCRIPT HISTORY
local function refreshScriptHistoryIfShown()
    if tbug_checkIfInspectorPanelIsShown("globalInspector", "scriptHistory") then
        tbug_refreshInspectorPanel("globalInspector", "scriptHistory")
        --TODO: Why does a single data refresh not work directly where a manual click on the update button does work?! Even a delayed update does not work properly...
        tbug_refreshInspectorPanel("globalInspector", "scriptHistory")
    end
end


--Remove a script from the script history by help of the context menu
function tbug.removeScriptHistory(panel, scriptRowId, refreshScriptsTableInspector, clearScriptHistory)
    if not panel or not scriptRowId then return end
    refreshScriptsTableInspector = refreshScriptsTableInspector or false
    clearScriptHistory = clearScriptHistory or false
    ClearMenu()
    --Check if script is not already in
    if tbug.savedVars and tbug.savedVars.scriptHistory then
        if not clearScriptHistory then
            --Set the column to update to 1
            local editBox = {}
            editBox.updatedColumnIndex = 1
            tbug.changeScriptHistory(scriptRowId, editBox, "", refreshScriptsTableInspector)
            if refreshScriptsTableInspector == true then
                refreshScriptHistoryIfShown()
            end
        else
            --Show security dialog asking if this is correct
            local callbackYes = function()
                --Clear the total script history?
                tbug.savedVars.scriptHistory = {}
                tbug.savedVars.scriptHistoryComments = {}

                refreshScriptHistoryIfShown()
            end
            tbug.ShowConfirmBeforeDialog(nil, "Delete total script history?", callbackYes)
        end
    end
end
local removeScriptHistory = tbug.removeScriptHistory

function tbug.editScriptHistory(panel, p_row, p_data, changeScript)
    ClearMenu()
    if not panel or not p_row or not p_data then return end
    if changeScript == nil then changeScript = true end
    --Simulate the edit of value 1 (script lua code)
    local cValRow = (changeScript == true and p_row.cVal) or p_row.cVal2
    local columnIndex = (changeScript == true and 1) or 2
    panel:valueEditStart(panel.editBox, p_row, p_data, cValRow, columnIndex)
end
local editScriptHistory = tbug.editScriptHistory

function tbug.testScriptHistory(panel, p_row, p_data, key)
    ClearMenu()
    if not panel or not key then return end
    panel:testScript(p_row, p_data, key, nil, true)
end
local testScriptHistory = tbug.testScriptHistory


function tbug.getActiveScriptKeybinds()
    local retTab = {}
    for i=1, tbug.maxScriptKeybinds do
        retTab[i] = tbug.savedVars.scriptKeybinds[i]
    end
    return retTab
end
local getActiveScriptKeybinds = tbug.getActiveScriptKeybinds

function tbug.getScriptKeybind(scriptKeybindNumber)
    if scriptKeybindNumber == nil or scriptKeybindNumber < 1 or scriptKeybindNumber > tbug.maxScriptKeybinds then return end
    return tbug.savedVars.scriptKeybinds[scriptKeybindNumber]
end
local getScriptKeybind = tbug.getScriptKeybind

function tbug.setScriptKeybind(scriptKeybindNumber, key, delete)
    delete = delete or false
    if scriptKeybindNumber == nil or scriptKeybindNumber < 1 or scriptKeybindNumber > tbug.maxScriptKeybinds then return end
    if not delete then if key == nil or key > #tbug.savedVars.scriptHistory then return end end
    tbug.savedVars.scriptKeybinds[scriptKeybindNumber] = key
end
local setScriptKeybind = tbug.setScriptKeybind

function tbug.clearScriptKeybinds()
    local activeScriptKeybinds = getActiveScriptKeybinds()
    for scriptKeybindNumber, key in pairs(activeScriptKeybinds) do
         tbug.savedVars.scriptKeybinds[scriptKeybindNumber] = nil
    end
end
local clearScriptKeybinds = tbug.clearScriptKeybinds

function tbug.runScript(scriptKeybindNumber)
    local activeScriptKeybindKey = getScriptKeybind(scriptKeybindNumber)
    if activeScriptKeybindKey == nil then return end
    local command  = tbug.savedVars.scriptHistory[activeScriptKeybindKey]
    if command == nil then return end

    --Run the script saved at the keybind
    tbug_slashCommand(command)
end


function tbug.cleanScriptHistory()
    local alreadyFoundScripts = {}
    local duplicatesFound = {}
    local totalCount = 0
    local duplicateCount = 0

    local scriptHistory = tbug.savedVars.scriptHistory
    for key, scriptStr in pairs(scriptHistory) do
        totalCount = totalCount + 1
        if alreadyFoundScripts[scriptStr] == nil then
            alreadyFoundScripts[scriptStr] = key
        else
            duplicatesFound[key] = alreadyFoundScripts[scriptStr]
            duplicateCount = duplicateCount + 1
        end
    end

    --Clear duplicatesFound key at scriptHistory
    if not ZO_IsTableEmpty(duplicatesFound) then
        local keybindsReassignedStr = ""
        local activeScriptKeybinds = getActiveScriptKeybinds()
        for duplicateKey, originalKey in pairs(duplicatesFound) do
            --Check if duplicate key was assigned to any keybind, then move the keybind to the new key now
            for scriptKeybindNumber, scriptKey in pairs(activeScriptKeybinds) do
                if scriptKey == duplicateKey then
                    tbug.savedVars.scriptKeybinds[scriptKeybindNumber] = originalKey
                    if keybindsReassignedStr == "" then
                        keybindsReassignedStr = tos(scriptKeybindNumber)
                    else
                        keybindsReassignedStr = keybindsReassignedStr .. "," ..tos(scriptKeybindNumber)
                    end
                end
            end
            trem(scriptHistory, duplicateKey)
        end
        --Update the script history UI now if it's currently shown
        refreshScriptHistoryIfShown()

        d("[TBUG]Cleaned duplicate script history entries.")
        d("> total: " .. tos(totalCount) .." / duplicate: " ..tos(duplicateCount) .. " / keybinds reassigned: " ..tos(keybindsReassignedStr))
    end
end
local cleanScriptHistory = tbug.cleanScriptHistory



------------------------------------------------------------------------------------------------------------------------
--SAVED INSPECTORS
local function refreshSavedInspectorsIfShown()
    if tbug_checkIfInspectorPanelIsShown("globalInspector", "savedInsp") then
        tbug_refreshInspectorPanel("globalInspector", "savedInsp")
        --TODO: Why does a single data refresh not work directly where a manual click on the update button does work?! Even a delayed update does not work properly...
        tbug_refreshInspectorPanel("globalInspector", "savedInsp")
    end
end

--Remove a saved inspector by help of the context menu
function tbug.removeSavedInspectors(panel, savedInspectorsRowId, refreshSavedInspectorsTableInspector, clearSavedInspectors)
    if not panel or not savedInspectorsRowId then return end
    refreshSavedInspectorsTableInspector = refreshSavedInspectorsTableInspector or false
    clearSavedInspectors                 = clearSavedInspectors or false
    ClearMenu()
    --Check if script is not already in
    if tbug.savedVars and tbug.savedVars.savedInspectors then
        if not clearSavedInspectors then
            --Set the column to update to 1
            local editBox = {}
            editBox.updatedColumnIndex = 1
            tbug.changeSavedInspectors(savedInspectorsRowId, editBox, "", refreshSavedInspectorsTableInspector)
            if refreshSavedInspectorsTableInspector == true then
                refreshSavedInspectorsIfShown()
            end
        else
            --Show security dialog asking if this is correct
            local callbackYes = function()
                --Clear the total script history?
                tbug.savedVars.savedInspectors = {}
                tbug.savedVars.savedInspectorsComments = {}

                refreshSavedInspectorsIfShown()
            end
            tbug.ShowConfirmBeforeDialog(nil, "Delete total saved inspectors?", callbackYes)
        end
    end
end
local removeSavedInspectors = tbug.removeSavedInspectors

function tbug.editSavedInspectors(panel, p_row, p_data, changeScript)
    ClearMenu()
    if not panel or not p_row or not p_data then return end
    if changeScript == nil then changeScript = true end
    --Simulate the edit of value 1 (script lua code)
    local cValRow = (changeScript == true and p_row.cVal) or p_row.cVal2
    local columnIndex = (changeScript == true and 1) or 2
    panel:valueEditStart(panel.editBox, p_row, p_data, cValRow, columnIndex)
end
local editSavedInspectors = tbug.editSavedInspectors


------------------------------------------------------------------------------------------------------------------------
--EVENTS
local function reRegisterAllEvents()
    eventsInspector = eventsInspector or tbug.Events.getEventsTrackerInspectorControl()
    tbug.Events.ReRegisterAllEvents(eventsInspector)
end

local function registerExcludedEventId(eventId)
    eventsInspector = eventsInspector or tbug.Events.getEventsTrackerInspectorControl()
    tbug.Events.UnRegisterSingleEvent(eventsInspector, eventId)
end

local function addToExcluded(eventId)
    table.insert(tbug.Events.eventsTableExcluded, eventId)
end
local function removeFromExcluded(eventId, removeAll)
    removeAll = removeAll or false
    if removeAll == true then
        tbug.Events.eventsTableExcluded = {}
    else
        for idx, eventIdToFind in ipairs(tbug.Events.eventsTableExcluded) do
            if eventIdToFind == eventId then
                table.remove(tbug.Events.eventsTableExcluded, idx)
                return true
            end
        end
    end
end

local function registerOnlyIncludedEvents()
    local events = tbug.Events
    eventsInspector = eventsInspector or events.getEventsTrackerInspectorControl()
    tbug.Events.UnRegisterAllEvents(eventsInspector, events.eventsTableIncluded)
end

local function addToIncluded(eventId, onlyThisEvent)
    onlyThisEvent = onlyThisEvent or false
    if onlyThisEvent == true then
        tbug.Events.eventsTableIncluded = {}
    end
    table.insert(tbug.Events.eventsTableIncluded, eventId)
end
local function removeFromIncluded(eventId, removeAll)
    removeAll = removeAll or false
    if removeAll == true then
        tbug.Events.eventsTableIncluded = {}
    else
        for idx, eventIdToFind in ipairs(tbug.Events.eventsTableIncluded) do
            if eventIdToFind == eventId then
                table.remove(tbug.Events.eventsTableIncluded, idx)
                return true
            end
        end
    end
end

local function showEventsContextMenu(p_self, p_row, p_data, isEventMainUIToggle)
    --Did we right click the main UI's e/E toggle button?
    isEventMainUIToggle = isEventMainUIToggle or false
    if isEventMainUIToggle == true then
        ClearMenu()
    end

    local events    = tbug.Events
    eventsInspector = eventsInspector or events.getEventsTrackerInspectorControl()

    AddCustomMenuItem("Event tracking actions", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)

    --If the events list is not empty
    if eventsInspector ~= nil and #events.eventsTableInternal > 0 then
        AddCustomMenuItem("Clear events list", function()
            events.eventsTableInternal = {}
            tbug.RefreshTrackedEventsList()
            globalInspector = globalInspector or tbug.getGlobalInspector(true)
            local eventsPanel = globalInspector.panels["events"]
            --eventsPanel:populateMasterList(events.eventsTable, RT.EVENTS_TABLE)
            eventsPanel:refreshData()
            eventsPanel:refreshData() --todo: why do we need to call this twice to clear the list?
        end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
    end

    local currentValue
    if p_data == nil then
        if isEventMainUIToggle == true then
            p_data = {
                key = nil,
                value = {
                    _eventName = "Settings",
                    _eventId   = nil
                }
            }
        else
            return
        end
    end
    currentValue = p_data.value
    local eventName = currentValue._eventName
    local eventId   = currentValue._eventId

    --Actual event actions
    local eventTrackingSubMenuTable = {}
    local eventTrackingSubMenuTableEntry = {}
    if not isEventMainUIToggle then
        eventTrackingSubMenuTableEntry = {
            label = strformat("Exclude this event"),
            callback = function()
                addToExcluded(eventId)
                removeFromIncluded(eventId, false)
                registerExcludedEventId(eventId)
            end,
        }
        table.insert(eventTrackingSubMenuTable, eventTrackingSubMenuTableEntry)
        eventTrackingSubMenuTableEntry = {
            label = strformat("Include this event"),
            callback = function()
                addToIncluded(eventId, false)
                removeFromExcluded(eventId, false)
                registerOnlyIncludedEvents()
            end,
        }
        table.insert(eventTrackingSubMenuTable, eventTrackingSubMenuTableEntry)
        eventTrackingSubMenuTableEntry = {
            label = strformat("ONLY show this event"),
            callback = function()
                addToIncluded(eventId, true)
                removeFromExcluded(nil, true)
                registerOnlyIncludedEvents()
            end,
        }
        table.insert(eventTrackingSubMenuTable, eventTrackingSubMenuTableEntry)
        eventTrackingSubMenuTableEntry = {
            label = "-",
            callback = function() end,
        }
        table.insert(eventTrackingSubMenuTable, eventTrackingSubMenuTableEntry)
    end
    eventTrackingSubMenuTableEntry = {
        label = "Re-register ALL events (clear excluded/included)",
        callback = function()
            reRegisterAllEvents()
        end,
    }
    table.insert(eventTrackingSubMenuTable, eventTrackingSubMenuTableEntry)
    AddCustomSubMenuItem(strformat("Event: \'%s\'", tos(eventName)), eventTrackingSubMenuTable)


    --Included events
    local includedEvents = events.eventsTableIncluded
    if includedEvents and #includedEvents > 0 then
        local eventTrackingIncludedSubMenuTable = {}
        local eventTrackingIncludedSubMenuTableEntry = {}
        for _, eventIdIncluded in ipairs(includedEvents) do
            local eventNameIncluded = events.eventList[eventIdIncluded]
            eventTrackingIncludedSubMenuTableEntry = {
                label = eventNameIncluded,
                callback = function()
                    --Todo Any option needed?
                end,
            }
            table.insert(eventTrackingIncludedSubMenuTable, eventTrackingIncludedSubMenuTableEntry)
        end
        AddCustomSubMenuItem("INcluded events",  eventTrackingIncludedSubMenuTable)
    end

    --Excluded events
    local excludedEvents = events.eventsTableExcluded
    if excludedEvents and #excludedEvents > 0 then
        eventsInspector = eventsInspector or tbug.Events.getEventsTrackerInspectorControl()

        local eventTrackingExcludedSubMenuTable = {}
        local eventTrackingExcludedSubMenuTableEntry = {}
        for _, eventIdExcluded in ipairs(excludedEvents) do
            local eventNameExcluded = events.eventList[eventIdExcluded]
            eventTrackingExcludedSubMenuTableEntry = {
                label = eventNameExcluded .. clickToIncludeAgainStr,
                callback = function()
                    --Remove the excluded event again -> Include it again
                    removeFromExcluded(eventIdExcluded, false)
                    tbug.Events.RegisterSingleEvent(eventsInspector, eventIdExcluded)
                end,
            }
            table.insert(eventTrackingExcludedSubMenuTable, eventTrackingExcludedSubMenuTableEntry)
        end
        AddCustomSubMenuItem("EXcluded events", eventTrackingExcludedSubMenuTable)
    end

    if isEventMainUIToggle == true then
        ShowMenu(p_self)
    end
end
tbug.ShowEventsContextMenu = showEventsContextMenu



------------------------------------------------------------------------------------------------------------------------
-- Localization string functions
------------------------------------------------------------------------------------------------------------------------
local function putLocalizationStringToChat(p_self, p_row, p_data, withCounter)
    withCounter = withCounter or false
    if p_row == nil or p_data == nil then return end
    local keyText = p_data and p_data[localizationStringKeyText]
    --local value = p_data and p_data.value
    if keyText == nil then return end

    if not withCounter then
        addTextToChat("GetString(" .. tos(keyText) ..")")
    else
        addTextToChat("GetString('" .. tos(keyText) .."', <id>)")
    end
end


------------------------------------------------------------------------------------------------------------------------
-- Dialog functions
------------------------------------------------------------------------------------------------------------------------
local function openDialog(p_self, p_row, p_data)
    if p_row == nil or p_data == nil then return end
    local key = p_data and p_data.dataEntry and p_data.dataEntry.data and p_data.dataEntry.data.key
    if key == nil then return end
    ZO_Dialogs_ShowPlatformDialog(tos(key), nil, { })
end


------------------------------------------------------------------------------------------------------------------------
-- Sound functions
------------------------------------------------------------------------------------------------------------------------
local isPlayingEndlessly = false
local endlessPlaySoundName
local endlessPlaySoundEventName = "tbugPlaySoundEndlessly"

local function playRepeated(soundId, count)
    if SOUNDS[soundId] == nil then return end
    count = count or 1
    for i=1, count, 1 do
        PlaySound(SOUNDS[soundId])
    end
end


local function playSoundNow(p_self, p_row, p_data, playCount, playEndless, endlessPause)
    if isPlayingEndlessly and playCount == nil and playEndless == false and endlessPause == nil then
        isPlayingEndlessly = false
        EM:UnregisterForUpdate(endlessPlaySoundEventName)
        return
    end
    if p_row == nil or p_data == nil then return end
    local key = p_data and p_data.key
    local value = p_data and p_data.value
    if key == nil or value == nil then return end

    if key == "NONE" or value == noSoundValue then return end
    if not playEndless then
        playRepeated(key, playCount)
    else
        if isPlayingEndlessly == true then return end
        endlessPause = endlessPause or 0
        local endlessPauseInMs = endlessPause * 1000
        EM:UnregisterForUpdate(endlessPlaySoundEventName)
        if SOUNDS[key] == nil then return end

        playRepeated(key, playCount)
        endlessPlaySoundName = key

        EM:RegisterForUpdate(endlessPlaySoundEventName, endlessPauseInMs, function()
            if not isPlayingEndlessly then
                EM:UnregisterForUpdate(endlessPlaySoundEventName)
                return
            end
            playRepeated(key, playCount)
        end)
        isPlayingEndlessly = true
    end
end
tbug.PlaySoundNow = playSoundNow


------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
--Itemlink context menu entries - Only build once for all functions -> At first context menu open
local itemLinkPrefixesSubmenuTab = {}
local upperCaseFunctionNamePrefixes = {}
local upperCaseFunctionNameSubmenuEntriesIndex = 0
local upperCaseFunctionNameSubmenuEntries = {}
local upperCaseFunctionNamePrefixesMoreThanMax = {}
local noUpperCaseFunctionNameSubmenuEntries = {}

local maxSubmenuEntries = 30


--todo 2023-12-09 Switch context menus from LibCustomMenu to LibScrollableMenu for the itemlinks somehow?

local function getPrefixOfItemLinkFunctionNames(functionNamesTab, prefixDepth, p_maxSubmenuEntries, p_self, p_row, p_data)
--("========================================")
--d("========================================")
--d("[TBUG]getPrefixOfItemLinkFunctionNames-prefixDepth: " ..tos(prefixDepth) .. ", maxEntries: " ..tos(p_maxSubmenuEntries))
--d("========================================")
--d("========================================")
    for _, itemLinkFuncName in ipairs(functionNamesTab) do
        --Get the prefix of the function name (2nd Uppercase char, to detect e.g. Is or Get or Set or Preview or ZO_ prefix)
        local upperCaseOffsetsTab = findUpperCaseCharsAndReturnOffsetsTab(itemLinkFuncName)
        if not ZO_IsTableEmpty(upperCaseOffsetsTab) then
            local startPos --Start the subString for the submenu at 1st character, until next uppercase character
            local endPos --endPos should be next uppercase char - 1
            local prefixCounter = 0
            if #upperCaseOffsetsTab < prefixDepth then
                startPos = 1
                endPos = strlen(itemLinkFuncName)
            else
                for _, posData in ipairs(upperCaseOffsetsTab) do
                    if startPos == nil or endPos == nil then
                        startPos = 1
                        --Is the first uppercase char the 1st char in the function name?
                        -->Then do not use the endPos (1 in that case), but the next found's upperCase char's startPos - 1
                        if prefixDepth == 1 then
                            if posData.startPos ~= 1 and posData.endPos ~= 1 then
                                endPos = posData.startPos - 1
                                --else
                                --1st char is upperCase
                            end
                        else
                            prefixCounter = prefixCounter + 1
                            if prefixCounter == prefixDepth then
                                endPos = posData.startPos - 1
                            end
                        end
                        if endPos ~= nil and endPos <= 0 then endPos = 1 end
                        if startPos ~= nil and endPos ~= nil then break end
                    end
                end
    --d(">funcName: " ..tos(itemLinkFuncName) .. ", startPos: " ..tos(startPos) .. ",  endPos: " ..tos(endPos))
                if startPos ~= nil and endPos ~= nil then
                    local subStrName = strsub(itemLinkFuncName, startPos, endPos)
    --d(">subStrName: " ..tos(subStrName))
                    if subStrName ~= nil and subStrName ~= "" then
                        if upperCaseFunctionNamePrefixes[subStrName] == nil then
                            upperCaseFunctionNameSubmenuEntriesIndex = upperCaseFunctionNameSubmenuEntriesIndex + 1
                            upperCaseFunctionNamePrefixes[subStrName] = upperCaseFunctionNameSubmenuEntriesIndex
    --d(">>index NEW: " ..tos(upperCaseFunctionNameSubmenuEntriesIndex))
                            upperCaseFunctionNameSubmenuEntries[upperCaseFunctionNameSubmenuEntriesIndex] = {
                                submenuName = subStrName,
                                submenuEntries = {
                                    [1] = {
                                        label = itemLinkFuncName,
                                        callback = function() --start chat input with that func name and an itemLink of the bagId and slotIndex of the context menu
                                            setChatEditTextFromContextMenu(p_self, p_row, p_data, false, itemLinkFuncName, false, true)
                                        end,
                                    }
                                },
                            }
                        else
                            local indexOfSubmenuEntry = upperCaseFunctionNamePrefixes[subStrName]
    --d(">>EXISTING index: " ..tos(indexOfSubmenuEntry))
                            local currentSubmenuEntries = upperCaseFunctionNameSubmenuEntries[indexOfSubmenuEntry].submenuEntries
                            local newEntryCount = #currentSubmenuEntries + 1
                            currentSubmenuEntries[newEntryCount] = {
                                label = itemLinkFuncName,
                                callback = function() --start chat input with that func name and an itemLink of the bagId and slotIndex of the context menu
                                    setChatEditTextFromContextMenu(p_self, p_row, p_data, false, itemLinkFuncName, false, true)
                                end,
                            }

                            if newEntryCount > p_maxSubmenuEntries then
                                upperCaseFunctionNamePrefixesMoreThanMax[subStrName] = true
                            end
                        end
                    end
                end
            end

        else
--d("!!!! >No Uppercase function name!")
            --No uppercase characters in the function name? Directly add it
            noUpperCaseFunctionNameSubmenuEntries[#noUpperCaseFunctionNameSubmenuEntries + 1] = {
                label = itemLinkFuncName,
                callback = function() --start chat input with that func name and an itemLink of the bagId and slotIndex of the context menu
                    setChatEditTextFromContextMenu(p_self, p_row, p_data, false, itemLinkFuncName, false, true)
                end,
            }
        end
    end
end

local function buildItemLinkContextMenuEntries(p_self, p_row, p_data)
    local functionsItemLinkSorted = tbug.functionsItemLinkSorted
    if ZO_IsTableEmpty(functionsItemLinkSorted) then return end

    if ZO_IsTableEmpty(itemLinkPrefixesSubmenuTab) then
        upperCaseFunctionNamePrefixes = {}
        upperCaseFunctionNameSubmenuEntriesIndex = 0
        upperCaseFunctionNameSubmenuEntries = {}
        upperCaseFunctionNamePrefixesMoreThanMax = {}
        noUpperCaseFunctionNameSubmenuEntries = {}

        --Get itemLink functionNames with prefix 1
        getPrefixOfItemLinkFunctionNames(functionsItemLinkSorted, 1, maxSubmenuEntries, p_self, p_row, p_data)

        --Uppercase function name submenu entries, for each prefix one
        -->Check 5 times for too many entries in submenus -> Would build up to 5 submenu prefixes with longer entries
        -->e.g. GetItemLinkTrait or GetItemLink or GetItem etc.

        --Up to prefixDepth 5
        for i=1, 3, 1 do
            if not ZO_IsTableEmpty(upperCaseFunctionNameSubmenuEntries) then
                local prefixDepth = i + 1

                for idx, upperCaseSubmenuPrefixData in ipairs(upperCaseFunctionNameSubmenuEntries) do
                    --Check which submenuPrefixEntries are more than the allowed max and build new subMenus with a longer prefix
                    local prefixNameOld = upperCaseSubmenuPrefixData.submenuName
                    if upperCaseFunctionNamePrefixesMoreThanMax[prefixNameOld] == true then
                        local currentSubmenuPrefixData = ZO_ShallowTableCopy(upperCaseSubmenuPrefixData)
                        if currentSubmenuPrefixData ~= nil then
--d("<<PREFIX DELETED due to too many entries: " ..tos(prefixNameOld))
                            --Delete the old 1 prefix entry
                            trem(upperCaseFunctionNameSubmenuEntries, idx)
                            upperCaseFunctionNamePrefixes[prefixNameOld] = nil
                            upperCaseFunctionNameSubmenuEntriesIndex = #upperCaseFunctionNameSubmenuEntries

                            --Get function nams with the prefix
                            local functionNamesTab = {}
                            for _, submenuEntryData in ipairs(currentSubmenuPrefixData.submenuEntries) do
                                functionNamesTab[#functionNamesTab + 1] = submenuEntryData.label
                            end

                            getPrefixOfItemLinkFunctionNames(functionNamesTab, prefixDepth, maxSubmenuEntries, p_self, p_row, p_data)
                        end
                    end

                end

            end
        end --for i=1, 5, 1 do

        if not ZO_IsTableEmpty(upperCaseFunctionNameSubmenuEntries) then
--d(">found #upperCaseFunctionNameSubmenuEntries: " ..tos(#upperCaseFunctionNameSubmenuEntries))
--tbug._upperCaseFunctionNameSubmenuEntries = upperCaseFunctionNameSubmenuEntries

            for _, upperCaseSubmenuPrefixData in ipairs(upperCaseFunctionNameSubmenuEntries) do
                itemLinkPrefixesSubmenuTab[#itemLinkPrefixesSubmenuTab + 1] = {
                    submenuName    = "ItemLink functions \'" .. upperCaseSubmenuPrefixData.submenuName  .. "\'",
                    submenuEntries = upperCaseSubmenuPrefixData.submenuEntries
                }
            end
        end


        --No uppercase function name submenu entries
        if not ZO_IsTableEmpty(noUpperCaseFunctionNameSubmenuEntries) then
--d(">found #noUpperCaseFunctionNameSubmenuEntries: " ..tos(noUpperCaseFunctionNameSubmenuEntries))
            itemLinkPrefixesSubmenuTab[#itemLinkPrefixesSubmenuTab + 1] = {
                submenuName    = "Other ItemLink functions",
                submenuEntries = noUpperCaseFunctionNameSubmenuEntries
            }
        end
    end

    --tbug._upperCaseFunctionNameSubmenuEntries = upperCaseFunctionNameSubmenuEntries
    --tbug._noUpperCaseFunctionNameSubmenuEntries = noUpperCaseFunctionNameSubmenuEntries
    --tbug._itemLinkPrefixesSubmenuTab = itemLinkPrefixesSubmenuTab

    if not ZO_IsTableEmpty(itemLinkPrefixesSubmenuTab) then
        table.sort(itemLinkPrefixesSubmenuTab, function(a, b) return a.submenuName < b.submenuName end)

        for _, data in ipairs(itemLinkPrefixesSubmenuTab) do
            AddCustomSubMenuItem(data.submenuName, data.submenuEntries)
        end
    end
end

------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
--Row context menu at inspectors
--LibCustomMenu custom context menu entry creation for inspector rows
function tbug.buildRowContextMenuData(p_self, p_row, p_data, p_contextMenuForKey)
    p_contextMenuForKey = p_contextMenuForKey or false
--d("[tbug.buildRowContextMenuData]isKey: " ..tos(p_contextMenuForKey))
    if LibCustomMenu == nil or p_self == nil or p_row == nil or p_data == nil then return end

    --TODO: for debugging
--[[
tbug._contextMenuLast = {}
tbug._contextMenuLast.self   = p_self
tbug._contextMenuLast.row    = p_row
tbug._contextMenuLast.data   = p_data
tbug._contextMenuLast.isKey  = p_contextMenuForKey
]]
    local doShowMenu = false
    ClearMenu()

    local RT = tbug.RT
    local dataEntry = p_data.dataEntry
    local dataTypeId = dataEntry and dataEntry.typeId

    local canEditValue = p_self:canEditValue(p_data)
    local key          = p_data.key
    local keyType      = type(key)
    local currentValue = p_data.value
    local valType      = type(currentValue)
    local prop         = p_data.prop
    local propName = prop and prop.name
    local dataPropOrKey = (propName ~= nil and propName ~= "" and propName) or key
    local keyToEnums = tbug.keyToEnums
--d(">canEditValue: " ..tos(canEditValue) .. ", forKey: " .. tos(p_contextMenuForKey) .. ", key: " ..tos(key) ..", keyType: "..tos(keyType) .. ", value: " ..tos(currentValue) .. ", valType: " ..tos(valType) .. ", propName: " .. tos(propName) ..", dataPropOrKey: " ..tos(dataPropOrKey))

    local activeTab = p_self.inspector and p_self.inspector.activeTab

    --Context menu for the key of the row
    if p_contextMenuForKey == true then
        ------------------------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------------------------
        local isScriptHistoryDataType = dataTypeId == RT.SCRIPTHISTORY_TABLE
        local isSoundsDataType = dataTypeId == RT.SOUND_STRING
        local isLocalStringDataType = dataTypeId == RT.LOCAL_STRING
        local isDialogDataType = dataTypeId == RT.GENERIC and activeTab and activeTab.pKeyStr == globalInspectorDialogTabKey --"dialogs"
        local isSavedInspectorsDataType = dataTypeId == RT.SAVEDINSPECTORS_TABLE
        local isEventsDataType = dataTypeId == RT.EVENTS_TABLE

        if key ~= nil then
            local rowActionsSuffix = ""
            local keyNumber = ton(key)
            if "number" == type(keyNumber) then
                rowActionsSuffix = " - #" .. tos(key)
            end

            --General entries
            AddCustomMenuItem("Row actions" .. rowActionsSuffix, function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
            AddCustomMenuItem("Copy key RAW to chat", function() setChatEditTextFromContextMenu(p_self, p_row, p_data, true, nil, true) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            --Add copy "value" raw to chat
            --Default "copy raw etc." entries
            AddCustomMenuItem("Copy value RAW to chat", function() setChatEditTextFromContextMenu(p_self, p_row, p_data, true, nil, nil) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            if tbug.isSpecialEntryAtInspectorList(p_self, p_row, p_data) then
                AddCustomMenuItem("Copy value SPECIAL to chat", function() setChatEditTextFromContextMenu(p_self, p_row, p_data, false, "special", nil) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            end

            local searchValuesAdded = {}
            local searchSubmenu = {}
            local keyStr = key
            if keyType == "number" then
                keyStr = p_data.keyText or tos(key)
            end
            tins(searchSubmenu,
                {
                    label =     "Search key",
                    callback =  function() setSearchBoxTextFromContextMenu(p_self, p_row, p_data, keyStr) end,
                }
            )
            searchValuesAdded[keyStr] = true
            if valType == "string" or valType == "number" then
                tins(searchSubmenu,
                        {
                            label =     "Search value",
                            callback =  function() setSearchBoxTextFromContextMenu(p_self, p_row, p_data, tos(currentValue)) end,
                        }
                )
                searchValuesAdded[tos(currentValue)] = true
            end
            --String and splittable at "_"?
            local isSplittable, splitTab = isSplittableString(keyStr, constantsSplitSepparator)
            if isSplittable == true then
                tins(searchSubmenu,
                        {
                            label =     "-",
                            callback =  function() end,
                        }
                )

                local searchString = ""
                for i=1, #splitTab - 1, 1 do
                    searchString = searchString .. splitTab[i] .. constantsSplitSepparator
                    if not searchValuesAdded[searchString] then
                        tins(searchSubmenu,
                                {
                                    label =     "Search '" .. searchString .. "'",
                                    callback =  function() setSearchBoxTextFromContextMenu(p_self, p_row, p_data, searchString) end,
                                }
                        )
                        searchValuesAdded[searchString] = true
                    end
                end
            end

                --String and got uppercase characters in there, where we could split it?
                local upperCaseOffsetsTab = findUpperCaseCharsAndReturnOffsetsTab(keyStr)
                if not ZO_IsTableEmpty(upperCaseOffsetsTab) then
                    tins(searchSubmenu,
                            {
                                label =     "-",
                                callback =  function() end,
                            }
                    )

                    local stringLength = strlen(keyStr)
                    local searchString = ""
                    local maxEntries = #upperCaseOffsetsTab
                    for idx, offsetData in ipairs(upperCaseOffsetsTab) do
                        local upperCaseString
                        local startPos = offsetData.startPos
                        local endPos = ((idx+1 <= maxEntries) and (upperCaseOffsetsTab[idx + 1].startPos - 1)) or stringLength

                        if startPos ~= nil and endPos ~= nil then
                            upperCaseString = strsub(keyStr, startPos, endPos)
                            --Last entry? Do not add the complete string again as "Search key" covers that already!
                            if idx == maxEntries or stringLength == endPos then
--d(">lastEntry!")
                                --Check if last entry ends with digits
                                local digitsFoundStartPos, digitsFoundEndPos = strfind(upperCaseString, "%d+$")
--d(">>digitsFoundStartPos: " ..tos(digitsFoundStartPos) .. ", digitsFoundEndPos: " ..tos(digitsFoundEndPos))
                                if digitsFoundStartPos ~= nil then
                                    local upperCaseStringWithoutDigits = strsub(upperCaseString, 1, digitsFoundStartPos - 1)
--d(">>>upperCaseStringWithoutDigits: " ..tos(upperCaseStringWithoutDigits))
                                    if upperCaseStringWithoutDigits ~= "" then
                                        local searchStringWithoutDigits = searchString .. upperCaseStringWithoutDigits
                                        if not searchValuesAdded[searchStringWithoutDigits] then
                                            tins(searchSubmenu,
                                                    {
                                                        label =     "Search '" .. searchStringWithoutDigits .. "'",
                                                        callback =  function() setSearchBoxTextFromContextMenu(p_self, p_row, p_data, searchStringWithoutDigits) end,
                                                    }
                                            )
                                            searchValuesAdded[searchStringWithoutDigits] = true
                                        end
                                    end
                                end
                            end

                            if upperCaseString ~= nil then
                                searchString = searchString .. upperCaseString
                                local searchStringCopy = searchString
--d(">searchString: " ..tos(searchString) .. ", upperCaseString: " ..tos(upperCaseString))
                                if not searchValuesAdded[searchStringCopy] then
                                    tins(searchSubmenu,
                                            {
                                                label =     "Search '" .. searchString .. "'",
                                                callback =  function() setSearchBoxTextFromContextMenu(p_self, p_row, p_data, searchStringCopy) end,
                                            }
                                    )
                                    searchValuesAdded[searchStringCopy] = true
                                end
                            end
                        end
                    end
                end

            if not ZO_IsTableEmpty(searchSubmenu) then
                AddCustomSubMenuItem("Search", searchSubmenu)
            end

            doShowMenu = true --to show general entries
            ------------------------------------------------------------------------------------------------------------------------

            --Is key a string ending on "SCENE_NAME" and the value is a string e.g. "trading_house"
            -->Show a context menu entry "Open scene"
            if type(key) == "string" and valType == "string" and (tbug_endsWith(key, "_SCENE_NAME") == true or tbug_endsWith(key, "_SCENE_IDENTIFIER") == true) then
                local slashCmdToShowScene = "SCENE_MANAGER:Show(\'" ..tos(currentValue) .. "\')"
                AddCustomMenuItem("Scene actions", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Show scene", function() tbug.slashCommand(slashCmdToShowScene) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                if SCENE_MANAGER:IsShowing(tos(currentValue)) then
                    local slashCmdToHideScene = "SCENE_MANAGER:Hide(\'" ..tos(currentValue) .. "\')"
                    AddCustomMenuItem("Hide scene", function() tbug.slashCommand(slashCmdToHideScene) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                end
            end
            ------------------------------------------------------------------------------------------------------------------------

            --Dialogs
            if isDialogDataType then
                AddCustomMenuItem("Dialog actions", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Show platform dialog",
                        function()
                            openDialog(p_self, p_row, p_data)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)

            --Localization strings
            elseif isLocalStringDataType then
                AddCustomMenuItem("Local. string actions", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
                AddCustomMenuItem("GetString(<constant>) to chat",
                        function()
                            putLocalizationStringToChat(p_self, p_row, p_data, false)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("GetString('<constant>', id) to chat",
                        function()
                            putLocalizationStringToChat(p_self, p_row, p_data, true)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)

            --Sounds
            elseif isSoundsDataType then
                local soundsHeadlineAdded = false
                local function addSoundsHeadline()
                    if soundsHeadlineAdded == true then return false end
                    AddCustomMenuItem("Sounds actions", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
                    soundsHeadlineAdded = true
                    return true
                end
                if currentValue ~= noSoundValue then
                    addSoundsHeadline()
                    AddCustomMenuItem("||> Play sound",
                            function()
                                playSoundNow(p_self, p_row, p_data, 1, false)
                            end,
                            MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                    local playSoundLouderSubmenu = {}
                    for volume=2,10,1 do
                        playSoundLouderSubmenu[#playSoundLouderSubmenu+1] = {
                            label = "Play sound louder ("..tos(volume).."x)",
                            callback = function()
                                playSoundNow(p_self, p_row, p_data, volume, false)
                            end,
                        }
                    end
                    AddCustomSubMenuItem("||> Play sound (choose volume)", playSoundLouderSubmenu)
                end
                if isPlayingEndlessly == true then
                    if not addSoundsHeadline() then
                        AddCustomMenuItem("-", function()  end)
                    end
                    AddCustomMenuItem("[ ] STOP playing non-stop \'" ..tos(endlessPlaySoundName) .. "\'",
                            function()
                                playSoundNow(p_self, p_row, p_data, nil, false, nil)
                            end,
                            MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                else
                    if currentValue ~= noSoundValue then
                        AddCustomMenuItem("-", function()  end)
                        local playSoundEndlesslyVolumeSubmenus = {}
                        for volume=1,10,1 do
                            playSoundEndlesslyVolumeSubmenus[volume] = {}
                            for pause=0,10,1 do
                                playSoundEndlesslyVolumeSubmenus[volume][#playSoundEndlesslyVolumeSubmenus[volume]+1] = {
                                    label = "Play non-stop ("..tos(pause).."s pause)",
                                    callback = function()
                                        playSoundNow(p_self, p_row, p_data, volume, true, pause)
                                    end,
                                }
                            end
                            AddCustomSubMenuItem("||> Play non-stop (volume "..tos(volume)..")", playSoundEndlesslyVolumeSubmenus[volume])
                        end
                    end
                end

            --SavedInspectors KEY context menu
            elseif isSavedInspectorsDataType then
                AddCustomMenuItem("Saved inspectors actions", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
                --[[
                AddCustomMenuItem("Edit saved inspector entry",
                        function()
                            editSavedInspectors(p_self, p_row, p_data, true)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                ]]
                AddCustomMenuItem("Edit saved inspectors comment",
                        function()
                            editSavedInspectors(p_self, p_row, p_data, false)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Delete saved inspectors entry",
                        function()
                            removeSavedInspectors(p_self, key, true, nil)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Clear total saved inspectors",
                        function()
                            removeSavedInspectors(p_self, key, true, true)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)

            --ScriptHistory KEY context menu
            elseif isScriptHistoryDataType then
                AddCustomMenuItem("Script history actions", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Edit script history entry",
                        function()
                            editScriptHistory(p_self, p_row, p_data, true)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Edit script history comment",
                        function()
                            editScriptHistory(p_self, p_row, p_data, false)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Test script history entry",
                        function()
                            testScriptHistory(p_self, p_row, p_data, key)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Delete script history entry",
                        function()
                            removeScriptHistory(p_self, key, true, nil)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Script history clear & clean", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Clean script history (duplicates)",
                        function()
                            tbug.ShowConfirmBeforeDialog(nil, "Clean duplicates from script history\nand reassign keybinds (if assigned)?", cleanScriptHistory)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Clear total script history",
                        function()
                            removeScriptHistory(p_self, key, true, true)
                        end,
                        MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)

                --Script keybinds
                local submenuScriptKeybinds = {}
                local submenuScriptKeybindsRemove = {}
                local activeKeybinds = getActiveScriptKeybinds()
                for i=1, tbug.maxScriptKeybinds, 1 do
                    local scriptKeybindSubmenuEntry = {
                        label = not activeKeybinds[i] and "Set as Keybind #" .. tos(i) or "Reassign keybind #" .. tos(i) .. ", current script: " ..tos(activeKeybinds[i]),
                        callback = function() setScriptKeybind(i, key) end,
                    }
                    tins(submenuScriptKeybinds, scriptKeybindSubmenuEntry)
                    if activeKeybinds[i] ~= nil then
                        local scriptKeybindRemoveSubmenuEntry = {
                            label = "< Remove Keybind #" .. tos(i) .. ", current script: " ..tos(activeKeybinds[i]),
                            callback = function() setScriptKeybind(i, nil, true) end,
                        }
                        tins(submenuScriptKeybindsRemove, scriptKeybindRemoveSubmenuEntry)
                    end
                end
                if not ZO_IsTableEmpty(activeKeybinds) then
                    if not ZO_IsTableEmpty(submenuScriptKeybindsRemove) then
                        local scriptKeybindSubmenuEntry = {
                            label = "-", --divider
                        }
                        tins(submenuScriptKeybindsRemove, scriptKeybindSubmenuEntry)
                    end
                    local scriptKeybindClearAllSubmenuEntry = {
                        label = "Clear all script keybinds",
                        callback = function() clearScriptKeybinds() end,
                    }
                    tins(submenuScriptKeybindsRemove, scriptKeybindClearAllSubmenuEntry)
                end
                if not ZO_IsTableEmpty(submenuScriptKeybinds) then
                    AddCustomMenuItem("Script keybinds", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
                    AddCustomSubMenuItem("Script keybinds", submenuScriptKeybinds)
                    if not ZO_IsTableEmpty(submenuScriptKeybindsRemove) then
                        AddCustomSubMenuItem("Script keybinds - Remove", submenuScriptKeybindsRemove)
                    end
                end

                doShowMenu = true
                ------------------------------------------------------------------------------------------------------------------------
            --Event tracking KEY context menu
            elseif isEventsDataType then

                showEventsContextMenu(p_self, p_row, p_data, false)
                doShowMenu = true --to show general entries
            end

        end
        ------------------------------------------------------------------------------------------------------------------------
        --Properties are given?
        if prop ~= nil then
            --Getter and Setter - To chat
            local controlOfInspectorRow = p_self.subject
            if controlOfInspectorRow ~= nil then
                local getterName = prop.getOrig or prop.get
                local setterName = prop.setOrig or prop.set
                local getterOfCtrl = controlOfInspectorRow[getterName]
                local setterOfCtrl = controlOfInspectorRow[setterName]
                --d(">prop found - get: " ..tos(getterName) ..", set: " ..tos(setterName))

                if getterOfCtrl ~= nil or setterOfCtrl ~= nil then
                    AddCustomMenuItem("Get & Set", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
                    if getterOfCtrl ~= nil then
                        --p_self, p_row, p_data, copyRawData, copySpecialFuncStr, isKey
                        AddCustomMenuItem("Copy getter name to chat", function() setChatEditTextFromContextMenu(p_self, p_row, p_data, false, "getterName", true) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                        AddCustomMenuItem("Copy <control>:Getter() to chat", function() setChatEditTextFromContextMenu(p_self, p_row, p_data, false, "control:getter", true) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                    end
                    if setterOfCtrl ~= nil then
                        AddCustomMenuItem("Copy setter name to chat", function() setChatEditTextFromContextMenu(p_self, p_row, p_data, false, "setterName", true) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                        AddCustomMenuItem("Copy <control>:Setter() to chat", function() setChatEditTextFromContextMenu(p_self, p_row, p_data, false, "control:setter", true) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                    end
                    doShowMenu = true
                end
            end

            ------------------------------------------------------------------------------------------------------------------------
            --Boolean value at the key, even if no "key" was provided
            if valType == "boolean" then

                --Control outline KEY context menu
                if ControlOutline and dataPropOrKey and dataPropOrKey == "outline" then
                    AddCustomMenuItem("Outline actions", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
                    if not controlOfInspectorRow or controlOfInspectorRow:IsHidden() then
                        AddCustomMenuItem("Control is hidden - no outline possible", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                    else
                        AddCustomMenuItem("Outline", function() outlineControl(p_self, p_row, p_data, false) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                        AddCustomMenuItem("Outline + child controls", function() outlineControl(p_self, p_row, p_data, true) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                        AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                        AddCustomMenuItem("Blink outline 1x", function() blinkControlOutline(p_self, p_row, p_data, 1) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                        AddCustomMenuItem("Blink outline 3x", function() blinkControlOutline(p_self, p_row, p_data, 3) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                        AddCustomMenuItem("Blink outline 5x", function() blinkControlOutline(p_self, p_row, p_data, 5) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)

                        local controlToOutline = p_self.subject
                        local addControlClearOutline = (controlToOutline ~= nil and ControlOutline_IsControlOutlined(controlToOutline) and true) or false
                        local addClearAllOutlines = (#ControlOutline.pool.m_Active > 0 and true) or false
                        local addDividerForClearOutlines = addControlClearOutline or addClearAllOutlines
                        if addDividerForClearOutlines == true then
                            AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                        end
                        if addControlClearOutline == true then
                            AddCustomMenuItem("Remove control outlines", function() hideOutline(p_self, p_row, p_data, false) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                        end
                        if addClearAllOutlines == true then
                            AddCustomMenuItem("Remove all outlines", function() hideOutline(p_self, p_row, p_data, true) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                        end
                    end
                    doShowMenu = true
                end

            end
        end

------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
    --Context menu for the value of the row
    else
        if currentValue ~= nil then
------------------------------------------------------------------------------------------------------------------------
            --boolean entries
            if valType == "boolean" then
                if canEditValue then
                    if currentValue == false then
                        AddCustomMenuItem("+ true",  function() p_data.value = true  setEditValueFromContextMenu(p_self, p_row, p_data, false) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                    else
                        AddCustomMenuItem("- false", function() p_data.value = false setEditValueFromContextMenu(p_self, p_row, p_data, true) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                    end
                    AddCustomMenuItem("   NIL (Attention!)",  function() p_data.value = nil  setEditValueFromContextMenu(p_self, p_row, p_data, currentValue) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                    doShowMenu = true
                end
                ------------------------------------------------------------------------------------------------------------------------
                --number or string entries
            elseif valType == "number" or valType == "string" then
                --Do we have a setter function given?
                --Check if any enumeration is provided and add the givenenum entries to the context menu entries
                local enumsWereAdded = false
                local enumContextMenuEntries = {}
                if prop == nil then
                    if dataPropOrKey ~= nil then
                        --No prop given e.g. at a tableInspector of dataEntry of inventory item
                        --Check if dataPropOrKey == "bagId" e.g. and get the mapped enum for bagId
                        prop = {}
                        prop.enum = keyToEnums[key]
--d(">no props found, used key: " ..tos(key) .. " to get: " ..tos(prop.enum))
                        if prop.enum == nil then prop = nil end
                    end
                end
                if prop ~= nil then
                    local enumProp = prop.enum
                    --Check for enums
                    if enumProp ~= nil then
                        local enumsTab = tbug.enums[enumProp]
                        if enumsTab ~= nil then
                    --for debugging
                    --tbug._contextMenuLast.enumsTab = enumsTab
                            local controlOfInspectorRow = p_self.subject
                            if controlOfInspectorRow then
                                --Setter control and func are given, enums as well
                                --Loop all enums now
                                for enumValue, enumName in pairs(enumsTab) do
                                    table.insert(enumContextMenuEntries, {enumName = enumName, enumValue=enumValue})

                                end
                                enumsWereAdded = #enumContextMenuEntries > 0

                                local setterName = prop.setOrig or prop.set
                                local setterOfCtrl
                                if setterName then
                                    setterOfCtrl = controlOfInspectorRow[setterName]
                                end
                                if setterOfCtrl ~= nil then
                                    canEditValue = true
                                end
                            end
                        end
                    end
                end
                local function insertEnumsToContextMenu(dividerLate)
                    if not dividerLate then
                        --Divider line at the top
                        AddCustomMenuItem("-", function() end)
                    end
                    --Divider line needed from enums?
                    if enumsWereAdded then
                        local headlineText = canEditValue and "Choose value" or "Possible values"
                        local entryFont = canEditValue and "ZoFontGame" or "ZoFontGameSmall"
                        local entryFontColorNormal = canEditValue and DEFAULT_TEXT_COLOR or DISABLED_TEXT_COLOR
                        local entryFontColorHighlighted = canEditValue and DEFAULT_TEXT_HIGHLIGHT or DISABLED_TEXT_COLOR
                        AddCustomMenuItem(headlineText, function() end, MENU_ADD_OPTION_HEADER, nil, entryFontColorNormal, entryFontColorHighlighted, nil, nil)
                        for _, enumData in ipairs(enumContextMenuEntries) do
                            local funcCalledOnEntrySelected = canEditValue and function() p_data.value = enumData.enumValue  setEditValueFromContextMenu(p_self, p_row, p_data, currentValue) end or function()  end
                            AddCustomMenuItem(enumData.enumName, funcCalledOnEntrySelected, MENU_ADD_OPTION_LABEL, entryFont, entryFontColorNormal, entryFontColorHighlighted, nil, nil)
                        end
                        if dividerLate then
                            --Divider line at the bottom
                            AddCustomMenuItem("-", function() end)
                        end
                    end
                end
                if enumsWereAdded and canEditValue then
                    insertEnumsToContextMenu(canEditValue)
                end
                --Default "copy raw etc." entries
                AddCustomMenuItem("Copy RAW to chat", function() setChatEditTextFromContextMenu(p_self, p_row, p_data, true, nil, nil) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                --Special entries for bagId/slotIndex
                local isSpecialEntry = tbug.isSpecialEntryAtInspectorList(p_self, p_row, p_data)
                if isSpecialEntry then
                    AddCustomMenuItem("Copy SPECIAL to chat", function() setChatEditTextFromContextMenu(p_self, p_row, p_data, false, "special", nil) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                end
                --BagId / slotIndex
                if dataPropOrKey and (dataPropOrKey == "bagId" or dataPropOrKey =="slotIndex") then
                    AddCustomMenuItem("Copy ITEMLINK to chat", function() setChatEditTextFromContextMenu(p_self, p_row, p_data, false, "itemlink", nil) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                    AddCustomMenuItem("Copy NAME to chat", function() setChatEditTextFromContextMenu(p_self, p_row, p_data, false, "itemname", nil) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                end
                if dataPropOrKey and (dataPropOrKey == "itemLink") or isSpecialEntry then
                    buildItemLinkContextMenuEntries(p_self, p_row, p_data)
                end
                if enumsWereAdded and not canEditValue then
                    insertEnumsToContextMenu(canEditValue)
                end
                doShowMenu = true
            end
        end
------------------------------------------------------------------------------------------------------------------------
    end
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
    if doShowMenu == true then
        ShowMenu(p_row)
    end
end





------------------------------------------------------------------------------------------------------------------------
-- Context menu for the globalInspector/inspector windows tbug icon
---------------------------------------------------------------------------------------------------------------------------
local function updateSizeOnTabWindowAndCallResizeHandler(p_control, newWidth, newHeight)
    local left = p_control:GetLeft()
    local top = p_control:GetTop()
    p_control:ClearAnchors()
    p_control:SetAnchor(TOPLEFT, nil, TOPLEFT, left, top)
    p_control:SetDimensions(newWidth, newHeight)

    local OnResizeStopHandler = p_control:GetHandler("OnResizeStop")
    if OnResizeStopHandler and type(OnResizeStopHandler) == "function" then
        OnResizeStopHandler(p_control)
    end
end



function tbug.ShowTabWindowContextMenu(selfCtrl, button, upInside, selfInspector)
    setDrawLevel = setDrawLevel or tbug.SetDrawLevel
    --Context menu at headline torchbug icon
    if LibCustomMenu then
        local toggleSizeButton = selfInspector.toggleSizeButton
        local refreshButton = selfInspector.refreshButton

--tbug._selfInspector = selfInspector
--tbug._selfControl = selfCtrl

        globalInspector = globalInspector or tbug.getGlobalInspector()
        local isGlobalInspectorWindow = (selfInspector == globalInspector) or false
        local owner = selfCtrl:GetOwningWindow()

        local activeTab = selfInspector.activeTab
        local subject = activeTab and activeTab.subject
        local subjectName = activeTab and activeTab.subjectName
        local parentSubjectName = activeTab and activeTab.parentSubjectName

        --Claer the menu
        ClearMenu()

        --Draw layer
        local dLayer = owner:GetDrawLayer()
        --setDrawLevel(owner, DL_CONTROLS)
        local drawLayerSubMenu = {}
        local drawLayerSubMenuEntry = {
            label = "On top",
            callback = function() setDrawLevel(owner, DL_OVERLAY, true) end,
        }
        if dLayer ~= DL_OVERLAY then
            tins(drawLayerSubMenu, drawLayerSubMenuEntry)
        end
        drawLayerSubMenuEntry = {
            label = "Normal",
            callback = function() setDrawLevel(owner, DL_CONTROLS, true) end,
        }
        if dLayer ~= DL_CONTROLS then
            tins(drawLayerSubMenu, drawLayerSubMenuEntry)
        end
        drawLayerSubMenuEntry = {
            label = "Background",
            callback = function() setDrawLevel(owner, DL_BACKGROUND, true) end,
        }
        if dLayer ~= DL_BACKGROUND then
            tins(drawLayerSubMenu, drawLayerSubMenuEntry)
        end
        AddCustomSubMenuItem("DrawLayer", drawLayerSubMenu)

        --Add copy RAW title bar
        local titleBar = selfInspector.title
        if titleBar and titleBar.GetText then
            local titleText = titleBar:GetText()
            if titleText ~= "" then
                AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Copy RAW title to chat", function()
                    StartChatInput(titleText, CHAT_CHANNEL_SAY, nil)
                end, MENU_ADD_OPTION_LABEL)
                local titleTextClean = cleanTitle(titleText)
                if titleTextClean ~= titleText then
                    AddCustomMenuItem("Copy CLEAN title to chat", function()
                        StartChatInput(titleTextClean, CHAT_CHANNEL_SAY, nil)
                    end, MENU_ADD_OPTION_LABEL)
                end
            end

            --subjectName
            --parentSubjectName
            --.__Object
            if activeTab ~= nil then
                if subjectName ~= nil then
                    AddCustomMenuItem("Copy SUBJECT to chat", function()
                        addTextToChat(subjectName)
                    end, MENU_ADD_OPTION_LABEL)
                end
                if parentSubjectName ~= nil and subjectName ~= nil and subjectName ~= parentSubjectName then
                    AddCustomMenuItem("Copy PARENT SUBJECT to chat", function()
                        addTextToChat(parentSubjectName)
                    end, MENU_ADD_OPTION_LABEL)
                end

                --[[
                .__Object does not exist at the activeTab directly. It's a custom added entry only visible at the .__index entry of the inspector
                if activeTab[customKey__Object] ~= nil then
                    AddCustomMenuItem("Copy OBJECT name to chat", function()
                        addTextToChat(activeTab[customKey__Object], true)
                    end, MENU_ADD_OPTION_LABEL)
                end
                ]]
            end
        end

        --Inspectors
        local inspectorsSubmenu = {}
        if not isGlobalInspectorWindow then
            tins(inspectorsSubmenu, {
                label = "Save opened inspectors",
                callback = function()
                    local savedInspectorsNr, windowCounter, tabsCounter = tbug.saveCurrentInspectorsAndSubjects()
                    if savedInspectorsNr ~= nil then
                        d("[TBUG]Saved '".. tostring(windowCounter) .."' open inspector windows, with '" ..tos(tabsCounter) .. "' tabs, to:   #" ..tos(savedInspectorsNr))
                    end
                end,
            })
        end
        tins(inspectorsSubmenu, {
            label = "Close all inspectors",
            callback = function() tbug.closeAllInspectors(true) end,
        })
        if not isGlobalInspectorWindow then
            tins(inspectorsSubmenu, {
                label = "Close all inspectors (excl. Global)",
                callback = function() tbug.closeAllInspectors(false) end,
            })
        end
        if not ZO_IsTableEmpty(inspectorsSubmenu) then
            AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            AddCustomSubMenuItem("Inspectors", inspectorsSubmenu)
        end

        --Tabs
        local tabsSubmenu = {}
        if not isGlobalInspectorWindow then
            tins(tabsSubmenu, {
                label = "Close all tabs",
                callback = function() tbug.closeAllTabs(selfInspector) end,
            })
        end
        if not ZO_IsTableEmpty(tabsSubmenu) then
            AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            AddCustomSubMenuItem("Tabs", tabsSubmenu)
        end

        --Tools
        local toolsSubmenu = {}
        local isSceneManagerInspectorTab = subject ~= nil and subject == SCENE_MANAGER
        if not isSceneManagerInspectorTab then
            tins(toolsSubmenu, {
                label = "SCENE_MANAGER",
                callback = function() tbug_slashCommandSCENEMANAGER() end,
            })
        end
        if not ZO_IsTableEmpty(toolsSubmenu) then
            AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            AddCustomSubMenuItem("Tools", toolsSubmenu)
        end

        AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
        AddCustomMenuItem("Reset size to default", function() updateSizeOnTabWindowAndCallResizeHandler(selfInspector.control, tbug.defaultInspectorWindowWidth, tbug.defaultInspectorWindowHeight) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
        AddCustomMenuItem("Collapse/Expand", function() toggleSizeButton.onClicked[MOUSE_BUTTON_INDEX_LEFT](toggleSizeButton) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
        if toggleSizeButton.toggleState == false then
            AddCustomMenuItem("Refresh", function() refreshButton.onClicked[MOUSE_BUTTON_INDEX_LEFT]() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
        end
        --Not at the global inspector of TBUG itsself, else you'd remove all the libraries, scripts, globals etc. tabs
        if not isGlobalInspectorWindow and toggleSizeButton.toggleState == false and (selfInspector.tabs and #selfInspector.tabs > 0) then
            AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            AddCustomMenuItem("Remove all tabs", function() selfInspector:removeAllTabs() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            --Only at the global inspector
        elseif isGlobalInspectorWindow and toggleSizeButton.toggleState == false and (selfInspector.tabs and #selfInspector.tabs < tbug.panelCount ) then
            AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            AddCustomMenuItem("+ Restore all standard tabs +", function() tbug.slashCommand("-all-") end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
        end
        AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
        AddCustomMenuItem("Hide", function() owner:SetHidden(true) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)

        if isPlayingEndlessly == true then
            AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            AddCustomMenuItem("[ ] STOP playing sound \'" ..tos(endlessPlaySoundName) .. "\'", function() playSoundNow(nil, nil, nil, nil, false, nil) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
        end

        if isGlobalInspectorWindow then
            if GetDisplayName() == "@Baertram" then
                AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("~ DEBUG MODE ~", function() tbug.doDebug = not tbug.doDebug d("[TBUG]Debugging: " ..tos(tbug.doDebug)) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            end
            AddCustomMenuItem("Settings", function() end, MENU_ADD_OPTION_HEADER, nil, nil, nil, nil, nil)
            local settingsSubmenu = {
                {
                    label = keyShiftAndLMBRMB .." Inspect control below cursor",
                    callback = function(state) tbug.savedVars.enableMouseRightAndLeftAndSHIFTInspector = state end,
                    itemType = MENU_ADD_OPTION_CHECKBOX,
                    checked = function() return tbug.savedVars.enableMouseRightAndLeftAndSHIFTInspector end,
                },
                {
                    label = "Allow " .. keyShiftAndLMBRMB .. " during Combat/Dungeon/Raid/AvA",
                    callback = function(state) tbug.savedVars.enableMouseRightAndLeftAndSHIFTInspectorDuringCombat = state end,
                    itemType = MENU_ADD_OPTION_CHECKBOX,
                    checked = function() return tbug.savedVars.enableMouseRightAndLeftAndSHIFTInspectorDuringCombat end,
                    disabled = function() return not tbug.savedVars.enableMouseRightAndLeftAndSHIFTInspector end,
                },
            }
            AddCustomSubMenuItem("Mouse", settingsSubmenu)
        end
        AddCustomMenuItem("|cFF0000X Close|r", function() selfInspector:release() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
        --Fix to show the context menu entries above the window, and make them selectable
        if dLayer == DL_OVERLAY then
            setDrawLevel(owner, DL_CONTROLS)
        end
        ShowMenu(owner)

    end --if LibCustomMenu then
end
