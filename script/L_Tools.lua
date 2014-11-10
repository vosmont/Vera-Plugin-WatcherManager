-- NOTE : Limitation of mios UI5
-- The compressed modules must be declared with module(), and not using any of the alternative forms.
module("Tools", package.seeall)

-- **************************************************
-- Définition des devices et services
-- **************************************************

_G.DID_BinaryLight = "urn:schemas-upnp-org:device:BinaryLight:1"
_G.SID_SwitchPower = "urn:upnp-org:serviceId:SwitchPower1"

_G.DID_DimmableLight = "urn:schemas-upnp-org:device:DimmableLight:1"
_G.SID_Dimming = "urn:upnp-org:serviceId:Dimming1"

_G.SID_SecuritySensor = "urn:micasaverde-com:serviceId:SecuritySensor1"

_G.DID_MotionSensor = "urn:schemas-micasaverde-com:device:MotionSensor:1"
_G.SID_MotionSensor = "urn:micasaverde-com:serviceId:MotionSensor1"

_G.DID_LightSensor = "urn:schemas-micasaverde-com:device:LightSensor:1"
_G.SID_LightSensor = "urn:micasaverde-com:serviceId:LightSensor1"

_G.DID_TemperatureSensor = "urn:schemas-micasaverde-com:device:TemperatureSensor:1"
_G.SID_TemperatureSensor = "urn:upnp-org:serviceId:TemperatureSensor1"

_G.DID_HumiditySensor = "urn:schemas-micasaverde-com:device:HumiditySensor:1"
_G.SID_HumiditySensor = "urn:micasaverde-com:serviceId:HumiditySensor1"

_G.SID_Karotz = "urn:antor-fr:serviceId:Karotz1"

_G.SID_VariableContainer = "urn:upnp-org:serviceId:VContainer1"

_G.SID_HomeAutomationGateway = "urn:micasaverde-com:serviceId:HomeAutomationGateway1"

_G.DID_PowerMeter = "urn:schemas-micasaverde-com:device:PowerMeter:1"
_G.SID_EnergyMetering = "urn:micasaverde-com:serviceId:EnergyMetering1"

_G.DID_VirtualSwitch ="urn:schemas-upnp-org:device:VSwitch:1"
_G.SID_VirtualSwitch = "urn:upnp-org:serviceId:VSwitch1"

_G.SID_PanTiltZoom = "urn:micasaverde-com:serviceId:PanTiltZoom1"

_G.DID_SmartSwitchController = "urn:schemas-hugheaves-com:device:SmartSwitchController:1"
_G.SID_SmartSwitchController = "urn:hugheaves-com:serviceId:SmartSwitchController1"

_G.DID_BatteryMonitor = "urn:schemas-upnp-org:device:BatteryMonitor:1"
_G.SID_BatteryMonitor = "urn:upnp-org:serviceId:BatteryMonitor1"

_G.SID_MultiSwitch = "urn:dcineco-com:serviceId:MSwitch1"

_G.DID_CombinationSwitch = "urn:schemas-futzle-com:device:CombinationSwitch:1"

_G.SID_RGBController = "urn:upnp-org:serviceId:RGBController1"

-- **************************************************
-- Table functions
-- **************************************************

-- set of list
function _G.table.set (t)
	local u = { }
	for _, v in ipairs(t) do
		u[v] = true
	end
	return u
end

-- find element v of l satisfying f(v)
function _G.table.find (f, l)
	for _, v in ipairs(l) do
		if f(v) then
			return v
		end
	end
	return nil
end

-- check if table contains 
function _G.table.contains (t, i)
	for k, v in pairs(t) do
		if v == i then
			return true
		end
	end
	return false
end

-- return the first integer index holding the value
function _G.table.indexOf (t, val)
	for i, v in ipairs(t) do
		if v == val then
			return i
		end
	end
end

-- delete first item with value val in array
function _G.table.delete (t, val)
	local i = _G.table.indexOf(t, val)
	_G.table.remove(t, i)
end

-- **************************************************
-- String functions
-- **************************************************

--- Pads str to length len with char from left
function _G.string.lpad (str, len, char)
	if (char == nil) then
		char = ' '
	end
	return string.rep(char, len - #str) .. str
end

--- Pads str to length len with char from right
function _G.string.rpad (str, len, char)
	if (char == nil) then
		char = ' '
	end
	return str .. string.rep(char, len - #str)
end

function _G.string.split(str, pat)
	local t = {}  -- NOTE: use {n = 0} in Lua-5.0
	local fpat = "(.-)" .. pat
	local last_end = 1
	local s, e, cap = str:find(fpat, 1)
	while s do
		if s ~= 1 or cap ~= "" then
			table.insert(t,cap)
		end
		last_end = e+1
		s, e, cap = str:find(fpat, last_end)
	end
	if last_end <= #str then
		cap = str:sub(last_end)
		table.insert(t, cap)
	end
	return t
end


-- **************************************************
-- Tricks for mios UI5
-- **************************************************

-- Permet l'appel des méthodes dans l'espace de nom du module depuis les
-- fonctions luup.variable_watch, luup.call_delay et luup.call_timer
function _G.registerModuleNamespace (moduleName)
	local module = _G[moduleName]
	if module == nil then
		return false
	end
	for methodName, method in pairs(module) do
		local methodFlattenName = moduleName .. "." .. methodName
		if (type(method) == "function") and (string.sub(methodName, 1, 1) ~= "_") and (_G[methodFlattenName] == nil) then
			-- Méthode non privée et non déjà présente dans le contexte global
			_G[methodFlattenName] = method
		end
	end
	return true
end

-- **************************************************
-- Helpers
-- **************************************************

_G.DeviceHelper = {
	-- Get device id by its description
	getIdByName = function (deviceName)
		if (type(deviceName) == "number") then
			return deviceName
		else
			for deviceId, device in pairs(luup.devices) do
				if (device.description == deviceName) then
					return deviceId
				end
			end
		end
		luup.log("[DeviceHelper.getIdByName] " .. deviceName .. " doesn't exist", 1)
		return nil
	end,

	supportsService = function (deviceName, serviceId)
		local deviceId = DeviceHelper.getIdByName(deviceName)
		return luup.device_supports_service(serviceId, deviceId)
	end,

	getStatus = function (deviceName)
		local status
		local deviceId = DeviceHelper.getIdByName(deviceName)
		if (deviceId == nil) then
			return nil
		end
		if (luup.devices[deviceId].device_type == DID_VirtualSwitch) then
			status = luup.variable_get(SID_VirtualSwitch, "Status", deviceId)
		else
			status = luup.variable_get(SID_SwitchPower, "Status", deviceId)
		end
		return status
	end,

	watchStatus = function (deviceName, callback)
		local deviceId = DeviceHelper.getIdByName(deviceName)
		if (deviceId == nil) then
			return nil
		end
		if (luup.devices[deviceId].device_type == DID_VirtualSwitch) then
			luup.variable_watch(callback, SID_VirtualSwitch, "Status", deviceId)
		else
			luup.variable_watch(callback, SID_SwitchPower, "Status", deviceId)
		end
		return status
	end,

	setTarget = function (deviceName, target)
		local deviceId = DeviceHelper.getIdByName(deviceName)
		if (deviceId == nil) then
			return nil
		end
		if (luup.devices[deviceId].device_type == DID_VirtualSwitch) then
			luup.call_action(SID_VirtualSwitch, "SetTarget", {newTargetValue = target}, deviceId)
		else
			luup.call_action(SID_SwitchPower, "SetTarget", {newTargetValue = target}, deviceId)
		end
	end,

	getLoadLevelStatus = function (deviceName)
		local deviceId = DeviceHelper.getIdByName(deviceName)
		if (deviceId == nil) then
			return nil
		end
		return luup.variable_get(SID_Dimming, "LoadLevelStatus", deviceId)
	end,

	getLoadLevelTarget = function (deviceName)
		local deviceId = DeviceHelper.getIdByName(deviceName)
		if (deviceId == nil) then
			return nil
		end
		return luup.variable_get(SID_Dimming, "LoadLevelTarget", deviceId)
	end,

	setLoadLevelTarget = function (deviceName, loadLevelTarget)
		local deviceId = DeviceHelper.getIdByName(deviceName)
		if (deviceId == nil) then
			return nil
		end
		if (luup.devices[deviceId].category_num == 2) then
			luup.call_action(SID_Dimming, "SetLoadLevelTarget", {newLoadlevelTarget = loadLevelTarget}, deviceId)
		elseif (luup.devices[deviceId].category_num == 3) then
			if (tonumber(loadLevelTarget) < 50) then
				setDeviceTarget(deviceId, "0")
			else
				setDeviceTarget(deviceId, "1")
			end
		end
	end
}

_G.SceneHelper = {
	getIdByName = function (sceneName)
		for sceneId, scene in pairs(luup.scenes) do
			if (scene.description == sceneName) then
				return sceneId
			end
		end
		luup.log("[SceneHelper.getIdByName] Scene '" .. sceneName .. "' doesn't exist.", 1)
		return nil
	end,

	run = function (sceneId)
		if (type(sceneId) ~= "number") then
			sceneId = SceneHelper.getIdByName(sceneId)
		end
		if (sceneId ~= nil) then
			luup.call_action(SID_HomeAutomationGateway, "RunScene", {SceneNum = sceneId}, 0)
		end
	end
}

_G.VariableContainerHelper = {
	setVar = function (devID, varN, value)
		luup.variable_set(SID_VariableContainer, "Variable" .. varN, value or 0, devID)
	end,

	setVarName = function (devID, varNameN, value)
		luup.variable_set(SID_VariableContainer, "VariableName" .. varNameN, value or "undefined", devID)
	end,

	getVar = function (devID, varN)
		local value = luup.variable_get(SID_VariableContainer, "Variable" .. varN, devID)
		return value
	end
}
