local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")

--Event tracking code was spyed and copied from the addon Zgoo! All credits go to the authors.
--Authors: Errc, SinusPi, merlight, Rhyono

local getGlobalInspector

------------------------------------------------------------------------------------------------------------------------
local tbEvents = {}
tbug.Events = tbEvents

------------------------------------------------------------------------------------------------------------------------
--The possible events of the game
tbEvents.eventList = {}
local lookupEventName = tbug.Events.eventList
--Lookup table with key&value reversed
--tbEvents.eventListLookup = {}
--local lookupEvent = tbug.Events.eventListLookup

local realESOEventNames = tbug.realESOEventNames
local blacklistedEventIds = tbug.blacklistedEventIds

------------------------------------------------------------------------------------------------------------------------
--The events currently tracked/fired list
tbEvents.eventsTable = {}
tbEvents.eventsTableInternal = {}
tbEvents.eventsTableIncluded = {}
tbEvents.eventsTableExcluded = {}

tbEvents.IsEventTracking = false
tbEvents.AreAllEventsRegistered = false

------------------------------------------------------------------------------------------------------------------------
--Local helper pointers
local type = type
local strfind = string.find
local tinsert = table.insert


local eventsInspectorControl
local globalInspector

local throttledCall = tbug.throttledCall
local tbug_inspect = tbug.inspect
local tbug_inspectResults = tbug.inspectResults


------------------------------------------------------------------------------------------------------------------------
--Local helper functions
local l_globalprefixes = function(prefix)
	local l_safeglobalnext = function(tab,index)
		for k, v in zo_insecureNext, tab, index do
			if type(k) == "string" and strfind(k, prefix, 1, true) == 1 then
				return k, v
			end
		end
	end
	return l_safeglobalnext,_G,nil
end

--Add the possible events of the game (from _G table) to the eventsList
for k,v in l_globalprefixes("EVENT_") do
	if not blacklistedEventIds[v] and type(v)=="number" then
        --Lookup the real eventname
        local eventName = realESOEventNames[v] or k
        lookupEventName[v]=eventName
	end
end
setmetatable(tbug.Events.eventList,{__index = "-NO EVENT-"})

lookupEventName = tbug.Events.eventList

--Build the reversed lookup table
--[[
for k,v in pairs(lookupEventName) do
    lookupEvent[v]=k
end
]]

------------------------------------------------------------------------------------------------------------------------

local function getEventsTrackerInspectorControl()
    if eventsInspectorControl ~= nil then return eventsInspectorControl end
    --Start the event tracking by registering all events
    globalInspector = globalInspector or tbug.getGlobalInspector()
    if not globalInspector then return end
    eventsInspectorControl = globalInspector.panels and globalInspector.panels.events and globalInspector.panels.events.control
    return eventsInspectorControl
end
tbEvents.getEventsTrackerInspectorControl = getEventsTrackerInspectorControl

local function scrollScrollBarToIndex(list, index, animateInstantly)
    if not list then return end
    local onScrollCompleteCallback = function() end
    animateInstantly = animateInstantly or false
    ZO_ScrollList_ScrollDataIntoView(list, index, onScrollCompleteCallback, animateInstantly)
end

local function updateEventTrackerLines()
    --Is the events panel currently visible?
    local eventsPanel = globalInspector.panels.events
    local eventsPanelControl = eventsPanel.control
    if not eventsPanel or (eventsPanel and eventsPanelControl and eventsPanelControl:IsHidden() == true) then return end

    --Add the event to the masterlist of the outpt table
    -->Already called via eventsPanel:refreshData -> BuildMasterList
    --tbug.RefreshTrackedEventsList()

    --Update the visual ZO_ScrollList
    eventsPanel:refreshData()

    --Scroll to the bottom, if scrollbar is needed/shown
    local eventsListOutput = eventsPanel.list
    local numEventsInList = #eventsListOutput.data
    if numEventsInList <= 0 then return end

    local scrollbar = eventsListOutput.scrollbar
    if scrollbar and not scrollbar:IsHidden() then
        scrollScrollBarToIndex(eventsListOutput, numEventsInList, true)
    end

    --Add context menu to each row in the events table
end

------------------------------------------------------------------------------------------------------------------------
--The events tracker functions

--Add the event tracked to the list and show them at the output tab
function tbEvents.EventHandler(eventId, ...)
    if not tbEvents.IsEventTracking == true then return end

    local timeStampAdded = GetTimeStamp()
    local frameTime = GetFrameTimeMilliseconds()
    local eventParametersOriginal = {...}
    local eventTab = {}
    eventTab._timeStamp     = timeStampAdded
    eventTab._frameTime     = frameTime
    eventTab._eventName     = lookupEventName[eventId] or "? UNKNOWN EVENT ?"
    eventTab._eventId       = eventId
    for eventParamNo, eventParamValue in ipairs(eventParametersOriginal) do
        eventTab["param" .. tostring(eventParamNo)] = eventParamValue
    end

	local tabPosAdded = tinsert(tbEvents.eventsTableInternal, eventTab)

	--Add the added line to the output list as well, if the list is currently visible!
    throttledCall("UpdateTBUGEventsList", 100, updateEventTrackerLines)
end
local tbEvents_EventHandler = tbEvents.EventHandler

function tbug.UpdateEventsTrackingButton(selfVar)
    getGlobalInspector = getGlobalInspector or tbug.getGlobalInspector
--todo 20250110 remove debug data
tbug._debugUpdateEventsTrackingButton = {
    selfVar = selfVar,
    globalInspector = getGlobalInspector(),
}

    selfVar = selfVar or getGlobalInspector()
    local eventsButton = (selfVar and selfVar.eventsButton) or nil
    if eventsButton == nil then return end

    if tbEvents.IsEventTracking == true then
        eventsButton.toggleState = true
        eventsButton:fitText("E", 12)
        eventsButton:setMouseOverBackgroundColor(0.8, 0.0, 0, 0.4)
        eventsButton.tooltipText = "Event tracking is |c00FF00Enabled|r.\nClick to disable EVENT tracking"
    else
        eventsButton.toggleState = false
        eventsButton:fitText("e", 12)
        eventsButton:setMouseOverBackgroundColor(0, 0.8, 0, 1)
        eventsButton.tooltipText = "Event tracking is |cFF0000Disabled|r.\nClick to enable EVENT tracking"
    end
end
local UpdateEventsTrackingButton = tbug.UpdateEventsTrackingButton

--Fill the masterlist of the events output ZO_SortFilterList with the tracked events data rows
function tbug.RefreshTrackedEventsList()
    tbEvents.eventsTable = {}
    local intEventTable = tbEvents.eventsTableInternal
    if intEventTable == nil or #intEventTable == 0 then return end

    for numEventAdded, eventDataTable in ipairs(intEventTable) do
        tbEvents.eventsTable[numEventAdded] = eventDataTable
    end
end
--local RefreshTrackedEventsList = tbug.RefreshTrackedEventsList

function tbEvents.RegisterAllEvents(inspectorControl, override)
    if not inspectorControl then return end
    override = override or false
    --Event tracking is enabled?
    if not override == true and not tbEvents.IsEventTracking then return end
    --No need to register all events multiple times!
    if tbEvents.AreAllEventsRegistered == true then return end

    for id, _ in pairs(lookupEventName) do
        inspectorControl:RegisterForEvent(id, tbEvents_EventHandler)
    end
    tbEvents.AreAllEventsRegistered = true
end
local RegisterAllEvents = tbEvents.RegisterAllEvents

function tbEvents.UnRegisterAllEvents(inspectorControl, excludedEventsFromUnregisterTable, override)
    if not inspectorControl then return end
    override = override or false
    local keepEventsRegistered = (excludedEventsFromUnregisterTable ~= nil and type(excludedEventsFromUnregisterTable) == "table") or false
    if not keepEventsRegistered then
        if not override == true and tbEvents.IsEventTracking == true then return end
        if not tbEvents.AreAllEventsRegistered then return end
        for id, _ in pairs(lookupEventName) do
            inspectorControl:UnregisterForEvent(id)
        end
        tbEvents.AreAllEventsRegistered = false
    else
        if not override == true and not tbEvents.IsEventTracking == true then return end
        for id, _ in pairs(lookupEventName) do
            inspectorControl:UnregisterForEvent(id)
        end
        for _, eventId in ipairs(excludedEventsFromUnregisterTable) do
            tbEvents.RegisterSingleEvent(inspectorControl, eventId)
        end
    end
end
local UnRegisterAllEvents = tbEvents.UnRegisterAllEvents

function tbEvents.UnRegisterSingleEvent(inspectorControl, eventId)
    if not inspectorControl then return end
    --Event tracking is not enabled?
    if not tbEvents.IsEventTracking == true then return end
    inspectorControl:UnregisterForEvent(eventId)
end
local UnRegisterSingleEvent = tbEvents.UnRegisterSingleEvent

function tbEvents.RegisterSingleEvent(inspectorControl, eventId)
    if not inspectorControl then return end
    --Event tracking is not enabled?
    if not tbEvents.IsEventTracking == true then return end
    inspectorControl:RegisterForEvent(eventId, tbEvents_EventHandler)
end
local RegisterSingleEvent = tbEvents.RegisterSingleEvent

function tbEvents.ReRegisterAllEvents(inspectorControl)
    if not inspectorControl then return end
    --Event tracking is not enabled?
    tbug.Events.eventsTableIncluded = {}
    tbug.Events.eventsTableExcluded = {}
    UnRegisterAllEvents(inspectorControl, nil, true)
    RegisterAllEvents(inspectorControl, true)
end

function tbug.StartEventTracking()
    --Start the event tracking by registering either all events, or if any are excluded/included respect those
    if tbEvents.IsEventTracking == true then return end
    tbEvents.IsEventTracking = true
    UpdateEventsTrackingButton(nil)

    eventsInspectorControl = eventsInspectorControl or getEventsTrackerInspectorControl()
    if not eventsInspectorControl then
        tbEvents.IsEventTracking = false
        return
    end
    --Any included "only" to show?
    if #tbEvents.eventsTableIncluded > 0 then
        UnRegisterAllEvents(eventsInspectorControl, nil)
        for _, eventId in ipairs(tbEvents.eventsTableIncluded) do
             RegisterSingleEvent(eventsInspectorControl, eventId)
        end

    --Any excluded to "not" show?
    elseif #tbEvents.eventsTableExcluded > 0 then
        RegisterAllEvents(eventsInspectorControl)
        for _, eventId in ipairs(tbEvents.eventsTableExcluded) do
             UnRegisterSingleEvent(eventsInspectorControl, eventId)
        end

    --Else: Register all events
    else
        RegisterAllEvents(eventsInspectorControl)
    end

    --Show the UI/activate the events tab
    tbug.slashCommandEvents()
end
local startEventTracking = tbug.StartEventTracking

function tbug.StopEventTracking()
    if not tbEvents.IsEventTracking == true then return false end
    tbEvents.IsEventTracking = false
    UpdateEventsTrackingButton(nil)

    eventsInspectorControl = eventsInspectorControl or getEventsTrackerInspectorControl()
    if not eventsInspectorControl then return end
    UnRegisterAllEvents(eventsInspectorControl)

    --if the events panel is shown update it one time to show the last incoming events properly
    if not eventsInspectorControl:IsHidden() then
        zo_callLater(function()
            updateEventTrackerLines()
        end, 1500)
    end

    return true
end
local stopEventTracking = tbug.StopEventTracking


--Saved tracked events to SavedVariables subtable savedEvents
local function addSavedEvents(doRestartEventsTracking)
    if tbEvents.IsEventTracking then return end
    local savedEvents = tbug.savedVars.savedEvents
    savedEvents = savedEvents or {}


    local intEventTable = tbEvents.eventsTableInternal
    if ZO_IsTableEmpty(intEventTable) then return end

    local newSavedEventsEntry = {
        _timeStamp = GetTimeStamp(),
        events = ZO_ShallowTableCopy(intEventTable),
    }
    local indexAdded = tinsert(savedEvents, newSavedEventsEntry)
    indexAdded = indexAdded or #savedEvents
    d("[TBUG]Saved the currently tracked #" .. tostring(#intEventTable)  .." events as index: " .. tostring(indexAdded))

    if not doRestartEventsTracking then return end
    startEventTracking()
end

function tbug.SaveEventsTracked()
    if stopEventTracking() == true then
        if not eventsInspectorControl:IsHidden() then
            --Wait 1,5s
            zo_callLater(function()
                addSavedEvents(true)
            end, 1501)
        else
            addSavedEvents(true)
        end
    else
        addSavedEvents(false)
    end
end

function tbug.LoadEventsTracked(key)
    local savedEvents = tbug.savedVars.savedEvents
    if key == nil or savedEvents == nil or savedEvents[key] == nil then return end
    --Load the saved events and show them in an inspector UI!
    tbug_inspectResults(nil, nil, savedEvents[key], true, savedEvents[key])
end


--At startup of the addon EVENT_ADD_ON_LOADED: Automatically load the event tracking?
function tbug.AutomaticEventTrackingCheck()
    if not tbug.savedVars.enableEventTrackerAtStartup then return end
    startEventTracking()
end
