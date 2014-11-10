-- NOTE : Limitation of mios UI5
-- The compressed modules must be declared with module(), and not using any of the alternative forms.
-- See http://wiki.micasaverde.com/index.php/UI4_UI5_Migration
module("WatcherManager", package.seeall)

require("L_Tools")
local json = require("json") -- See http://json.luaforge.net/

local WatcherManager = {
	_VERSION = "0.0.1"
}

local _taskId = -1
local _rules = {}
local _indexTriggersByEvent = {}
local _verbosity = 1
local _minRecurentTimeDelay = 60

local _currentTime -- for debug
local _currentHookName = ""

local function log(msg, lvl, methodName, isFromHook)
	lvl = tonumber(lvl) or 1
	if (lvl > _verbosity) then
		return
	end
	isFromHook = isFromHook or false
	if (methodName == nil) then
		methodName = debug.getinfo(2).name
		if (methodName == "log") then
			local i = 3
			while (debug.getinfo(i) ~= nil) do
				if (debug.getinfo(i).name == "doHook") then
					isFromHook = true
					break
				end
				i = i + 1
			end
			if isFromHook then
				methodName = "[WatcherManager][".. _currentHookName .. "]"
			else
				methodName = debug.getinfo(4).name
			end
		else
			methodName = "[WatcherManager." .. tostring(methodName) .. "]"
		end
	else
		methodName = "[WatcherManager." .. tostring(methodName) .. "]"
	end

	--luup.log(tostring(lvl) .. "-" .. msg, 50)
	luup.log(string.rpad(methodName, 35) .. " " .. msg, 50)
end

local function getTimeDelay (action)
	if (type(action.timeDelay) == "function") then
		timeDelay = action.timeDelay()
	else
		timeDelay = action.timeDelay
	end
	if (
		(action.event == "reminder")
		and ((timeDelay == nil) or (timeDelay < _minRecurentTimeDelay))
	) then
		-- Sécurité sur le temps minimal pour les actions récurentes
		log("Recurent action min delay is set to " .. tostring(_minRecurentTimeDelay))
		timeDelay = _minRecurentTimeDelay
	end
	return timeDelay or 0
end

local function getMessage (item)
	if (item == nil) then
		return ""
	end
	return "Rule '" .. tostring(item._ruleName) .. "' - " .. tostring(item._subType) .. " #" .. tostring(item._id) .. " of type '" .. tostring(item._type) .. "'"
end

local function initMultiValueKey(object, multiValueKey, monoValueKey)
	if (object[multiValueKey] == nil) then
		if (object[monoValueKey] ~= nil) then
			object[multiValueKey] = { object[monoValueKey] }
		else
			object[multiValueKey] = {}
		end
	end
end

local function checkParameters (input, parameters)
	local isOk = true
	local msg = getMessage(input)
	if (input == nil) then
		log(msg .. " - Input is not defined", 1)
		isOk = false
	else
		for _, parameterAND in ipairs(parameters) do
			-- AND
			if (type(parameterAND) == "string") then
				if (input[parameterAND] == nil) then
					log("SETTING ERROR - " .. msg .. " - Parameter '" .. parameterAND .. "' is not defined", 1)
					isOk = false
				elseif ((type(input[parameterAND]) == "table") and (next(input[parameterAND]) == nil)) then
					log("SETTING ERROR - " .. msg .. " - Parameter '" .. parameterAND .. "' is empty", 1)
					isOk = false
				end
			elseif (type(parameterAND) == "table") then
				-- OR
				local isOk2 = false
				for _, parameterOR in ipairs(parameterAND) do
					if (input[parameterOR] ~= nil) then
						if (
							(type(input[parameterOR]) ~= "table")
							or ((type(input[parameterOR]) == "table") and (next(input[parameterOR]) ~= nil))
						) then
							isOk2 = true
						end
					end
				end
				if not isOk2 then
					log("SETTING ERROR - " .. msg .. " - Not a single parameter in " .. json.encode(parameterAND) .. "' is defined or not empty", 1)
					isOk = false
				end
			end
		end
	end
	if not isOk then
		log("SETTING ERROR - " .. msg .. " - There's a problem with setting of input : " .. json.encode(input), 2)
	end
	return isOk
end

	-- **************************************************
	-- Hooks
	-- **************************************************

	local _hooks = {}

	-- Add a hook
	function WatcherManager.addHook (moduleName, event, callback)
		if (_hooks[event] == nil) then
			_hooks[event] = {}
		end
		log("Add hook for event '" .. event .. "'", 1)
		table.insert(_hooks[event], { moduleName, callback} )
	end

	-- Execute a hook for an event and a rule
	local function doHook (event, rule)
		if (_hooks[event] == nil) then
			return true
		end
		local nbHooks = table.getn(_hooks[event])
		if (nbHooks == 1) then
			log("Rule '" .. rule.name .. "' - Event '" .. event .. "' - There is 1 hook to do", 2)
		elseif (nbHooks > 1) then
			log("Rule '" .. rule.name .. "' - Event '" .. event .. "' - There are " .. tostring(nbHooks) .. " hooks to do" ,2)
		end
		local isHookOK = true
		for _, hook in ipairs(_hooks[event]) do
			_currentHookName = hook[1]
			local callback
			if (type(hook[2]) == "function") then
				callback = hook[2]
			elseif ((type(hook[2]) == "string") and (type(_G[hook[2]]) == "function")) then
				callback = _G[hook[2]]
			end
			if (callback ~= nil) then
				if not callback(rule) then
					isHookOK = false
				end
			end
		end
		return isHookOK
	end

	-- **************************************************
	-- Condition
	-- (rule condition, rule trigger, action condition)
	-- **************************************************

local ConditionTypes = {
	_index = {
		--["value"] = "value",
		["value-"] = "value",
		["value+"] = "value",
		["value<>"] = "value",
		--["rule"] = "rule",
		--["timer"] = "timer",
		--["time"] = "time",
		["time-"] = "time",
		["time+"] = "time"
	}
}
-- Unknown Condition type
setmetatable(ConditionTypes,{
	__index = function(t, conditionTypeName)
		local conditionTypeEquivalentName = ConditionTypes._index[conditionTypeName]
		if (conditionTypeEquivalentName == nil) then
			log("SETTING WARNING - Condition type '" .. tostring(conditionTypeName) .. "' is unknown", "ConditionTypes.get")
			conditionTypeEquivalentName = "unknown"
		end
		return ConditionTypes[conditionTypeEquivalentName]
	end
})


	-- ConditionTypes.get = function (typeName)
		-- local conditionTypeName = ConditionTypes._index[typeName] or "unknown"
		-- return ConditionTypes[conditionTypeName]
	-- end

	ConditionTypes.unknown = {
		init = function (condition)
			local msg = ConditionTypes.getMessage(condition)
			
		end,
		check = function (condition)
			local msg = ConditionTypes.getMessage(condition)
			log("SETTING WARNING - " .. msg .. " - Condition type '" .. tostring(condition.type) .. "' is unknown")
		end,
		start = function (condition)
		end,
		updateStatus = function (condition)
		end
	}

	-- Condition of type 'value'
	ConditionTypes.value = {
		init = function (condition)
			initMultiValueKey(condition, "devices", "device")
			initMultiValueKey(condition, "deviceIds", "deviceId")
			if (table.getn(condition.devices) > 0) then
				condition.deviceIds = {}
				for i, device in ipairs(condition.devices) do
					condition.deviceIds[i] = DeviceHelper.getIdByName(device)
				end
			end
		end,

		check = function (condition)
			local msg = getMessage(condition)
			if not checkParameters(condition, {"devices", "service", "variable", "value"}) then
				return false
			else
				for j, device in ipairs(condition.devices) do
					if (condition.deviceIds[j] == nil) then
						log("SETTING ERROR - " .. msg .. " - Device '" .. device .. "' is unknown")
						return false
					end
				end
			end
			return true
		end,

		register = function (trigger)
			local msg = getMessage(trigger)
			for j, deviceId in ipairs(trigger.deviceIds) do
				-- Mise à jour des index trigger par évènement
				local eventName = trigger.service .. "-" .. trigger.variable .. "-" .. tostring(deviceId)
				if (_indexTriggersByEvent[eventName] == nil) then
					-- Enregistrement de la surveillance du module pour ce service et cette variable
					_indexTriggersByEvent[eventName] = {}
					log(msg .. " - Watch device '" .. trigger.devices[j] .. "'", 3)
					luup.variable_watch("WatcherManager.onDeviceValueIsUpdated", trigger.service, trigger.variable, deviceId)
				else
					log(msg .. " - Watch device '" .. trigger.devices[j] .. "' (register already done)", 3)
				end
				if not table.contains(_indexTriggersByEvent[eventName], trigger) then
					table.insert(_indexTriggersByEvent[eventName], trigger)
				end
			end
		end,

		updateStatus = function (condition)
			local msg = getMessage(condition)
			local context = condition._context
			for j, device in ipairs(condition.devices) do
				-- Condition of type 'value' / 'value-' / 'value+' / 'value<>'
				if (condition.deviceId == nil) then
					condition.deviceId = DeviceHelper.getIdByName(condition.device)
					condition.device = luup.devices[condition.deviceId].description
				end
				msg = msg .. " for device #" .. tostring(condition.deviceId) .. "-'" .. condition.device .. "'"
							.. " - '" .. condition.service .. "-" ..  condition.variable .. "'"

				-- Update value if too old (not recently updated by a trigger for example)
				if (os.difftime(os.time(), context.lastUpdate) >= 1 ) then
					msg = msg .. " (value retrieved)"
					context.value, context.lastUpdate = luup.variable_get(condition.service, condition.variable, condition.deviceId)
				end

				-- Status update
				condition._status = "1"
				if (condition.value ~= nil) then
					-- a threshold is defined
					if ((context.value == nil)
						or ((condition.type == "value") and (tostring(condition.value) ~= tostring(context.value)))
						or ((condition.type == "value-") and (tonumber(condition.value) < tonumber(context.value)))
						or ((condition.type == "value+") and (tonumber(condition.value) > tonumber(context.value)))
					) then
						-- Threshold is not respected
						msg = msg .. " - is inactive - The value condition is not respected"
						condition._status = "0"
					else
						msg = msg .. " - is active -  The value condition is respected"
					end
				else
					-- No specific value condition on that condition
					msg = msg .. " - is active - The condition has no value condition"
				end
			end
			log(msg, 3)
		end

	}

	-- Condition of type 'rule'
	ConditionTypes.rule = {
		init = function (condition)
			initMultiValueKey(condition, "rules", "rule")
		end,

		check = function (condition)
			local msg = getMessage(condition)
			if not checkParameters(condition, {"rules", "status"}) then
				return false
			else
				for _, ruleName in ipairs(condition.rules) do
					if not WatcherManager.getRule(ruleName) then
						log("SETTING ERROR - " .. msg .. " - Rule '" .. ruleName .. "' is unknown")
						return false
					end
				end
			end
			return true
		end,

		register = function (trigger)
			local msg = getMessage(trigger)
			for _, ruleToWatchName in ipairs(trigger.rules) do
				local eventName = "status-" .. ruleToWatchName
				-- Enregistrement de la surveillance du status pour cette règle
				if (_indexTriggersByEvent[eventName] == nil) then
					_indexTriggersByEvent[eventName] = {}
				end
				log(msg .. " - Watch status for rule '" .. ruleToWatchName .. "'", 3)
				if not table.contains(_indexTriggersByEvent[eventName], trigger) then
					table.insert(_indexTriggersByEvent[eventName], trigger)
				end
			end
		end,

		updateStatus = function (condition)
			local msg = getMessage(condition)
			for _, ruleName in ipairs(condition.rules) do
				local rule = _rules[ruleName]
				if (rule._status ~= condition.status) then
					msg = msg .. " is inactive - The value condition is not respected"
					condition._status = "0"
				else
					msg = msg .. " is active - The value condition is respected"
					condition._status = "1"
				end
			end
			log(msg, 3)
		end
	}

	-- Condition of type 'timer'
	ConditionTypes.timer = {
		init = function (condition)
			local msg = getMessage(condition)
		end,

		-- See http://wiki.micasaverde.com/index.php/Luup_Lua_extensions#function:_call_timer
		check = function (condition)
			local msg = getMessage(condition)
			if not checkParameters(condition, {"timerType", {"time", "days"}}) then
				return false
			end
			return true
		end,

		register = function (trigger)
			local msg = getMessage(trigger)
			log(msg .. " - Register timer '" .. json.encode(trigger) .. "'", 3)
			luup.call_timer("WatcherManager.onTimerIsTriggered", trigger.timerType, trigger.time, trigger.days, trigger._ruleName .. ";" .. trigger._id)
		end,

		updateStatus = function (condition)
			local msg = getMessage(condition)
			if (condition._status == "1") then
					msg = msg .. " is active"
				else
					msg = msg .. " is not active"
				end
			log(msg, 3)
		end
	}

	-- Condition of type 'time'
	ConditionTypes.time = {
		init = function (condition)
		end,

		-- See http://wiki.micasaverde.com/index.php/Luup_Lua_extensions#function:_call_timer
		check = function (condition)
			if (((condition.type == "time-") or (condition.type == "time+")) and not checkParameters(condition, {"time"})) then
				return false
			elseif not checkParameters(condition, {{"time", "between"}}) then
				return false
			end
			return true
		end,

		register = function (trigger)
			-- Nothing to do
		end,

		updateStatus = function (condition)
			local msg = getMessage(condition)
			local currentTime = _currentTime or os.date('%H:%M:%S')
			condition._status = "1"
			if ((condition.type == "time-") and (currentTime > condition.time)) then -- under
				condition._status = "0"
			elseif ((condition.type == "time+") and (currentTime < condition.time)) then -- above
				condition._status = "0"
			elseif (condition.type == "time") then
				if (condition.between ~= nil) then -- between
					if ((currentTime < condition.between[1]) or (currentTime > condition.between[2])) then
						condition._status = "0"
					end
				elseif (currentTime ~= condition.time) then -- exact time
					condition._status = "0"
				end
			end
			log(msg, 3)
		end

	}

	-- **************************************************
	-- Conditions
	-- **************************************************

	local function initConditions (ruleName, conditions, subType)
		if (conditions == nil) then
			conditions = {}
		end
		for i, condition in ipairs(conditions) do
			condition._id = i
			condition._ruleName = ruleName
			condition._level = tonumber(condition.level) or 0
			condition._context = {lastUpdate = 0}
			condition._type = condition.type or ""
			if (subType ~= nil) then
				condition._subType = subType
			end
			ConditionTypes[condition._type].init(condition)
		end
		return conditions
	end

	local function checkConditionsSettings (conditions)
		local isOk = true
		for i, condition in ipairs(conditions) do
			if not checkParameters(condition, {"type"}) then
				isOk = false
			elseif not ConditionTypes[condition._type].check(condition) then
				isOk = false
			end
		end
		return isOk
	end

	local function getConditionsMaxActiveLevel (conditions)
		local level = 0
		for _, condition in ipairs(conditions) do
			if ((condition._status == "1") and (condition._level > level)) then
				level = condition._level
			end
		end
		return level
	end

	local function isMatchingAllConditions (conditions)
		-- if (conditions == nil) then
			-- return true
		-- end
		isMatching = true
		for _, condition in ipairs(conditions) do
			--ConditionTypes.get(condition._type).updateStatus(condition)
			ConditionTypes[condition._type].updateStatus(condition)
			if (condition._status == "0") then
				isMatching = false
			end
		end
		return isMatching
	end

	local function isMatchingAtLeastOneCondition (conditions)
		-- if (conditions == nil) then
			-- return true
		-- end
		isMatching = false
		for _, condition in ipairs(conditions) do
			--ConditionTypes.get(condition._type).updateStatus(condition)
			ConditionTypes[condition._type].updateStatus(condition)
			if (condition._status == "1") then
				isMatching = true
			end
		end
		return isMatching
	end

	-- **************************************************
	-- Messages
	-- **************************************************

	local function getTimeAgo(timestamp)
		if (timestamp == nil) then
			return "", ""
		end
		local timeInterval = os.difftime(os.time(), timestamp)
		local days = math.floor(timeInterval / 86400)
		local daysRemainder = timeInterval % 86400
		local hours = math.floor(daysRemainder / 3600)
		local hoursRemainder = daysRemainder % 3600
		local minutes = math.floor(hoursRemainder / 60)
		local seconds = hoursRemainder % 60

		local timeAgo = ""
		local timeAgoFull = ""

		-- Days
		if (days > 0) then
			timeAgo = timeAgo .. tostring(days) .. "D"
			if (daysRemainder > 0) then
				timeAgo = timeAgo .. "T"
			end
		end
		-- Days full
		if (days > 1) then
			timeAgoFull = tostring(days) .. " jours"
		elseif (days == 1) then
			timeAgoFull = "1 jour"
		end

		-- Hours
		if ((string.len(timeAgo) > 0) or (hours > 0)) then
			timeAgo = timeAgo .. tostring(hours) .. "H"
		end
		-- Hours full
		if ((string.len(timeAgoFull) > 0) and (hours > 0)) then
			timeAgoFull = timeAgoFull .. " et "
		end
		if (hours > 1) then
			timeAgoFull = timeAgoFull .. tostring(hours) .. " heures"
		elseif (hours == 1) then
			timeAgoFull = timeAgoFull .. "une heure"
		end

		-- Minutes
		if ((string.len(timeAgo) > 0) or (minutes > 0)) then
			timeAgo = timeAgo .. tostring(minutes) .. "M"
		end
		-- Minutes full
		if (days == 0) then
			if ((string.len(timeAgoFull) > 0) and (minutes > 0)) then
				timeAgoFull = timeAgoFull .. " et "
			end
			if (minutes > 1) then
				timeAgoFull = timeAgoFull .. tostring(minutes) .. " minutes"
			elseif (minutes == 1) then
				timeAgoFull = timeAgoFull .. "une minute"
			end
		end

		-- Seconds
		if ((string.len(timeAgo) > 0) or (seconds > 0)) then
			timeAgo = timeAgo .. tostring(seconds) .. "S"
		end
		-- Seconds full
		if ((days == 0) and (hours == 0)) then
			if ((string.len(timeAgoFull) > 0) and (seconds > 0)) then
				timeAgoFull = timeAgoFull .. " et "
			end
			if (seconds > 1) then
				timeAgoFull = timeAgoFull .. tostring(seconds) .. " secondes"
			elseif (seconds == 1) then
				timeAgoFull = timeAgoFull .. "une seconde"
			end
		end

		return "P" .. timeAgo, timeAgoFull
	end

	function WatcherManager.getEnhancedMessage (message, context)
		if (message == nil) then
			return false
		end
		if (context == nil) then
			return message
		end
		if (string.find(message, "#value#")) then
			-- Most recent value from triggers and conditions
			message = string.gsub(message, "#value#", tostring(context.value))
		end
		local timeAgo, timeAgoFull = getTimeAgo(context.lastStatusUpdate)
		if (string.find(message, "#duration#")) then
			message = string.gsub(message, "#duration#", timeAgo)
		end
		if (string.find(message, "#durationfull#")) then
			message = string.gsub(message, "#durationfull#", timeAgoFull)
		end
		return message
	end

	-- **************************************************
	-- Rule actions
	-- **************************************************

	local function initRuleActions (ruleName, actions)
		if (actions == nil) then
			actions = {}
		end
		for i, action in ipairs(actions) do
			action._id = i
			action._subType = "Action"
			action._ruleName = ruleName
			action._context = {lastUpdate = 0}
			action._type = "ActionType"
			if (action.level ~= nil) then
				action.level = tonumber(action.level) or 0
			end
			initMultiValueKey(action, "types", "type")
			initMultiValueKey(action, "devices", "device")
			action.conditions = initConditions(ruleName .. "-Action#" .. tostring(i), action.conditions, "Condition")
		end
		return actions
	end

	local function checkRuleActionsSettings (actions)
		local isOk = true
		for i, action in ipairs(actions) do
			if not checkParameters(action, {{"types", "callback"}}) then
				isOk = false
			elseif ((action.types ~= nil) and table.contains(action.types, "action") and not checkParameters(action, {"devices", "service", "action", "arguments"})) then
				isOk = false
			elseif not checkConditionsSettings(action.conditions) then
				isOk = false
			end
		end
		return isOk
	end

	-- **************************************************
	-- WatcherManager actions
	-- **************************************************

	local _actions = {}

	-- Add an action
	function WatcherManager.addAction (actionType, actionFunction)
		if (_actions[actionType] ~= nil) then
			log("ERROR - Action of type '" .. actionType ..  "' is already defined", 1)
		end
		_actions[actionType] = actionFunction
	end

	-- Default action
	WatcherManager.addAction(
		"action",
		function (action, context)
			local deviceIds = {}
			if (action.devices ~= nil) then
				for _, deviceName in ipairs(action.devices) do
					table.insert(deviceIds, DeviceHelper.getIdByName(deviceName))
				end
			else
				deviceIds = { DeviceHelper.getIdByName(action.device) }
			end
			log("Action '" .. action.action .. "' for devices " .. json.encode(deviceIds), 3)
			for _, deviceId in ipairs(deviceIds) do
				luup.call_action(action.service, action.action, action.arguments, deviceId)
			end
		end
	)

	-- Execute one action from a rule
	function WatcherManager.doRuleAction (ruleName, actionId)
		local params = string.split(ruleName, ";")
		if (table.getn(params) > 1) then
			ruleName = params[1]
			actionId = tonumber(params[2])
		end
		local message = "Rule '" .. ruleName .. "'"
		local rule = _rules[ruleName]
		local action = rule.actions[actionId]
		if not doHook("beforeDoingAction", ruleName, actionId) then
			log(message .. " - A hook prevent from doing action #" .. tostring(actionId), 3, "doRuleAction")
			return
		end
		if (action.callback ~= nil) then
			-- Action de type callback
			log(message .. " - Do action #" .. tostring(actionId) ..  " of type 'function'", 3, "doRuleAction")
			local ok, err
			if (type(action.callback) == "function") then
				ok, err = pcall(action.callback, rule._context)
			elseif ((type(action.callback) == "string") and (type(_G[action.callback]) == "function")) then
				ok, err = pcall(_G[action.callback], rule._context)
			end
			assert(ok, "ERROR: " .. tostring(err))
			if not ok then 
				log("ERROR: " .. err, 1, "doRuleAction")
			end
		elseif (action.types ~= nil) then
			for _, actionType in ipairs(action.types) do
				-- Action enregistrée
				log(message .. " - Do action #" .. tostring(actionId) ..  " of type '" .. actionType .. "'", 3, "doRuleAction")
				local ok, err = pcall(_actions[actionType], action, rule._context)
				assert(ok, "ERROR: " .. tostring(err))
				if not ok then
					log("ERROR:" .. err, 1, "doRuleAction")
				end
			end
		else
			log(message .. " - Don't know what to do !", 1, "doRuleAction")
		end
	end

	-- Execute one recurent action from a rule
	function WatcherManager.doRuleRecurrentAction (ruleName, actionId)
		local params = string.split(ruleName, ";")
		if (table.getn(params) > 1) then
			ruleName = params[1]
			actionId = tonumber(params[2])
		end
		local rule = _rules[ruleName]
		local action = rule.actions[actionId]
		local timeDelay = getTimeDelay(action)

		local msg = "Rule '" .. rule.name .. "' - Recurent action #" .. tostring(actionId)
		if (action.level ~= nil) then
			msg = msg .. " for level '" .. tostring(action.level) .. "'"
		end

		-- Check if rule is disabled
		if (rule._isDisabled) then
			log(msg .. " - Don't do action (and don't retry) - Rule is disabled", 1, "doRuleRecurrentAction")
			return false
		end

		-- Check if the rule is still active
		if (rule._status ~= "1") then
			log(msg .. " - Don't do action (and don't retry) - Rule is no more active", 1, "doRuleRecurrentAction")
			return false
		end

		-- From how long is the rule active ? 
		-- Check that there was no activation of the rule since last call and therefore a new timer
		if (os.difftime(os.time(), rule._lastStatusTime) < timeDelay) then
			log(msg .. " - Don't do action - Rule is active since too few time (it is watched by another process)", 1, "doRuleRecurrentAction")
			return false
		end

		log(msg .. " - About to do recurent action", 3, "doRuleRecurrentAction")

		-- Reminder action (if rule main conditions and action conditions are still respected)
		if not isMatchingAllConditions(rule.conditions) then
			-- The rule main conditions are no more respected : deactive the rule
			log(msg .. " - Don't do recurent action - Rule conditions are no more respected", 2, "doRuleRecurrentAction")
			WatcherManager.setRuleStatus(rule, "0")
		else
			if not isMatchingAllConditions(action.conditions) then
				-- The recurent action conditions are no more respected : does nothing until the next call is made
				log(msg .. " - Don't do recurent action - Rule is still active but action conditions are no more respected", 3, "doRuleRecurrentAction")
			elseif ((action.level ~= nil) and (action.level ~= rule._level)) then
				-- The action level does not match with current rule level
				log(msg .. " - Don't do recurent action - The rule current level '" .. tostring(rule._level) .. "' is not respected", 3, "doRuleRecurrentAction")
			else
				log(msg .. " - Do recurent action - Rule is still active and conditions are still respected", 3, "doRuleRecurrentAction")
				luup.call_delay("WatcherManager.doRuleAction", 0, rule.name .. ";" .. tostring(actionId))
			end
			-- Relance de la surveillance du statut de la règle
			log(msg .. " - Retry recurent action in " .. timeDelay .. " seconds", 2, "doRuleRecurrentAction")
			luup.call_delay("WatcherManager.doRuleRecurrentAction", timeDelay, rule.name .. ";" .. tostring(actionId))
		end

		return true
	end

	-- Do actions from a rule for an event and optionaly a level
	function WatcherManager.doRuleActions (ruleName, event, level)
		local rule = WatcherManager.getRule(ruleName)

		-- Check if rule is disabled
		if (rule._isDisabled) then
			log("Rule '" .. rule.name .. "' is disabled - Do nothing", 1)
			return false
		end

		if (level ~= nil) then
			log("Rule '" .. rule.name .. "' - Do actions for event '" .. event .. "' and level '" .. tostring(level) .. "'", 1)
		else
			log("Rule '" .. rule.name .. "' - Do actions for event '" .. event .. "'", 1)
		end
		-- Recherche des actions de la règle liées à l'évènement
		local isAtLeastOneActionToDo = false
		for actionId, action in ipairs(rule.actions) do
			local msg = "Rule '" .. rule.name .. "' - Action #" .. tostring(actionId) .. " for event '" .. event .. "'"
			if (action.level ~= nil) then
				msg = msg .. " and level '" .. tostring(action.level) .. "'"
			end
			if ((event == "reminder") and (action.event == event)) then
				-- Action récurente
				isAtLeastOneActionToDo = true
				local timeDelay = getTimeDelay(action)
				log(msg .. " - Do recurent action in " .. tostring(timeDelay) .. " second(s)", 2)
				luup.call_delay("WatcherManager.doRuleRecurrentAction", timeDelay, rule.name .. ";" .. tostring(actionId))
			elseif ((event == nil) or (action.event == nil) or (action.event == event)) then
				-- L'action correspond à l'évènement (ou est valable pour tous les évènements)
				if not isMatchingAllConditions(action.conditions) then
					-- Les conditions particulières de l'action ne sont pas respectées
					log(msg .. " - Don't do action - The action conditions are not respected", 2)
				elseif ((level ~= nil) and ((action.level == nil) or (action.level ~= level))) then
					-- Le niveau de l'action ne correspond pas au niveau explicitement demandé
					log(msg .. " - Don't do action - The requested level '" .. tostring(level) .. "' is not respected", 2)
				elseif ((level == nil) and (action.level ~= nil) and (action.level ~= rule._level)) then
					-- Le niveau de l'action ne correspond pas à l'actuel de la règle
					log(msg .. " - Don't do action - The rule current level '" .. tostring(rule._level) .. "' is not respected", 2)
				else
					-- Exécution de l'action
					isAtLeastOneActionToDo = true
					local timeDelay = getTimeDelay(action)
					if (timeDelay > 0) then
						log(msg .. " - Do action in " .. tostring(timeDelay) .. " second(s)", 2)
					else
						log(msg .. " - Do action immediately", 2)
					end
					-- Les appels se font en asynchrone pour éviter les blocages
					luup.call_delay("WatcherManager.doRuleAction", timeDelay, rule.name .. ";" .. tostring(actionId))
				end
			end
		end
		if not isAtLeastOneActionToDo then
			local msg = "Rule '" .. rule.name .. "' - No action to do for event '" .. event .. "'"
			if (level ~= nil) then
				msg = msg .. " and level '" .. tostring(level) .. "'"
			end
			log(msg, 2)
		end
	end

	-- **************************************************
	-- Rules
	-- **************************************************

	-- Rule initialisation
	local function initRule (rule)
		rule._isDisabled = false
		rule._level = 0
		rule._status = nil
		rule._lastStatusTime = nil
		rule._context = {lastUpdate = 0}
		rule.triggers   = initConditions(rule.name, rule.triggers, "Trigger")
		rule.conditions = initConditions(rule.name, rule.conditions, "Condition")
		rule.actions    = initRuleActions(rule.name, rule.actions)
	end

	local function checkRuleSettings (rule)
		if (
			checkConditionsSettings(rule.triggers)
			and checkConditionsSettings(rule.conditions)
			and checkRuleActionsSettings(rule.actions)
		) then
			return true
		else
			luup.task("Error in settings for rule '" .. rule.name .. "' (see log)", 2, "WatcherManager", _taskId)
			return false
		end
	end

	-- Compute rule status according to conditions and triggers
	local function computeRuleStatus (rule)
		if (rule._isDisabled) then
			return nil
		end
		local msg = "Rule '" .. rule.name .. "'"
		log(msg .. " - Compute status", 3)
		local status = "1"

		-- Conditions principales de la règle (toutes)
		if (table.getn(rule.conditions) == 0) then
			msg = msg .. " - No main condition"
		elseif isMatchingAllConditions(rule.conditions) then
			msg = msg .. " - The main conditions are all respected"
		else
			msg = msg .. " - The main conditions are not respected"
			status = "0"
		end

		-- Triggers de la règle (au moins un)
		if (isMatchingAtLeastOneCondition(rule.triggers)) then
			msg = msg .. " - At least one trigger is active"
		else
			msg = msg .. " - No trigger is active"
			status = "0"
		end

		log(msg .. " - Status: " .. status, 2)
		return status
	end

	-- Update the active rule level
	local function updateRuleLevel (rule)
		rule._level = 0
		local conditionsLevel = getConditionsMaxActiveLevel(rule.conditions)
		if (conditionsLevel > rule._level) then
			rule._level = conditionsLevel
		end
		local triggersLevel = getConditionsMaxActiveLevel(rule.triggers)
		if (triggersLevel > rule._level) then
			rule._level = triggersLevel
		end
	end

	-- Update rule context
	local function updateRuleContext (rule)
		rule._context.lastStatusUpdate = rule._lastStatusTime
		if (rule.conditions._context.lastUpdate > rule._context.lastUpdate) then
			rule._context.lastUpdate = rule.conditions._context.lastUpdate
			rule._context.value = rule.conditions._context.value
		end
		if (rule.triggers._context.lastUpdate > rule._context.lastUpdate) then
			rule._context.lastUpdate = rule.triggers._context.lastUpdate
			rule._context.value = rule.triggers._context.value
		end
	end

	-- Add a rule
	function WatcherManager.addRule (rule)
		if ((rule == nil) or (type(rule) ~= "table")) then
			return false
		end
		if (rule.name == nil) then
			-- TODO : initialiser le nom si non fourni
			rule.name = "ToBeDefined"
		end
		log("Add rule '" .. rule.name .. "'", 1)
		initRule(rule)
		if checkRuleSettings(rule) then
			_rules[rule.name] = rule
		else
			log("Can not add rule '" .. rule.name .. "' : there is at least one error in settings", 1)
		end
	end

	-- Get rule (by name or return the input)
	function WatcherManager.getRule (ruleName)
		local rule
		if (ruleName == nil) then
			log("ERROR - ruleName is nil", 1)
		elseif (type(ruleName) == "string") then
			rule = _rules[ruleName]
			if (rule == nil) then
				log("WARNING - Rule '" .. ruleName .. "' is unknown", 1)
			end
		elseif (type(ruleName) == "table") then
			rule = ruleName
		else
			log("ERROR - Rule is not a table", 1)
		end
		return rule
	end

	-- Get rule status
	function WatcherManager.getRuleStatus (ruleName)
		local rule = WatcherManager.getRule(ruleName)
		if (rule ~= nil) then
			return rule._status or "0"
		else
			return nil
		end
	end

	-- Is rule active
	function WatcherManager.isRuleActive (ruleName)
		local _status = WatcherManager.getRuleStatus(ruleName)
		return (_status == "1")
	end

	-- Mise à jour du statut de la règle et exécution des actions liées
	function WatcherManager.setRuleStatus (ruleName, status)
		local rule = WatcherManager.getRule(ruleName)
		if (rule == nil) then
			return false
		end

		-- Check if rule is disabled
		if (rule._isDisabled) then
			log("Rule '" .. rule.name .. "' is disabled - Do nothing", 1)
			return false
		end

		-- Update rule active level
		oldRuleLevel = rule._level
		updateRuleLevel(rule)
		if (rule._level ~= oldRuleLevel) then
			log("Rule '" .. rule.name .. "' level has changed (oldLevel:" .. tostring(oldRuleLevel).. ", newLevel:" .. tostring(rule._level) .. ")", 2)
		end

		--updateRuleContext(rule)

		local hasRuleStatusChanged = false

		if ((rule._status == "0") and (status == "1")) then
			-- The rule has just been activated
			log("Rule '" .. rule.name .. "' is now active", 1)
			rule._status = "1"
			rule._lastStatusTime = os.time()
			rule._context.lastStatusUpdate = rule._lastStatusTime
			
			hasRuleStatusChanged = true
			doHook("onRuleIsActivated", rule)
			-- Execute actions linked to activation, if possible 
			if doHook("beforeDoingActionsOnRuleIsActivated", rule) then
				WatcherManager.doRuleActions(rule, "start")
				WatcherManager.doRuleActions(rule, "reminder")
			else
				log("Rule '" .. rule.name .. "' is now active, but a hook prevents from doing actions", 1)
			end
		elseif ((rule._status == "1") and (status == "0")) then
			-- The rule has just been deactivated
			log("Rule '" .. rule.name .. "' is now inactive", 1)
			rule._status = "0"
			rule._lastStatusTime = os.time()
			rule._context.lastStatusUpdate = rule._lastStatusTime

			hasRuleStatusChanged = true
			doHook("onRuleIsDeactivated", rule)
			-- Execute actions linked to deactivation, if possible 
			if doHook("beforeDoingActionsOnRuleIsDeactivated", rule) then
				if (rule._level ~= oldRuleLevel) then
					WatcherManager.doRuleActions(rule, "end", oldRuleLevel)
				end
				WatcherManager.doRuleActions(rule, "end")
			else
				log("Rule '" .. rule.name .. "' is now inactive, but a hook prevents from doing actions", 1)
			end

		elseif (rule._status == "1") then
			-- The rule is still active
			if (rule._level ~= oldRuleLevel) then
				log("Rule '" .. rule.name .. "' is still active but its level has changed", 1)
				WatcherManager.doRuleActions(rule, "end", oldRuleLevel)
				WatcherManager.doRuleActions(rule, "start", rule._level)
			else
				log("Rule '" .. rule.name .. "' is still active (do nothing)", 1)
			end
		elseif (rule._status == "0") then
			-- The rule is still inactive
			log("Rule '" .. rule.name .. "' is still inactive (do nothing)", 1)
		end

		if (hasRuleStatusChanged) then
			-- Notify that rule status has changed
			WatcherManager.onRuleStatusIsUpdated(rule.name, rule._status)
		end

	end

	-- Disable rule
	function WatcherManager.disableRule (rule)
		rule = WatcherManager.getRule(rule)
		if (rule == nil) then
			return false
		end
		if not rule._isDisabled then
			rule._isDisabled = true
			log("Rule '" .. rule.name .. "' is now disabled", 1)
		else
			log("Rule '" .. rule.name .. "' was already disabled", 1)
		end
		return true
	end

	-- Enable rule
	function WatcherManager.enableRule (rule)
		rule = WatcherManager.getRule(rule)
		if (rule == nil) then
			return false
		end
		if rule._isDisabled then
			rule._isDisabled = false
			log("Rule '" .. rule.name .. "' is now enabled", 1)
			-- Change rule status if needed
			WatcherManager.setRuleStatus(rule, computeRuleStatus(rule))
		else
			log("Rule '" .. rule.name .. "' was already enabled", 1)
		end
		return true
	end

	-- Is rule enabled
	function WatcherManager.isRuleEnabled (rule)
		rule = WatcherManager.getRule(rule)
		if (rule == nil) then
			return false
		end
		return (rule._isDisabled == false)
	end

	-- **************************************************
	-- Callbacks on event
	-- **************************************************

	-- Callback on device value update (mios call)
	function WatcherManager.onDeviceValueIsUpdated (lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
		local eventName = lul_service .. "-" .. lul_variable .. "-" .. tostring(lul_device)
		log("Event '" .. eventName .. "-" .. luup.devices[lul_device].description .. "' - New value: '" .. tostring(lul_value_new) .. "'", 1, "onDeviceValueIsUpdated")
		local linkedTriggers = _indexTriggersByEvent[eventName]
		if (linkedTriggers == nil) then
			return false
		end
		local linkedRules = {}

		-- Parcours des triggers liés au module dont la variable vient de changer
		for _, trigger in ipairs(linkedTriggers) do
			log("This event is linked to rule '" .. trigger._ruleName .. "' and trigger #" .. trigger._id, 2, "onDeviceValueIsUpdated")
			-- Maj du context du trigger
			trigger._context.deviceId   = lul_device
			trigger._context.value      = lul_value_new
			trigger._context.lastUpdate = os.time()
			-- Maj du context de la règle liée
			local rule =  WatcherManager.getRule(trigger._ruleName)
			if (rule ~= nil) then
				if not table.contains(linkedRules, rule) then
					table.insert(linkedRules, rule)
				end
				if (trigger._context.lastUpdate > rule._context.lastUpdate) then
					rule._context.deviceId   = trigger._context.deviceId
					rule._context.value      = trigger._context.value
					rule._context.lastUpdate = trigger._context.lastUpdate
				end
			end
		end

		-- Mise à jour éventuelle du statut des règles liées (et exécution des actions liées)
		for _, rule in ipairs(linkedRules) do
			WatcherManager.setRuleStatus(rule, computeRuleStatus(rule))
		end
		linkedRules = nil
	end

	-- Callback on timer triggered (mios call)
	function WatcherManager.onTimerIsTriggered (data)
		log("Event '" .. tostring(data) .. "'", 1, "onTimerIsTriggered")
		local params = string.split(data, ";")
		local ruleName  = params[1]
		local triggerId = tonumber(params[2])
		log("This event is linked to rule '" .. ruleName .. "' and trigger #" .. tostring(triggerId), 2, "onTimerIsTriggered")
			
		local rule =  WatcherManager.getRule(ruleName)
		if (rule ~= nil) then
			local trigger = rule.triggers[triggerId]
			trigger._status = "1"
			trigger._context.status     = "1"
			trigger._context.lastUpdate = os.time()
			WatcherManager.setRuleStatus(rule, computeRuleStatus(rule))
			if (rule._status == "1") then
				trigger._status = "0"
				WatcherManager.setRuleStatus(rule, computeRuleStatus(rule))
			end
		end
	end

	-- Callback on rule status update (inside call)
	function WatcherManager.onRuleStatusIsUpdated (watchedRuleName, newStatus)
		local eventName = "status-" .. watchedRuleName
		log("Event '" .. eventName .. "' - New status: '" .. tostring(newStatus) .. "'", 1, "onRuleStatusIsUpdated")
		local linkedTriggers = _indexTriggersByEvent[eventName]
		if (linkedTriggers == nil) then
			return false
		end
		local linkedRules = {}

		-- Parcours des triggers liés à la règle dont le statut vient de changer
		for _, trigger in ipairs(linkedTriggers) do
			log("This event is linked to rule '" .. trigger._ruleName .. "' and trigger #" .. trigger._id, 2, "onRuleStatusIsUpdated")
			-- Maj du context du trigger
			trigger._context.status     = lul_value_new
			trigger._context.lastUpdate = os.time()
			-- Maj du context de la règle liée
			local rule =  WatcherManager.getRule(trigger._ruleName)
			if (rule ~= nil) then
				if not table.contains(linkedRules, rule) then
					table.insert(linkedRules, rule)
				end
				if (trigger._context.lastUpdate > rule._context.lastUpdate) then
					rule._context.deviceId   = watchedRuleName
					rule._context.value      = trigger._context.status
					rule._context.lastUpdate = trigger._context.lastUpdate
				end
			end
		end

		-- Mise à jour éventuelle du statut des règles liées (et exécution des actions liées)
		for _, rule in ipairs(linkedRules) do
			WatcherManager.setRuleStatus(rule, computeRuleStatus(rule))
		end
		linkedRules = nil
	end

	-- **************************************************
	-- Main
	-- **************************************************

	-- Start
	function WatcherManager.start ()
		log("Start WatcherManager (v" .. WatcherManager._VERSION ..")", 1)
		_taskId = luup.task("Running startup", 1, "WatcherManager", -1)

		-- Parcours des règles
		for ruleName, rule in pairs(_rules) do

			-- Initialisation du statut de la règle
			log("Rule '" .. ruleName .. "' - Init rule status", 2)
			doHook("onRuleStatusInit", rule)
			if (rule._status == nil) then
				-- Calcul du statut de la règle car non initialisée par un hook
				rule._status = computeRuleStatus(rule)
				rule._lastStatusTime = os.time()
				rule._context.lastStatusUpdate = rule._lastStatusTime
			end
			if (rule._status == "1") then
				log("Rule '" .. ruleName .. "' is active on start", 2)
			else
				log("Rule '" .. ruleName .. "' is not active on start", 2)
			end

			-- Enregistrement des triggers
			if ((type(rule.triggers == "table")) and (table.getn(rule.triggers) > 0)) then
				log("Rule '" .. ruleName .. "' - Register triggers", 2)
				for i, trigger in ipairs(rule.triggers) do
					local msg = "Rule '" .. ruleName .. "' - Trigger #" .. tostring(i) .. " (type '" .. tostring(trigger.type) .. "')"
					--ConditionTypes.get(trigger._type).register(trigger, msg)
					ConditionTypes[trigger._type].register(trigger, msg)
				end
			end

			-- Exécution si possible des actions liées à l'activation
			if (rule._status == "1") then
				if doHook("beforeDoingActionsOnRuleIsActivated", rule) then
					WatcherManager.doRuleActions(ruleName, "reminder")
				else
					log("Rule '" .. ruleName .. "' is now active, but a hook prevents from doing actions", 1)
				end
				WatcherManager.onRuleStatusIsUpdated(rule.name, rule._status)
			end

		end

		--WatcherManager.dump()

		luup.task("OK", 4, "WatcherManager", _taskId)
	end

	-- Dump for debug
	function WatcherManager.dump ()
		log("Dump WatcherManager datas", 4)
		log("rules: " .. json.encode(_rules), 4)
		log("indexTriggersByEvent: " .. json.encode(_indexTriggersByEvent), 4)
	end

	-- Reset (just for unit tests)
	function WatcherManager.reset ()
		log("Reset WatcherManager", 1)
		-- Initialisations of rules
		-- for ruleName, rule in pairs(_rules) do
			-- initRule(rule)
		-- end
		_rules  = {}
		_indexTriggersByEvent = {}
	end

	-- Reset hooks (just for unit tests)
	function WatcherManager.resetHooks ()
		log("Reset hooks", 1)
		-- Reset of hooks
		_hooks = {}
	end

	-- Set current time (just for unit tests)
	function WatcherManager.setTime (currentTime)
		_currentTime = currentTime
	end

	-- Sets the verbosity level
	function WatcherManager.setVerbosity (lvl)
		_verbosity = lvl or 0
	end

	function WatcherManager.getVerbosity ()
		return _verbosity
	end

	-- Log something
	function WatcherManager.log (msg, lvl, methodName, isFromHook)
		log(msg, lvl, methodName, isFromHook)
	end

	function WatcherManager.setMinRecurentTimeDelay (timeDelay)
		_minRecurentTimeDelay = timeDelay
	end

-- Tricks for mios UI5
_G["WatcherManager"]                        = WatcherManager
_G["WatcherManager.onDeviceValueIsUpdated"] = WatcherManager.onDeviceValueIsUpdated
_G["WatcherManager.onTimerIsTriggered"]     = WatcherManager.onTimerIsTriggered
_G["WatcherManager.doRuleAction"]           = WatcherManager.doRuleAction
_G["WatcherManager.doRuleRecurrentAction"]  = WatcherManager.doRuleRecurrentAction

return WatcherManager
