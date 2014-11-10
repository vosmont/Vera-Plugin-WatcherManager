package.path = "./script/?.lua;./lib/?.lua;../?.lua;" .. package.path

local _verbosity = 3

local LuaUnit = require("luaunit")
local VeraMock = require("core.vera")
require("L_Tools")
require("L_WatcherManager")

WatcherManager.setVerbosity(3)
VeraMock:setVerbosity(_verbosity)
LuaUnit:setVerbosity(_verbosity)
WatcherManager.setMinRecurentTimeDelay(1)

-- Log messages concerning these unit tests
local function log(msg)
	if (_verbosity > 0) then
		print(msg)
	end
end

-- Trace inside calls to be able to check them
local _calls = {}
local function traceCall(ruleName, event)
	if (_calls[ruleName] == nil) then
		_calls[ruleName] = {}
	end
	if (_calls[ruleName][event] == nil) then
		_calls[ruleName][event] = 0
	end
	_calls[ruleName][event] = _calls[ruleName][event] + 1
end

-- **************************************************
-- Mock initialisations
-- **************************************************

VeraMock:addDevice({description="Garage_SectionalDoor"})
VeraMock:addDevice({description="Garage_ServiceDoor"})
VeraMock:addDevice({description="Garage_Temperature"})
VeraMock:addDevice({description="Garage_Light"})
VeraMock:addDevice({description="Garage_WarningLamp"})

-- **************************************************
-- WatcherManager test datas
-- **************************************************

-- Actions
local _message
WatcherManager.addAction(
	"vocal",
	function (action, context)
		_message = WatcherManager.getEnhancedMessage(action.message, context)
		print("[WatcherManager.doRuleAction] Action vocal - message: \"" .. _message .. "\"")
	end
)
WatcherManager.addAction(
	"email",
	function (action, context)
		_message = WatcherManager.getEnhancedMessage(action.message, context)
		local subject = action.subject or "Alerte technique domotique"
		print("[WatcherManager.doRuleAction] Action email - subject: \"" .. subject .. "\" - message: \"" .. _message .. "\"")
	end
)

-- Rules
local ruleGarageDoors = {
	name = "Rule_Garage_Doors",
	triggers = {
		{type="value", device="Garage_SectionalDoor", service=SID_SecuritySensor, variable="Tripped", value="1"},
		{type="value", device="Garage_ServiceDoor", service=SID_SecuritySensor, variable="Tripped", value="1"}
	},
	conditions = {
		{type="value", device="Garage_SectionalDoor", service=SID_SecuritySensor, variable="Armed", value="1"}
	},
	actions = {
		{
			event = "start",
			timeDelay = 1,
			type = "vocal",
			message = "La porte du garage est en train de s'ouvrir"
		}, {
			event = "start",
			type = "action",
			devices={"Garage_Light"}, service=SID_SwitchPower, action="SetTarget", arguments={NewTarget="1"}
		}, {
			event = "start",
			timeDelay = 2,
			callback = function ()
				-- Custom function called on rule activation
				expect(getExpect() + 2)
				assertTrue(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is active (Start function)")
				assertEquals(luup.variable_get(SID_SwitchPower, "Status", DeviceHelper.getIdByName("Garage_Light")), "1", "The garage light is ON (Start function)")
				traceCall("Rule_Garage_Doors", "start")
			end
		}, {
			event = "reminder",
			timeDelay = 4,
			type = "vocal",
			message = "Attention, la porte du garage est ouverte depuis #durationfull#"
		}, {
			event = "reminder",
			timeDelay = 5,
			callback = function ()
				-- Custom function called after rule activation if still active
				expect(getExpect() + 1)
				assertTrue(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is active (Reminder function)")
				traceCall("Rule_Garage_Doors", "reminder")
			end
		}, {
			event = "end",
			type = "vocal",
			message = "La porte du garage vient de se fermer"
		}, {
			event = "end",
			type = "action",
			devices={"Garage_Light"}, service=SID_SwitchPower, action="SetTarget", arguments={NewTarget="0"}
		}, {
			event = "end",
			timeDelay = 1,
			callback = function ()
				-- Custom function called on rule deactivation
				expect(getExpect() + 2)
				assertFalse(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is inactive (End function)")
				assertEquals(luup.variable_get(SID_SwitchPower, "Status", DeviceHelper.getIdByName("Garage_Light")), "0", "The garage light is OFF (End function)")
				traceCall("Rule_Garage_Doors", "end")
			end
		}
	}
}
local ruleGarageTemperature = {
	name = "Rule_Garage_Temperature",
	triggers = {
		{type="value-", device="Garage_Temperature", service=SID_TemperatureSensor, variable="CurrentTemperature", value="10"},
		{type="value+", device="Garage_Temperature", service=SID_TemperatureSensor, variable="CurrentTemperature", value="20"}
	},
	actions = {
		{
			event = "start",
			conditions = {
				{type="value-", device="Garage_Temperature", service=SID_TemperatureSensor, variable="CurrentTemperature", value="10"}
			},
			type = "vocal",
			message = "Attention, température du garage trop basse. La température est de #value# degrés"
		}, {
			event = "start",
			conditions = {
				{type="value+", device="Garage_Temperature", service=SID_TemperatureSensor, variable="CurrentTemperature", value="20"}
			},
			type = "vocal",
			message = "Attention, température du garage trop haute. La température est de #value# degrés"
		}, {
			event = "end",
			types = {"vocal", "email"},
			message = "Retour à la normale de la température du garage",
			subject = "Alerte"
		}
	}
}


-- Check settings
local ruleToCheck = {
	name = "Rule_test_errors",
	triggers = {
		{something="type not defined"},
		{type="type not known"},
		-- Type 'value'
		{type="value"},
		{type="value", devices={}},
		{type="value+", devices={"unknown"}, service="something", variable="something", value="something"},
		{type="value", device="unknown", service="something", variable="something", value="something"},
		{type="value-", deviceId="999", service="something", variable="something", value="something"},
		-- Type 'rule'
		{type="rule"},
		{type="rule", rule="unknown", status="1"},
		-- Type 'timer'
		{type="timer", time="something"},
		{type="timer", timerType="1"}
	},
	actions = {
		{type="action"},
		{type="unknown"},
		{event="unknown"}
	}
}
--WatcherManager.addRule(ruleToCheck)

-- **************************************************
-- WatcherManager TestCases
-- **************************************************

TestWatcherManager = {}

	function TestWatcherManager:setUp()
		log("\n-------> Begin of TestCase")
		log("*** Init")
		VeraMock:reset()
		WatcherManager.reset()
		_calls = {}
	end

	function TestWatcherManager:tearDown()
		log("<------- End of TestCase")
	end

	function TestWatcherManager:test_start()
		WatcherManager.addRule(ruleGarageDoors)
		expect(2)
		assertNotNil(WatcherManager.getRuleStatus("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is defined")

		log("*** Start")
		WatcherManager.start()
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is not active")
	end

	function TestWatcherManager:test_tripped_but_not_armed()
		WatcherManager.addRule(ruleGarageDoors)
		expect(3)

		log("*** Start")
		WatcherManager.start()
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is not active")

		log("*** Garage door is opening but not armed")
		luup.variable_set(SID_SecuritySensor, "Armed", "0", DeviceHelper.getIdByName("Garage_SectionalDoor"))
		luup.variable_set(SID_SecuritySensor, "Tripped", "1", DeviceHelper.getIdByName("Garage_SectionalDoor"))

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 3 secondes")
				assertFalse(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is not active")
				log("*** Garage door is closing (before reminder actions)")
				luup.variable_set(SID_SecuritySensor, "Tripped", "0", DeviceHelper.getIdByName("Garage_SectionalDoor"))
			end),
			3, ""
		)

		VeraMock:run()
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is not active.")
	end

	function TestWatcherManager:test_tripped_and_armed_before_start()
		WatcherManager.addRule(ruleGarageDoors)
		expect(3)

		log("*** Garage door is opening and is armed")
		luup.variable_set(SID_SecuritySensor, "Armed", "1", DeviceHelper.getIdByName("Garage_SectionalDoor"))
		luup.variable_set(SID_SecuritySensor, "Tripped", "1", DeviceHelper.getIdByName("Garage_SectionalDoor"))

		log("*** Start")
		WatcherManager.start()
		assertTrue(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is active")

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 3 secondes")
				assertTrue(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is active")
				log("*** Garage door is closing (before reminder actions)")
				luup.variable_set(SID_SecuritySensor, "Tripped", "0", DeviceHelper.getIdByName("Garage_SectionalDoor"))
			end),
			3, ""
		)

		VeraMock:run()
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is not active")
	end

	function TestWatcherManager:test_tripped_and_armed_after_start()
		WatcherManager.addRule(ruleGarageDoors)
		expect(3)

		log("*** Start")
		WatcherManager.start()
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is not active")

		log("*** Garage door is opening and is armed")
		luup.variable_set(SID_SecuritySensor, "Armed", "1", DeviceHelper.getIdByName("Garage_SectionalDoor"))
		luup.variable_set(SID_SecuritySensor, "Tripped", "1", DeviceHelper.getIdByName("Garage_SectionalDoor"))

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 3 secondes")
				assertTrue(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is active")
				log("*** Garage door is closing (before reminder actions)")
				luup.variable_set(SID_SecuritySensor, "Tripped", "0", DeviceHelper.getIdByName("Garage_SectionalDoor"))
			end),
			3, ""
		)

		VeraMock:run()
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is not active")
	end

	function TestWatcherManager:test_tripped_and_armed_before_start_with_reminder()
		WatcherManager.addRule(ruleGarageDoors)
		expect(6)

		log("*** Garage door is opening and is armed")
		luup.variable_set(SID_SecuritySensor, "Armed", "1", DeviceHelper.getIdByName("Garage_SectionalDoor"))
		luup.variable_set(SID_SecuritySensor, "Tripped", "1", DeviceHelper.getIdByName("Garage_SectionalDoor"))

		log("*** Start")
		WatcherManager.start()
		assertTrue(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is active")

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 11 secondes")
				assertTrue(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is active")
				log("*** Garage door is closing (after reminder actions)")
				luup.variable_set(SID_SecuritySensor, "Tripped", "0", DeviceHelper.getIdByName("Garage_SectionalDoor"))
			end),
			11, ""
		)

		VeraMock:run()
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is not active.")
		assertNil(_calls["Rule_Garage_Doors"]["start"], "The start function for 'Rule_Garage_Doors' has not been called")
		assertEquals(_calls["Rule_Garage_Doors"]["reminder"], 2, "The reminder function for 'Rule_Garage_Doors' has been called twice")
		assertEquals(_calls["Rule_Garage_Doors"]["end"], 1, "The end function for 'Rule_Garage_Doors' has been called")
		
	end

	function TestWatcherManager:test_tripped_and_armed_after_start_with_reminder()
		WatcherManager.addRule(ruleGarageDoors)
		expect(7)

		log("*** Start")
		WatcherManager.start()
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is not active")

		log("*** Garage door is opening and is armed")
		luup.variable_set(SID_SecuritySensor, "Armed", "1", DeviceHelper.getIdByName("Garage_SectionalDoor"))
		luup.variable_set(SID_SecuritySensor, "Tripped", "1", DeviceHelper.getIdByName("Garage_SectionalDoor"))
		assertTrue(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is active")

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 11 secondes")
				assertTrue(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is active")
				log("*** Garage door is closing (after reminder actions)")
				luup.variable_set(SID_SecuritySensor, "Tripped", "0", DeviceHelper.getIdByName("Garage_SectionalDoor"))
			end),
			11, ""
		)

		VeraMock:run()
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Doors"), "Rule 'Rule_Garage_Doors' is not active")
		assertEquals(_calls["Rule_Garage_Doors"]["start"], 1, "The start function for 'Rule_Garage_Doors' has been called")
		assertEquals(_calls["Rule_Garage_Doors"]["reminder"], 2, "The reminder function for 'Rule_Garage_Doors' has been called twice")
		assertEquals(_calls["Rule_Garage_Doors"]["end"], 1, "The end function for 'Rule_Garage_Doors' has been called")
	end

	function TestWatcherManager:test_trigger_value()
		WatcherManager.addRule(ruleGarageTemperature)

		expect(8)

		log("*** Start")
		WatcherManager.start()
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is not active")

		log("*** Garage temperature is between min and max thresholds")
		luup.variable_set(SID_TemperatureSensor, "CurrentTemperature", "10.9", DeviceHelper.getIdByName("Garage_Temperature"))
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is not active")

		log("*** Garage temperature is on min threshold")
		luup.variable_set(SID_TemperatureSensor, "CurrentTemperature", "10", DeviceHelper.getIdByName("Garage_Temperature"))
		assertTrue(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is active")

		log("*** Garage temperature is below min threshold")
		luup.variable_set(SID_TemperatureSensor, "CurrentTemperature", "9.9", DeviceHelper.getIdByName("Garage_Temperature"))
		assertTrue(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is active")

		log("*** Garage temperature is between min and max thresholds")
		luup.variable_set(SID_TemperatureSensor, "CurrentTemperature", "19.9", DeviceHelper.getIdByName("Garage_Temperature"))
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is not active")

		log("*** Garage temperature is on max threshold")
		luup.variable_set(SID_TemperatureSensor, "CurrentTemperature", "20", DeviceHelper.getIdByName("Garage_Temperature"))
		assertTrue(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is active")

		log("*** Garage temperature is above max threshold")
		luup.variable_set(SID_TemperatureSensor, "CurrentTemperature", "20.1", DeviceHelper.getIdByName("Garage_Temperature"))
		assertTrue(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is active")

		log("*** Garage temperature is between min and max thresholds")
		luup.variable_set(SID_TemperatureSensor, "CurrentTemperature", "15", DeviceHelper.getIdByName("Garage_Temperature"))
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is not active")

		VeraMock:run()
	end

	function TestWatcherManager:test_trigger_rule()
		WatcherManager.addRule({
			name = "Rule1"
		})
		WatcherManager.addRule({
			name = "Rule2"
		})
		WatcherManager.addRule({
			name = "Rule_Linked",
			triggers = {
				{type="rule", rule="Rule1", status="1"},
				{type="rule", rule="Rule2", status="1"}
			},
			actions = {
				{
					event = "start",
					callback = function ()
						traceCall("Rule_Linked", "start")
					end
				}, {
					event = "reminder",
					timeDelay = 2,
					callback = function ()
						traceCall("Rule_Linked", "reminder")
					end
				}, {
					event = "end",
					callback = function ()
						traceCall("Rule_Linked", "end")
					end
				}
			}
		})

		expect(10)

		log("*** Start")
		WatcherManager.start()
		assertFalse(WatcherManager.isRuleActive("Rule_Linked"), "Rule is inactive")

		log("*** Rule 1 active and Rule 2 inactive")
		WatcherManager.setRuleStatus("Rule1", "1")
		assertTrue(WatcherManager.isRuleActive("Rule_Linked"), "Rule is active")
		assertEquals(_calls["Rule_Linked"], {
			start = 1
		}, "The number of event call is correct")

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 3 secondes")
				log("*** Rule 1 and Rule 2 active")
				WatcherManager.setRuleStatus("Rule2", "1")
				assertTrue(WatcherManager.isRuleActive("Rule_Linked"), "Rule is active")
				assertEquals(_calls["Rule_Linked"], {
					start = 1,
					reminder = 1
				}, "The number of event call is correct")
			end),
			3, ""
		)

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 5 secondes")
				log("*** Rule 1 inactive and Rule 2 active")
				WatcherManager.setRuleStatus("Rule1", "0")
				assertTrue(WatcherManager.isRuleActive("Rule_Linked"), "Rule is active")
				assertEquals(_calls["Rule_Linked"], {
					start = 1,
					reminder = 2
				}, "The number of event call is correct")
			end),
			5, ""
		)

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 7 secondes")
				log("*** Rule 1 and Rule 2 inactive")
				WatcherManager.setRuleStatus("Rule2", "0")
				assertFalse(WatcherManager.isRuleActive("Rule_Linked"), "Rule is not active")
				assertEquals(_calls["Rule_Linked"], {
					start = 1,
					reminder = 3,
					["end"] = 1
				}, "The number of event call is correct")
			end),
			7, ""
		)

		VeraMock:run()
		assertFalse(WatcherManager.isRuleActive("Rule_Linked"), "Rule is not active")
	end

	function TestWatcherManager:test_rule_with_levels()
		VeraMock:addDevice({description="Device1"})
		VeraMock:addDevice({description="Device2"})
		WatcherManager.addRule({
			name = "Rule_Level",
			triggers = {
				{type="value", device="Device1", service=SID_SwitchPower, variable="Status", value="1", level=1},
				{type="value", device="Device2", service=SID_SwitchPower, variable="Status", value="1", level="2"}
			},
			actions = {
				{
					event = "start",
					callback = function ()
						traceCall("Rule_Level", "start")
					end
				}, {
					event = "start",
					level = "1",
					callback = function ()
						traceCall("Rule_Level", "start_level_1")
					end
				}, {
					event = "start",
					level = 2,
					callback = function ()
						traceCall("Rule_Level", "start_level_2")
					end
				}, {
					event = "reminder",
					timeDelay = 2,
					callback = function ()
						traceCall("Rule_Level", "reminder")
					end
				}, {
					event = "reminder",
					timeDelay = 2,
					level = 1,
					callback = function ()
						traceCall("Rule_Level", "reminder_level_1")
					end
				}, {
					event = "reminder",
					timeDelay = 2,
					level = 2,
					callback = function ()
						traceCall("Rule_Level", "reminder_level_2")
					end
				}, {
					event = "end",
					callback = function ()
						traceCall("Rule_Level", "end")
					end
				}, {
					event = "end",
					level = "1",
					callback = function ()
						traceCall("Rule_Level", "end_level_1")
					end
				}, {
					event = "end",
					level = 2,
					callback = function ()
						traceCall("Rule_Level", "end_level_2")
					end
				}
			}
		})
		
		expect(4)

		log("*** Start")
		WatcherManager.start()

		log("*** Rule level 1 active and Rule level 2 inactive")
		luup.variable_set(SID_SwitchPower, "Status", "1", DeviceHelper.getIdByName("Device1"))
		luup.variable_set(SID_SwitchPower, "Status", "0", DeviceHelper.getIdByName("Device2"))
		assertEquals(_calls["Rule_Level"], {
			start = 1,
			start_level_1 = 1
		}, "The number of event call is correct")

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 5 secondes")
				log("*** Rule level 1 still active and Rule level 2 active")
				luup.variable_set(SID_SwitchPower, "Status", "1", DeviceHelper.getIdByName("Device2"))
				assertEquals(_calls["Rule_Level"], {
					start = 1,
					start_level_1 = 1,
					start_level_2 = 1,
					reminder = 2,
					reminder_level_1 = 2,
					end_level_1 = 1
				}, "The number of event call is correct")
			end),
			5, ""
		)

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 7 secondes")
				log("*** Rule level 1 still active and Rule level 2 inactive")
				luup.variable_set(SID_SwitchPower, "Status", "0", DeviceHelper.getIdByName("Device2"))
				assertEquals(_calls["Rule_Level"], {
					start = 1,
					start_level_1 = 2,
					start_level_2 = 1,
					reminder = 3,
					reminder_level_1 = 2,
					reminder_level_2 = 1,
					end_level_1 = 1,
					end_level_2 = 1
				}, "The number of event call is correct")
			end),
			7, ""
		)

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 9 secondes")
				log("*** Rule level 1 inactive and Rule level 2 still inactive")
				luup.variable_set(SID_SwitchPower, "Status", "0", DeviceHelper.getIdByName("Device1"))
				assertEquals(_calls["Rule_Level"], {
					start = 1,
					start_level_1 = 2,
					start_level_2 = 1,
					reminder = 4,
					reminder_level_1 = 3,
					reminder_level_2 = 1,
					["end"] = 1,
					end_level_1 = 2,
					end_level_2 = 1
				}, "The number of event call is correct")
			end),
			9, ""
		)

		VeraMock:run()
	end

	function TestWatcherManager:test_rule_disable()
		VeraMock:addDevice({description="Device1"})
		WatcherManager.addRule({
			name = "Rule_Disabled",
			triggers = {
				{type="value", device="Device1", service=SID_SwitchPower, variable="Status", value="1"},
			},
			actions = {
				{
					event = "start",
					callback = function ()
						traceCall("Rule_Disabled", "start")
					end
				}, {
					event = "reminder",
					timeDelay = 2,
					callback = function ()
						traceCall("Rule_Disabled", "reminder")
					end
				}, {
					event = "end",
					callback = function ()
						traceCall("Rule_Disabled", "end")
					end
				}
			}
		})

		expect(16)

		log("*** Start")
		WatcherManager.start()
		assertFalse(WatcherManager.isRuleActive("Rule_Disabled"), "Rule is not active")

		log("*** Rule is disabled and could be active")
		WatcherManager.disableRule("Rule_Disabled")
		WatcherManager.disableRule("Rule_Disabled")
		assertFalse(WatcherManager.isRuleEnabled("Rule_Disabled"), "Rule is not enabled")
		luup.variable_set(SID_SwitchPower, "Status", "1", DeviceHelper.getIdByName("Device1"))
		assertFalse(WatcherManager.isRuleActive("Rule_Disabled"), "Rule is not active")
		assertNil(_calls["Rule_Disabled"], "The number of event call is correct")

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 1 seconde")
				log("*** Rule is enabled and could be active")
				
				WatcherManager.enableRule("Rule_Disabled")
				WatcherManager.enableRule("Rule_Disabled")
				assertTrue(WatcherManager.isRuleEnabled("Rule_Disabled"), "Rule is enabled")
				assertTrue(WatcherManager.isRuleActive("Rule_Disabled"), "Rule is now active")
				assertEquals(_calls["Rule_Disabled"], {
					start = 1
				}, "The number of event call is correct")
			end),
			1, ""
		)

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 4 secondes")
				log("*** Rule is disabled and could be active")
				WatcherManager.disableRule("Rule_Disabled")
				WatcherManager.disableRule("Rule_Disabled")
				assertFalse(WatcherManager.isRuleEnabled("Rule_Disabled"), "Rule is not enabled")
				assertTrue(WatcherManager.isRuleActive("Rule_Disabled"), "Rule is still active")
				assertEquals(_calls["Rule_Disabled"], {
					start = 1,
					reminder = 1
				}, "The number of event call is correct")
			end),
			4, ""
		)

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 6 secondes")
				log("*** Rule is disabled and could be inactive")
				WatcherManager.disableRule("Rule_Disabled")
				assertFalse(WatcherManager.isRuleEnabled("Rule_Disabled"), "Rule is not enabled")
				luup.variable_set(SID_SwitchPower, "Status", "0", DeviceHelper.getIdByName("Device1"))
				assertTrue(WatcherManager.isRuleActive("Rule_Disabled"), "Rule is still active")
				assertEquals(_calls["Rule_Disabled"], {
					start = 1,
					reminder = 1
				}, "The number of event call is correct")
			end),
			6, ""
		)

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 8 secondes")
				log("*** Rule is enabled and could be inactive")
				WatcherManager.enableRule("Rule_Disabled")
				WatcherManager.enableRule("Rule_Disabled")
				assertTrue(WatcherManager.isRuleEnabled("Rule_Disabled"), "Rule is enabled")
				assertFalse(WatcherManager.isRuleActive("Rule_Disabled"), "Rule is now not active")
				assertEquals(_calls["Rule_Disabled"], {
					start = 1,
					reminder = 1,
					["end"] = 1
				}, "The number of event call is correct")
			end),
			8, ""
		)

		VeraMock:run()
	end

	function TestWatcherManager:test_rule_duration()
		WatcherManager.addRule(ruleGarageTemperature)

		expect(13)
		local rule = WatcherManager.getRule("Rule_Garage_Temperature")
		local expectedLastStatusUpdate = os.time()
		local expectedLastUpdate

		log("*** Start")
		WatcherManager.start()
		assertFalse(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is not active")

		log("*** Garage temperature is below min threshold")
		expectedLastUpdate = os.time()
		luup.variable_set(SID_TemperatureSensor, "CurrentTemperature", "9", DeviceHelper.getIdByName("Garage_Temperature"))
		assertTrue(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is active")
		assertEquals(rule._lastStatusTime, expectedLastStatusUpdate, "Rule 'Rule_Garage_Temperature' last rule status update time is correct")
		assertEquals(rule._context.lastUpdate, expectedLastUpdate, "Rule 'Rule_Garage_Temperature' last trigger update time is correct")
		assertEquals(rule._context.value, "9", "Rule 'Rule_Garage_Temperature' context value has changed")

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 1 seconde")
				log("*** Garage temperature is still below min threshold")
				expectedLastUpdate = os.time()
				luup.variable_set(SID_TemperatureSensor, "CurrentTemperature", 5, DeviceHelper.getIdByName("Garage_Temperature"))
				assertTrue(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is active")
			end),
			1, ""
		)

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 2 secondes")
				log("*** Garage temperature is still below min threshold")
				assertEquals(rule._lastStatusTime, expectedLastStatusUpdate, "Rule 'Rule_Garage_Temperature' last rule status update time is correct")
				assertEquals(rule._context.lastUpdate, expectedLastUpdate, "Rule 'Rule_Garage_Temperature' last trigger update time has changed")
				assertEquals(rule._context.value, '5', "Rule 'Rule_Garage_Temperature' context value has changed")
			end),
			2, ""
		)

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 3 secondes")
				log("*** Garage temperature is over min threshold")
				expectedLastStatusUpdate = os.time()
				expectedLastUpdate = os.time()
				luup.variable_set(SID_TemperatureSensor, "CurrentTemperature", "15", DeviceHelper.getIdByName("Garage_Temperature"))
				assertFalse(WatcherManager.isRuleActive("Rule_Garage_Temperature"), "Rule 'Rule_Garage_Temperature' is not active")
			end),
			3, ""
		)

		VeraMock:run()
		assertEquals(rule._lastStatusTime, expectedLastStatusUpdate, "Rule 'Rule_Garage_Temperature' last rule status update time is correct")
		assertEquals(rule._context.lastUpdate, expectedLastUpdate, "Rule 'Rule_Garage_Temperature' last trigger update time has changed")
		assertEquals(rule._context.value, '15', "Rule 'Rule_Garage_Temperature' context value has changed")
	end

	function TestWatcherManager:test_enhanced_message()
		local message
		local context = {}

		log("*** #value#")

		context.value = 15
		message = WatcherManager.getEnhancedMessage ("valeur #value#", context)
		assertEquals(message, "valeur 15", "Value Integer")

		context.value = "32"
		message = WatcherManager.getEnhancedMessage ("valeur #value#", context)
		assertEquals(message, "valeur 32", "Value String")

		log("*** #duration# and #durationfull#")

		context.lastStatusUpdate = os.time() - 1
		message = WatcherManager.getEnhancedMessage ("durée - #duration# - #durationfull#", context)
		assertEquals(message, "durée - P1S - une seconde", "Duration 1 second")

		context.lastStatusUpdate = os.time() - 2
		message = WatcherManager.getEnhancedMessage ("durée - #duration# - #durationfull#", context)
		assertEquals(message, "durée - P2S - 2 secondes", "Duration of 2 seconds")

		context.lastStatusUpdate = os.time() - 60
		message = WatcherManager.getEnhancedMessage ("durée - #duration# - #durationfull#", context)
		assertEquals(message, "durée - P1M0S - une minute", "Duration of 1 minute")

		context.lastStatusUpdate = os.time() - 132
		message = WatcherManager.getEnhancedMessage ("durée - #duration# - #durationfull#", context)
		assertEquals(message, "durée - P2M12S - 2 minutes et 12 secondes", "Duration of 2 minutes and 12 seconds")

		context.lastStatusUpdate = os.time() - 3600
		message = WatcherManager.getEnhancedMessage ("durée - #duration# - #durationfull#", context)
		assertEquals(message, "durée - P1H0M0S - une heure", "Duration of 1 hour")

		context.lastStatusUpdate = os.time() - 8415
		message = WatcherManager.getEnhancedMessage ("durée - #duration# - #durationfull#", context)
		assertEquals(message, "durée - P2H20M15S - 2 heures et 20 minutes", "Duration of 2 hours et 20 minutes with seconds")

		context.lastStatusUpdate = os.time() - 91225
		message = WatcherManager.getEnhancedMessage ("durée - #duration# - #durationfull#", context)
		assertEquals(message, "durée - P1DT1H20M25S - 1 jour et une heure", "Duration of 1 day and 1 hour with minutes and seconds")

		context.lastStatusUpdate = os.time() - 188432
		message = WatcherManager.getEnhancedMessage ("durée - #duration# - #durationfull#", context)
		assertEquals(message, "durée - P2DT4H20M32S - 2 jours et 4 heures", "Duration of 2 days and 4 hours with minutes and seconds")

	end

	function TestWatcherManager:test_timer()
		WatcherManager.addRule({
			name = "Rule_Timer",
			triggers = {
				{type="timer", timerType=2, time="05:00:00", days="1,2,3,4,5,6,7"}
			},
			actions = {
				{
					event = "start",
					callback = function ()
						traceCall("Rule_Timer", "start")
					end
				}, {
					event = "reminder",
					timeDelay = 1,
					callback = function ()
						traceCall("Rule_Timer", "reminder")
					end
				}, {
					event = "end",
					callback = function ()
						traceCall("Rule_Timer", "end")
					end
				}
			}
		})

		expect(3)

		log("*** Start")
		WatcherManager.start()
		assertFalse(WatcherManager.isRuleActive("Rule_Timer"), "Rule 'Rule_Timer' is not active")

		log("*** Trigger timer")
		VeraMock:triggerTimer(2, "05:00:00", "1,2,3,4,5,6,7")

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 2 secondes")
				assertFalse(WatcherManager.isRuleActive("Rule_Timer"), "Rule 'Rule_Timer' is not active")
				assertEquals(_calls["Rule_Timer"], {
					start = 1,
					["end"] = 1
				}, "The number of event call is correct")
			end),
			2, ""
		)

		VeraMock:run()
	end

	function TestWatcherManager:test_time()
		VeraMock:addDevice({description="Device1"})
		WatcherManager.addRule({
			name = "Rule_Time",
			triggers = {
				{type="value", device="Device1", service=SID_SwitchPower, variable="Status", value="1"}
			},
			actions = {
				{
					event = "start",
					callback = function ()
						traceCall("Rule_Time", "start")
					end
				}, {
					event = "reminder",
					timeDelay = 2,
					conditions = {
						{type="time-", time="05:00:00"}
					},
					callback = function ()
						traceCall("Rule_Time", "reminderUnder")
					end
				}, {
					event = "reminder",
					timeDelay = 2,
					conditions = {
						{type="time", between={"05:00:00", "20:00:00"}}
					},
					callback = function ()
						traceCall("Rule_Time", "reminderBetween")
					end
				}, {
					event = "reminder",
					timeDelay = 2,
					conditions = {
						{type="time+", time="20:00:00"}
					},
					callback = function ()
						traceCall("Rule_Time", "reminderAbove")
					end
				}, {
					event = "end",
					callback = function ()
						traceCall("Rule_Time", "end")
					end
				}
			}
		})

		expect(8)

		log("*** Start")
		WatcherManager.start()
		assertFalse(WatcherManager.isRuleActive("Rule_Time"), "Rule 'Rule_Time' is not active")

		log("*** Rule is active")
		luup.variable_set(SID_SwitchPower, "Status", "1", DeviceHelper.getIdByName("Device1"))
		assertTrue(WatcherManager.isRuleActive("Rule_Time"), "Rule 'Rule_Time' is active")
		assertEquals(_calls["Rule_Time"], {
			start = 1
		}, "The number of event call is correct")

		log("*** Time is under 05:00:00")
		WatcherManager.setTime("04:50:10")

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 3 secondes")
				assertEquals(_calls["Rule_Time"], {
					start = 1,
					reminderUnder = 1
				}, "The number of event call is correct")
				log("*** Time is between 05:00:00 and 20:00:00")
				WatcherManager.setTime("14:30:12")
			end),
			3, ""
		)

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 5 secondes")
				assertEquals(_calls["Rule_Time"], {
					start = 1,
					reminderUnder = 1,
					reminderBetween = 1
				}, "The number of event call is correct")
				log("*** Time is above 20:00:00")
				WatcherManager.setTime("22:10:24")
			end),
			5, ""
		)

		luup.call_delay(
			wrapAnonymousCallback(function ()
				log("*** After waiting 7 secondes")
				assertEquals(_calls["Rule_Time"], {
					start = 1,
					reminderUnder = 1,
					reminderBetween = 1,
					reminderAbove = 1
				}, "The number of event call is correct")
				log("*** Rule is not active")
				luup.variable_set(SID_SwitchPower, "Status", "0", DeviceHelper.getIdByName("Device1"))
				assertFalse(WatcherManager.isRuleActive("Rule_Time"), "Rule is now not active")
				assertEquals(_calls["Rule_Time"], {
					start = 1,
					reminderUnder = 1,
					reminderBetween = 1,
					reminderAbove = 1,
					["end"] = 1
				}, "The number of event call is correct")
			end),
			7, ""
		)

		VeraMock:run()
	end

-- run all tests
print("")
LuaUnit:run()
--LuaUnit:run("TestWatcherManager:test_trigger_rule")
