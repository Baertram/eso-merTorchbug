local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")
local tos = tostring
local strformat = string.format
local strsub = string.sub
local type = type
local osdate = os.date

local typeColors = tbug.cache.typeColors
local typeSafeLess = tbug.typeSafeLess
local isGetStringKey = tbug.isGetStringKey

local tbug_inspect = tbug.inspect
local tbug_truncate = tbug.truncate
local tbug_specialKeyToColorType = tbug.specialKeyToColorType
local tbug_glookup = tbug.glookup
local tbug_glookupEnum = tbug.glookupEnum

local customKeysForInspectorRows = tbug.customKeysForInspectorRows
local customKey__Object = customKeysForInspectorRows.object

local tbug_buildRowContextMenuData = tbug.buildRowContextMenuData
local tbug_setEditValueFromContextMenu = tbug.setEditValueFromContextMenu

local keyToSpecialEnum = tbug.keyToSpecialEnum
local isSpecialInspectorKey = tbug.isSpecialInspectorKey
local enums = tbug.enums
--local tmpGroups = tbug.tmpGroups

local getRelevantNameForCall = tbug.getRelevantNameForCall
local getControlName = tbug.getControlName
local getControlType = tbug.getControlType

--------------------------------

local function getSpecialInspectorKeyConstant(key, value, row, data)
    local enumNameForConstants = keyToSpecialEnum[key]
    if not enumNameForConstants then return end
    local enumNameForConstantsWithoutUnderscoreSuffix = strsub(enumNameForConstants, 1, -2) --remove _ at the end
--d(">enumNameForConstantsWithoutUnderscoreSuffix: " ..tos(enumNameForConstantsWithoutUnderscoreSuffix))
    local enumsForConstants = enums[enumNameForConstantsWithoutUnderscoreSuffix]
    if not enumsForConstants then return end
    --Get the prefix of the enum to check in table tbug.tmpGroups
    local constantStr = enumsForConstants[value]
    return constantStr
end


--------------------------------
local function invoke(object, method, ...)
    return object[method](object, ...)
end


-------------------------------
-- class TableInspectorPanel --

local classes = tbug.classes
local ObjectInspectorPanel = classes.ObjectInspectorPanel
local TableInspectorPanel = classes.TableInspectorPanel .. ObjectInspectorPanel

TableInspectorPanel.CONTROL_PREFIX = "$(parent)PanelT"
TableInspectorPanel.TEMPLATE_NAME = "tbugTableInspectorPanel"

--Update the table tbug.panelClassNames with the TableInspectorPanel class
tbug.panelClassNames["tableInspector"] = TableInspectorPanel


local RT = tbug.RT

function TableInspectorPanel:__init__(control, ...)
    ObjectInspectorPanel.__init__(self, control, ...)

    self.compareFunc = function(a, b)
        local aa, bb = a.data, b.data
        if not aa.meta then
            if bb.meta then
                return false
            end
        elseif not bb.meta then
            return true
        end
        return typeSafeLess(aa.key, bb.key)
    end
end


function TableInspectorPanel:bindMasterList(editTable, specialMasterListID)
    self.subject = editTable
    self.specialMasterListID = specialMasterListID
end


function TableInspectorPanel:buildMasterList()
--d("[tbug]TableInspectorPanel:buildMasterList")
    if self:buildMasterListSpecial() then
--d("<building special!")
        return
    end
    local masterList = self.masterList
    local n = 0

    --Add the _parentControl -> if you are at a __index invoked metatable control
    -->adds the "__Object" name
    local _parentSubject = self._parentSubject
--tbug._selfTableInspector = self
    if _parentSubject ~= nil then
        local rt = RT.GENERIC
        --local controlName = pcall(invoke, _parentSubject, "GetName")
--d(">found __parentSubject: " ..tostring(controlName))
        --if controlName then
            local data = {key = customKey__Object, value = _parentSubject} --"__Object"
            n = n + 1
            masterList[n] = ZO_ScrollList_CreateDataEntry(rt, data)
        --end
    end

    for k, v in next, self.subject do
        local tv = type(v)
        local rt = RT.GENERIC

        if tv == "userdata" and pcall(invoke, v, "GetFontInfo") then
            rt = RT.FONT_OBJECT
        end

        local data = {key = k, value = v}
        n = n + 1
        masterList[n] = ZO_ScrollList_CreateDataEntry(rt, data)
    end

    local mt = getmetatable(self.subject)
    if mt then
        local rt = RT.GENERIC
        if rawequal(mt, rawget(mt, "__index")) then
            -- metatable refers to itself, which is typical for class
            -- tables containing methods => only insert the __index
            local data = {key = "__index", value = mt, meta = mt}
            n = n + 1
            masterList[n] = ZO_ScrollList_CreateDataEntry(rt, data)
        else
            -- insert the whole metatable contents
            for k, v in next, mt do
                local data = {key = k, value = v, meta = mt}
                n = n + 1
                masterList[n] = ZO_ScrollList_CreateDataEntry(rt, data)
            end
        end
    end

    tbug_truncate(masterList, n)
end


function TableInspectorPanel:buildMasterListSpecial()
    local editTable = self.subject
    local specialMasterListID = self.specialMasterListID
    local tbEvents = tbug.Events
    local isScenes = ((specialMasterListID and specialMasterListID == RT.SCENES_TABLE) or rawequal(editTable, tbug.ScenesOutput)) or false
    local isFragments = ((specialMasterListID and specialMasterListID == RT.FRAGMENTS_TABLE) or rawequal(editTable, tbug.FragmentsOutput)) or false
--d(string.format("[tbug]TableInspectorPanel:buildMasterListSpecial - specialMasterListID: %s, scenes: %s, fragments: %s", tos(specialMasterListID), tos(isScenes), tos(isFragments)))

    if rawequal(editTable, nil) then
        return true
    elseif (specialMasterListID and specialMasterListID == RT.GENERIC) or (rawequal(editTable, _G.ESO_Dialogs)) then
        self:populateMasterList(editTable, RT.GENERIC)
    elseif isScenes or isFragments then
        tbug.refreshScenes()
        if isScenes then
            self:bindMasterList(tbug.ScenesOutput, RT.SCENES_TABLE)
            self:populateMasterList(editTable, RT.SCENES_TABLE)
        elseif isFragments then
            self:bindMasterList(tbug.FragmentsOutput, RT.FRAGMENTS_TABLE)
            self:populateMasterList(editTable, RT.FRAGMENTS_TABLE)
        end
    elseif (specialMasterListID and specialMasterListID == RT.LOCAL_STRING) or rawequal(editTable, _G.EsoStrings) then
        self:populateMasterList(editTable, RT.LOCAL_STRING)
    elseif (specialMasterListID and specialMasterListID == RT.SOUND_STRING) or rawequal(editTable, _G.SOUNDS) then
        self:populateMasterList(editTable, RT.SOUND_STRING)
    --elseif rawequal(editTable, LibStub.libs) then
    elseif (specialMasterListID and specialMasterListID == RT.LIB_TABLE) or rawequal(editTable, tbug.LibrariesOutput) then
        self:bindMasterList(tbug.LibrariesOutput, RT.LIB_TABLE)
        self:populateMasterList(editTable, RT.LIB_TABLE)
    --[[
    elseif (specialMasterListID and specialMasterListID == RT.SCRIPTHISTORY_TABLE) or rawequal(editTable, tbug.ScriptsData) then
        tbug.refreshScripts()
        self:bindMasterList(tbug.ScriptsData, RT.SCRIPTHISTORY_TABLE)
        self:populateMasterList(editTable, RT.SCRIPTHISTORY_TABLE)
    ]]
    elseif (specialMasterListID and specialMasterListID == RT.ADDONS_TABLE) or rawequal(editTable, tbug.AddOnsOutput) then
        self:bindMasterList(tbug.AddOnsOutput, RT.ADDONS_TABLE)
        self:populateMasterList(editTable, RT.ADDONS_TABLE)
    elseif (specialMasterListID and specialMasterListID == RT.EVENTS_TABLE) or rawequal(editTable, tbEvents.eventsTable) then
        tbug.RefreshTrackedEventsList()
        self:bindMasterList(tbEvents.eventsTable, RT.EVENTS_TABLE)
        self:populateMasterList(editTable, RT.EVENTS_TABLE)
    elseif (specialMasterListID and specialMasterListID == RT.SAVEDVARIABLES_TABLE) or rawequal(editTable, tbug.SavedVariablesOutput) then
        self:bindMasterList(tbug.SavedVariablesOutput, RT.SAVEDVARIABLES_TABLE)
        self:populateMasterList(editTable, RT.SAVEDVARIABLES_TABLE)
    else
        return false
    end
    return true
end


function TableInspectorPanel:canEditValue(data)
    local dataEntry = data.dataEntry
    if not dataEntry then return false end
    local typeId = dataEntry.typeId
    return typeId == RT.GENERIC
            or typeId == RT.LOCAL_STRING
            or typeId == RT.SOUND_STRING
            --or typeId == RT.SCRIPTHISTORY_TABLE
end


function TableInspectorPanel:clearMasterList(editTable)
    local masterList = self.masterList
    tbug_truncate(masterList, 0)
    self.subject = editTable
    return masterList
end


function TableInspectorPanel:initScrollList(control)
    ObjectInspectorPanel.initScrollList(self, control)

    --Check for special key colors!
    local function checkSpecialKeyColor(keyValue)
        if keyValue == "event" or not tbug_specialKeyToColorType then return end
        local newType = tbug_specialKeyToColorType[keyValue]
        return newType
    end

    local function setupValue(cell, typ, val, isKey)
        isKey = isKey or false
        cell:SetColor(typeColors[typ]:UnpackRGBA())
        cell:SetText(tos(val))
    end

    local function setupValueLookup(cell, typ, val, row)
        cell:SetColor(typeColors[typ]:UnpackRGBA())
        local name = tbug_glookup(val)
        if name then
            cell:SetText(strformat("%s: %s", typ, name))
        else
            cell:SetText(tos(val))
        end
    end

    local function setupCommon(row, data, list, font)
        local k = data.key
        local tk = data.meta and "event" or type(k)
        local tkOrig = tk
        tk = checkSpecialKeyColor(k) or tkOrig

        self:setupRow(row, data)
        if row.cKeyLeft then
            setupValue(row.cKeyLeft, tk, k, true)
            if font and font ~= "" then
                row.cKeyLeft:SetFont(font)
            end
        end
        if row.cKeyRight then
            setupValue(row.cKeyRight, tk, "", true)
        end

        return k, tkOrig
    end

    local function setupAddOnRow(row, data, list, font)
        local k = data.key
        local tk = data.meta and "event" or type(k)
        local tkOrig

        self:setupRow(row, data)
        if row.cKeyLeft then
            local AddOnData = tbug.AddOnsOutput
            local addonNameClean
            local addonName
            if AddOnData and AddOnData[k] ~= nil then
                addonNameClean = AddOnData[k].name
                addonName = "[" .. tos(k) .."] " .. addonNameClean
            end

            tkOrig = tk
            tk = checkSpecialKeyColor(addonNameClean) or tkOrig
            setupValue(row.cKeyLeft, tk, addonName, true)
            if font and font ~= "" then
                row.cKeyLeft:SetFont(font)
            end
        end
        if row.cKeyRight then
            setupValue(row.cKeyRight, tk, "", true)
        end

        return k, tkOrig
    end

    local function setupGeneric(row, data, list)
        local k, tk = setupCommon(row, data, list)
        local v = data.value
        local tv = type(v)
        local isNumber = tv == "number" or false
        local isKeyRightUsed = false

        if v == nil or tv == "boolean" or isNumber then
            --Key is "text" and value is number? Show the GetString() for the text
            if k and isNumber and k ~= 0 and isGetStringKey(k)==true then
                local valueGetString = GetString(v)
                if valueGetString and valueGetString ~= "" then
                    setupValue(row.cVal, tv, v .. " |r|cFFFFFF(\""..valueGetString.."\")|r", false)
                end
            else
                setupValue(row.cVal, tv, v)
            end
        elseif tv == "string" then
            setupValue(row.cVal, tv, strformat("%q", v))
        elseif tv == "table" and next(v) == nil then
            setupValue(row.cVal, tv, "{}")
        elseif tv == "userdata" then
            local ct, ctName = getControlType(v, "CT_names")
            if ct then
                if row.cKeyRight then
                    setupValue(row.cKeyRight, type(ct), ctName, true)
                    isKeyRightUsed = true
                end
                setupValue(row.cVal, tv, getControlName(v))
            else
                setupValueLookup(row.cVal, tv, v)
            end
        else
            setupValueLookup(row.cVal, tv, v, row)
            if rawequal(v, self.subject) then
                if row.cKeyRight then
                    setupValue(row.cKeyRight, tv, "self")
                    isKeyRightUsed = true
                end
            end
        end

        --Special String key -> Add right key info?
        if not isKeyRightUsed and row.cKeyRight and isSpecialInspectorKey[k] then
            local keyRightText = getSpecialInspectorKeyConstant(k, v, row, data)
            if keyRightText ~= nil and keyRightText ~= "" then
                setupValue(row.cKeyRight, type(keyRightText), keyRightText, true)
            end
        end
    end

    local function setupFontObject(row, data, list)
        local k, tk = setupCommon(row, data, list, data.key)
        local v = data.value
        local tv = type(v)

        local ok, face, size, option = pcall(invoke, v, "GetFontInfo")
        if ok then
            --local nameFont = string.format("$(%s)|$(KB_%s)|%s", fontStyle, fontSize, fontWeight)
            v = tos(strformat("%s||%s||%s", typeColors[type(face)]:Colorize(face), typeColors[type(size)]:Colorize(size), typeColors[type(option)]:Colorize(option)))
        end

        setupValue(row.cVal, tv, v, false)
    end

    local function setupLibOrAddonTableRightKeyAndValues(row, data, list, k, tk, v, isLibrary, checkIfAddOnIsALibrary)
        isLibrary = isLibrary or false
        checkIfAddOnIsALibrary = checkIfAddOnIsALibrary or false
        local AddOnData = tbug.AddOnsOutput
        local addonName

        --Run if an addon should be handled as a library
        local isAddOnButShouldBeHandledAsLibrary = false
        if isLibrary == false and checkIfAddOnIsALibrary == true then
            addonName = AddOnData[k].name
            local libOutputTable = tbug.LibrariesOutput
            if libOutputTable[addonName] ~= nil then
                isAddOnButShouldBeHandledAsLibrary = true
            end
        end

        --Library or AddOn which is handled as a library
        if isLibrary == true or isAddOnButShouldBeHandledAsLibrary == true then
            local key = k
            if isAddOnButShouldBeHandledAsLibrary == true then
                key = addonName
            end
            if row.cKeyRight then
                local LibrariesData = tbug.LibrariesData
                local typeOfLibrary = "string"
                local libraryNameAndVersion = ""
                local wasFoundInLibStub = false
                if LibStub then
                    local lsLibs = LibStub.libs
                    local lsMinors = LibStub.minors
                    local lsLibsKey = lsLibs and lsLibs[key]
                    if lsLibsKey ~= nil and (lsLibsKey == v or (isAddOnButShouldBeHandledAsLibrary == true and v.LibraryGlobalVar and lsLibsKey == v.LibraryGlobalVar)) then
                        wasFoundInLibStub = true
                        typeOfLibrary = "obsolete"
                        libraryNameAndVersion = "LibStub"
                        if lsMinors and lsMinors[key] then
                            libraryNameAndVersion = libraryNameAndVersion .. " (v" .. tos(lsMinors[key]) ..")"
                        end
                    end
                end
                if wasFoundInLibStub == false then
                    if LibrariesData and LibrariesData[key] then
                        if LibrariesData[key].version ~= nil then
                            libraryNameAndVersion = tos(LibrariesData[key].version) or ""
                            if libraryNameAndVersion and libraryNameAndVersion ~= "" then
                                libraryNameAndVersion = "v" .. libraryNameAndVersion
                            end
                        end
                    end
                end
                setupValue(row.cKeyRight, typeOfLibrary, libraryNameAndVersion)

            end
            setupValue(row.cVal, type(v), v)

        --AddOn
        else
            if row.cKeyRight then
                local typeOfAddOn = "string"
                local addOnNameAndVersion = ""
                if AddOnData and AddOnData[k] then
                    if AddOnData[k].version ~= nil then
                        addOnNameAndVersion = tos(AddOnData[k].version) or ""
                        if addOnNameAndVersion and addOnNameAndVersion ~= "" then
                            addOnNameAndVersion = "v" .. addOnNameAndVersion
                        end
                    end
                end
                setupValue(row.cKeyRight, typeOfAddOn, addOnNameAndVersion)
            end
            setupValue(row.cVal, type(v), v)
        end
    end

    local function setupLibTable(row, data, list)
        local k, tk = setupCommon(row, data, list)
        local v = data.value
        setupLibOrAddonTableRightKeyAndValues(row, data, list, k, tk, v, true, nil)
    end

    local function setupAddOnTable(row, data, list)
        local k, tk = setupAddOnRow(row, data, list)
        local v = data.value
        local AddOnData = tbug.AddOnsOutput
        local isLibrary = AddOnData[k].isLibrary
        setupLibOrAddonTableRightKeyAndValues(row, data, list, k, tk, v, false, isLibrary)
    end

    local function setupLocalString(row, data, list)
        local k, tk = setupCommon(row, data, list)
        local v = data.value
        local tv = type(v)

        if tk == "number" then
            local si = rawget(tbug_glookupEnum("SI"), k)
            row.cKeyLeft:SetText(si or "")
            data.keyText = si
            if row.cKeyRight then
                row.cKeyRight:SetText(tos(k))
            end
        end

        if tv == "string" then
            setupValue(row.cVal, tv, strformat("%q", v))
        else
            setupValue(row.cVal, tv, v)
        end
    end

    --[[
    local function setupScriptHistory(row, data, list)
        local k, tk = setupCommon(row, data, list)
        local v = data.value
        local tv = type(v)

        row.cVal:SetText("")
        if tv == "string" then
            setupValue(row.cVal, tv, v)
        end
        if row.cVal2 then
            row.cVal2:SetText("")
            v = nil
            v = tbug.getScriptHistoryComment(data.key)
            if v ~= nil and v ~= "" then
                setupValue(row.cVal2, "comment", v)
            end
        end
    end
    ]]

    local function setupEventTable(row, data, list)
        local k, tk = setupCommon(row, data, list)
        local v = data.value
        local tv = type(v)

        if row.cKeyLeft then
            local timeStampAdded = data.value._timeStamp
            --local frameTimeAdded = data.value._frameTime
            if timeStampAdded then
                row.cKeyLeft:SetText(osdate("%c", timeStampAdded))
            end
        end

        if tv == "table" and next(v) == nil then
            setupValue(row.cVal, tv, "{}")
        elseif tv == "userdata" then
            setupValueLookup(row.cVal, tv, v)
        else
            setupValueLookup(row.cVal, tv, v)
            if rawequal(v, self.subject) then
                if row.cKeyRight then
                    setupValue(row.cKeyRight, tv, "self")
                end
            end
        end

        if row.cKeyRight then
            setupValue(row.cKeyRight, "event", data.value._eventName)
        end
    end

    local function hideCallback(row, data)
        if self.editData == data then
            self.editBox:ClearAnchors()
            self.editBox:SetAnchor(BOTTOMRIGHT, nil, TOPRIGHT, 0, -20)
        end
    end

    self:addDataType(RT.GENERIC,                "tbugTableInspectorRow",    24, setupGeneric,       hideCallback)
    self:addDataType(RT.FONT_OBJECT,            "tbugTableInspectorRowFont",56, setupFontObject,    hideCallback)
    self:addDataType(RT.LOCAL_STRING,           "tbugTableInspectorRow",    24, setupLocalString,   hideCallback)
    self:addDataType(RT.SOUND_STRING,           "tbugTableInspectorRow",    24, setupGeneric,       hideCallback)
    self:addDataType(RT.LIB_TABLE,              "tbugTableInspectorRow",    24, setupLibTable,      hideCallback)
    self:addDataType(RT.ADDONS_TABLE,           "tbugTableInspectorRow",    24, setupAddOnTable,    hideCallback)
    self:addDataType(RT.EVENTS_TABLE,           "tbugTableInspectorRow",    24, setupEventTable,    hideCallback)
    self:addDataType(RT.SAVEDVARIABLES_TABLE,   "tbugTableInspectorRow",    24, setupGeneric,       hideCallback)
    self:addDataType(RT.SCENES_TABLE,           "tbugTableInspectorRow",    24, setupGeneric,       hideCallback)
    self:addDataType(RT.FRAGMENTS_TABLE,        "tbugTableInspectorRow",    24, setupGeneric,       hideCallback)
end


--Clicking on a tables index (e.g.) 6 should not open a new tab called 6 but tableName[6] instead
function TableInspectorPanel:BuildWindowTitleForTableKey(data)
    local winTitle
    if data.key and type(tonumber(data.key)) == "number" then
        winTitle = self.inspector.activeTab.label:GetText()
        if winTitle and winTitle ~= "" then
            winTitle = tbug.cleanKey(winTitle)
            winTitle = winTitle .. "[" .. tos(data.key) .. "]"
--d(">tabTitle: " ..tos(tabTitle))
        end
    end
    return winTitle
end



function TableInspectorPanel:onRowClicked(row, data, mouseButton, ctrl, alt, shift)
    local isGlobalInspector = (self.inspector and self.inspector.control and self.inspector.control.isGlobalInspector) or false
    if tbug.doDebug then
        d("[tbug]TableInspectorPanel:onRowClicked - isGlobalInspector: " ..tos(isGlobalInspector))
        tbug._debugTableInspectorRowClicked = {
            row = row,
            data = data,
            self = self,
        }
    end
    ClearMenu()
    local sliderCtrl = self.sliderControl
    if mouseButton == MOUSE_BUTTON_INDEX_LEFT then
        self.editBox:LoseFocus()
        if sliderCtrl ~= nil then
            sliderCtrl.panel:valueSliderCancel(sliderCtrl)
        end

        local value = data.value
        if type(value) == "string" then
            if data.dataEntry.typeId == RT.SOUND_STRING then
                PlaySound(value)
            end
        else
            --Get metatable of a control? Save the subjectParent
            local valueToInspect = value
            local isFunctionCallWithParentSubject = false
            local _parentSubject, parentSubjectName
            local parentSubjectNameGiven = false
            if data.key == "__index" then
--d(">clicked on __index")
                --Add the subject as new line __parentSubject to the inspector result rows
                _parentSubject = self._parentSubject or (self.subject ~= nil and self.subject[customKey__Object])
                if _parentSubject == nil then
                    if self.subject ~= nil and type(self.subject == "table") then
                        --Got the subject table metatables?
                        local mt = getmetatable(self.subject)
                        if mt ~= nil and mt.__index ~= nil then
--d(">found metatable.__index at self.subject -> parentSubject")
                            _parentSubject = self.subject
                        end
                    end
                end
                data._parentSubject = _parentSubject
            elseif type(value) == "function" and shift == true and not ctrl then
--d(">>function!")
                _parentSubject = self._parentSubject or (self.subject ~= nil and self.subject[customKey__Object])
                if _parentSubject ~= nil then
--d(">found _parentSubject")
                    --Get the name of the control but only if it's no scene as the scene name is not the control name
                    parentSubjectName = getRelevantNameForCall(_parentSubject)

                    isFunctionCallWithParentSubject = true
                    parentSubjectNameGiven = (parentSubjectName ~= nil and type(parentSubjectName) == "string" and parentSubjectName ~= "" and true) or false
                    if not parentSubjectNameGiven then
--d(">>no parentSubject name")
                        --Attention: Might only return the 1st return parameter of the function!
                        valueToInspect = function() return _parentSubject[value](_parentSubject) end
                    end
                end
            end

            if not shift and self.inspector.openTabFor then
                local winTitle = self:BuildWindowTitleForTableKey(data)
                local useInspectorTitel = (winTitle ~= nil and winTitle ~= "" and true) or false
--d(">inspector.openTabFor-winTitle: " ..tos(winTitle) .. ", useInspectorTitel: " ..tos(useInspectorTitel))
                self.inspector:openTabFor(valueToInspect, tos(data.key), winTitle, useInspectorTitel, data, nil, true)
            else
                local winTitle = self:BuildWindowTitleForTableKey(data)
                if (winTitle == nil or winTitle == "") and isFunctionCallWithParentSubject == true and parentSubjectNameGiven then
--d(">preparing winTitle for function")
                    winTitle = parentSubjectName .. ":" .. tos(data.key)
                end
                if shift == true and not ctrl and isFunctionCallWithParentSubject == true and parentSubjectNameGiven then
                    local slashCommand = parentSubjectName .. ":" .. tos(data.key) .. "()"
--d(">tbug.slashCommand -> function of parentSubject: " ..slashCommand)
                    --Do not use tbug_inspect directly but use the tbug.slashCommand handler instead so that all
                    --return parameters of the function are properly shown in chat
                    --valueToInspect = function() return value(_parentSubject) end
                    tbug.slashCommand(slashCommand)

                else
--d(">tbug_inspect-winTitle: " ..tos(winTitle))
                  --tbug.inspect(object, tabTitle, winTitle, recycleActive, objectParent, currentResultIndex, allResults, data, searchData, isMOC, wasClickedAtGlobalInspector)
                    local inspector = tbug_inspect(valueToInspect, tos(data.key), winTitle, not shift, nil, nil, nil, data, nil, nil, isGlobalInspector)
                    if inspector then
                        inspector.control:BringWindowToTop()
                    end
                end
            end
        end
    elseif mouseButton == MOUSE_BUTTON_INDEX_RIGHT then
        if self:canEditValue(data) then
            if MouseIsOver(row.cVal) then
                if sliderCtrl ~= nil then
                    sliderCtrl.panel:valueSliderCancel(sliderCtrl)
                end
                self:valueEditStart(self.editBox, row, data)
                tbug_buildRowContextMenuData(self, row, data, false)
            elseif MouseIsOver(row.cVal2) then
                if sliderCtrl ~= nil then
                    sliderCtrl.panel:valueSliderCancel(sliderCtrl)
                end
                self:valueEditStart(self.editBox, row, data)
            elseif MouseIsOver(row.cKeyLeft) or MouseIsOver(row.cKeyRight) then
                if sliderCtrl ~= nil then
                    sliderCtrl.panel:valueSliderCancel(sliderCtrl)
                end
                self.editBox:LoseFocus()
                tbug_buildRowContextMenuData(self, row, data, true)
            end
        elseif MouseIsOver(row.cKeyLeft) or MouseIsOver(row.cKeyRight) then
            if sliderCtrl ~= nil then
                sliderCtrl.panel:valueSliderCancel(sliderCtrl)
            end
            self.editBox:LoseFocus()
            tbug_buildRowContextMenuData(self, row, data, true)
        elseif MouseIsOver(row.cVal1)  then
            if sliderCtrl ~= nil then
                sliderCtrl.panel:valueSliderCancel(sliderCtrl)
            end
            self.editBox:LoseFocus()
            tbug_buildRowContextMenuData(self, row, data, false)
        else
            if sliderCtrl ~= nil then
                sliderCtrl.panel:valueSliderCancel(sliderCtrl)
            end
            self.editBox:LoseFocus()
        end
    end
end

function TableInspectorPanel:onRowDoubleClicked(row, data, mouseButton, ctrl, alt, shift)
--df("tbug:TableInspectorPanel:onRowDoubleClicked")
    ClearMenu()
    if mouseButton == MOUSE_BUTTON_INDEX_LEFT then
        local sliderCtrl = self.sliderControl

        local value = data.value
        local typeValue = type(value)
        if MouseIsOver(row.cVal) then
            if sliderCtrl ~= nil then
                sliderCtrl.panel:valueSliderCancel(sliderCtrl)
            end
            if self:canEditValue(data) then
                if typeValue == "boolean" then
                    local oldValue = value
                    local newValue = not value
                    data.value = newValue
                    tbug_setEditValueFromContextMenu(self, row, data, oldValue)
                elseif typeValue == "string" then
                    --[[
                    if value ~= "" and data.dataEntry.typeId == RT.SCRIPTHISTORY_TABLE then
                        --CHAT_SYSTEM.textEntry.system:StartTextEntry("/script " .. data.value)
                        StartChatInput("/tbug " .. value, CHAT_CHANNEL_SAY, nil, false)
                    end
                    ]]
                end
            end
        end
    end
end

function TableInspectorPanel:populateMasterList(editTable, dataType)
    local masterList, n = self.masterList, 0
    for k, v in next, editTable do
        n = n + 1
        local dataEntry = masterList[n]
        if dataEntry then -- and dataType ~= RT.SCRIPTHISTORY_TABLE then
            dataEntry.typeId = dataType
            dataEntry.data.key = k
            dataEntry.data.value = v
        else
            local data = {key = k, value = v}
            masterList[n] = ZO_ScrollList_CreateDataEntry(dataType, data)
        end
    end
    return tbug_truncate(masterList, n)
end


function TableInspectorPanel:valueEditConfirmed(editBox, evalResult)
    local editData = self.editData
    --d(">editBox.updatedColumnIndex: " .. tos(editBox.updatedColumnIndex))
    local function confirmEditBoxValueChange(p_setIndex, p_editTable, p_key, p_evalResult)
        local l_ok, l_setResult = pcall(p_setIndex, p_editTable, p_key, p_evalResult)
        return l_ok, l_setResult
    end

    if editData then
        local editTable = editData.meta or self.subject
        local updateSpecial = false
        if editBox.updatedColumn ~= nil and editBox.updatedColumnIndex ~= nil then
            updateSpecial = true
        end
        if updateSpecial == false then
            local ok, setResult = confirmEditBoxValueChange(tbug.setindex, editTable, editData.key, evalResult)
            if not ok then return setResult end
            self.editData = nil
            editData.value = setResult
        else
            local typeId = editData.dataEntry.typeId
            --Update script history script or comment
            --[[
            if typeId and typeId == RT.SCRIPTHISTORY_TABLE then
                tbug.changeScriptHistory(editData.dataEntry.data.key, editBox, evalResult) --Use the row's dataEntry.data table for the key or it will be the wrong one after scrolling!
                editBox.updatedColumn:SetHidden(false)
                if evalResult == "" then
                    editBox.updatedColumn:SetText("")
                end
            --TypeId not given or generic
            else
            ]]
            if (not typeId or typeId == RT.GENERIC) then
                local ok, setResult = confirmEditBoxValueChange(tbug.setindex, editTable, editData.key, evalResult)
                if not ok then return setResult end
                self.editData = nil
                editData.value = setResult
            end
        end
        -- refresh only the edited row
        ZO_ScrollList_RefreshVisible(self.list, editData)
    end
    editBox:LoseFocus()
    editBox.updatedColumn = nil
    editBox.updatedColumnIndex = nil
end

function TableInspectorPanel:valueSliderConfirmed(sliderControl, evalResult)
--d("ControlInspectorPanel:valueSliderConfirmed-evalResult: "..tostring(evalResult))
    ZO_Tooltips_HideTextTooltip()
    local sliderData = self.sliderData
--d(">sliderControl.updatedColumnIndex: " .. tos(sliderControl.updatedColumnIndex))
    local function confirmSliderCtrlValueChange(p_setIndex, p_sliderTable, p_key, p_evalResult)
        local l_ok, l_setResult = pcall(p_setIndex, p_sliderTable, p_key, p_evalResult)
        return l_ok, l_setResult
    end

    if sliderData then
        local sliderTable = sliderData.meta or self.subject
        local updateSpecial = false
        if sliderData.updatedColumn ~= nil and sliderData.updatedColumnIndex ~= nil then
            updateSpecial = true
        end
        if updateSpecial == false then
            local ok, setResult = confirmSliderCtrlValueChange(tbug.setindex, sliderTable, sliderData.key, tonumber(evalResult))
            if not ok then return setResult end
            self.sliderData = nil
            sliderData.value = setResult
        else
            local typeId = sliderData.dataEntry.typeId
            --TypeId not given or generic
            if (not typeId or typeId == RT.GENERIC) then
                local ok, setResult = confirmSliderCtrlValueChange(tbug.setindex, sliderTable, sliderData.key, tonumber(evalResult))
                if not ok then return setResult end
                self.sliderData = nil
                sliderData.value = setResult
            end
        end
        -- refresh only the changed slider row
        ZO_ScrollList_RefreshVisible(self.list, sliderData)
    end
    sliderControl.updatedColumn = nil
    sliderControl.updatedColumnIndex = nil
end