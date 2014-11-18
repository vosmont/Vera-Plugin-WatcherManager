Vera-Plugin-WatcherManager
==========================

# Contexte

La gestion des évènements domotiques, par les scènes dans la Vera, est compliqué à maintenir et à mettre en oeuvre, dès qu'il y a des attentes à faire avec des reprises sous condition.

Il est paradoxalement plus simple de gérer ces évènements par des scripts LUA.

# Principe de fonctionnement

- Un plugin simplifié sous forme de module LUA.
- Le paramétrage (en LUA) à mettre dans le script lancé au démarrage de la Vera.
- Un système de hook permettant d'étendre les fonctionnalités.

Les écueils :
- Il n'y a pas d'interface graphique de paramétrage (trop compliqué à maintenir et à développer).
- Nécessite d'être un utilisateur avancé sur la Vera (certain paramétrage sont près proche du moteur luup)
- En cas de problème, il faut aller voir les logs pour analyse.

# Installation

Pour l'utiliser

1. il suffit de transférer les fichiers **L_Tools.lua** et **L_WatcherManager.lua** via l'interface de la Vera (UI->Develop Apps->Luup files).
2. et mettre dans le fichier de démarrage (à tester d'abord dans UI->Develop Apps->Test Luup code (Lua))

```lua
require("L_Tools")
require("L_WatcherManager")


-- ******************************************
-- Ici le paramétrage du module
-- (Voir la documentation)
-- ******************************************


-- Démarrage retardé pour sécuriser le démarrage du moteur LUA
function startCustomModules ()
	WatcherManager.start()
end
luup.call_delay("startCustomModules", 30, nil)
```

# Paramétrage

Il faut paramétrer des règles.

Une règle a :
- des triggers (déclencheurs)
- des conditions éventuelles à respecter
- des actions à effectuer pour un évènement particulier (début, relance, fin).
  Une action peut avoir des conditions particulières


## Ajout d'une règle

```lua
WatcherManager.addRule({
	name = "#RULE_NAME#",
	triggers = {
		#TRIGGER1#,
		#TRIGGER2#,
		...
	},
	conditions = {
		#CONDITION1#,
		#CONDITION2#,
		...
	},
	actions = {
		#ACTION1#,
		#ACTION2#,
		...
	}
})
```

## Types de Condition / Trigger

### Type "value"

```lua
{type="<TYPE>", devices={"<DEVICE_NAME1>", "<DEVICE_NAME2>", ...}, service="<SERVICE_ID>", variable="<VARIABLE_NAME>", value="<VALUE>"}
```
avec 

Paramètre | Description
----------|------------
TYPE | Le type de condition/trigger (voir ci-dessous)
DEVICE_NAME1, DEVICE_NAME2, ... | Le nom des modules liés à la condition/trigger
SERVICE_ID | L'id du service
VARIABLE_NAME | Le nom de la variable
VALUE | Le seuil

Type | Description
----------|------------
value | Valeur de la variable égale au seuil
value+ | Valeur de la variable inférieure au seuil
value+ | Valeur de la variable supérieure au seuil
value<> | Valeur de la variable différente du seuil


### Type "rule"

TODO

### Type "timer"

TODO


### Type "time"

TODO

## Actions

TODO



# Utilisation

Activation des logs

```lua
-- 0 - Pas de log
-- 1 -> 4 logs de plus en plus détaillés

DataCollector.setVerbosity(4)
```

# Exemples

## Ajout d'une action personnalisée

Ajout d'une action message vocal. Cette action peut être ensuite utilisée dans les règles.

```lua
WatcherManager.addAction(
	"vocal",
	function (action, context)
		local message = WatcherManager.getEnhancedMessage(action.message, context)
		KarotzHelper.say(message)
	end
)
```

## Contrôle du Home-Cinéma

Le Home-Cinéma est sur une prise avec mesure d'énergie.

Passé 100W, la télévision est considérée comme allumée, un mail est alors envoyé.

Tant que la télévision est allumée, un message vocal est joué toutes les 30 minutes (seulement entre 7 heures et 20 heures et si XBMC ne joue pas de la musique).

A l'extinction, un mail est envoyé.

```lua
WatcherManager.addRule({
	name = "HomeTheater",
	triggers = {
		{type="value+", device="Lounge_HomeTheater", service=SID.EnergyMetering, variable="Watts", value="100"}
	},
	actions = {
		{
			event = "start",
			type = "email",
			subject = "Événement domotique",
			message = "Le home-cinéma vient d'être allumé"
		}, {
			event = "reminder",
			conditions = {
				{type="time", between={"07:00:00", "20:00:00"}},
				{type="value<>", device="Lounge_XBMCState", service="urn:upnp-org:serviceId:XBMCState1", variable="PlayerStatus", value="Audio"}
			},
			timeDelay = 1800, -- 30 minutes
			type = "vocal",
			message = "La télévision est allumée depuis #durationfull#"
		}, {
			event = "end",
			types = {"email"},
			subject = "Événement domotique",
			message = "Le home-cinéma vient d'être éteint"
		}
	}
})
```

## Surveillance de la porte du garage

Lorsque la porte du garage est armée et s'ouvre, une alerte vocale et un email sont générés.

Tant que la porte est ouverte et armée, une alerte vocale est émise toutes les 10 minutes.

Quand la porte du garage est armée et se ferme, une alerte vocale et un email sont générés.
 
```lua
WatcherManager.addRule({
	name = "Garage_Door",
	triggers = {
		{type="value", device="Garage_SectionalDoor", service=SID.SecuritySensor, variable="Tripped", value="1"}
	},
	conditions = {
		{type="value", device="Garage_SectionalDoor", service=SID.SecuritySensor, variable="Armed", value="1"}
	},
	actions = {
		{
			event = "start",
			types = {"vocal", "email"},
			subject = "Événement domotique",
			message = "La porte du garage est en train de s'ouvrir"
		}, {
			event = "reminder",
			timeDelay = 600, -- 10 minutes
			type = "vocal",
			message = "Attention, la porte du garage est ouverte depuis #durationfull#"
		}, {
			event = "end",
			types = {"vocal", "email"},
			subject = "Événement domotique",
			message = "La porte du garage vient de se fermer"
		}
	}
})
```

## Surveillance de la température du congélateur

Si la température du congélateur dépasse -16°C, une alerte vocale et un email sont générés.

Tant que la température n'est pas revenue à la normale, une alerte vocale est émise toutes les 30 minutes.

Au retour à la normale, une alerte vocale et un email sont générés.

```lua
WatcherManager.addRule({
	name = "Freezer_Temperature",
	triggers = {
		{type="value+", device="Garage_FreezerTemperature", service=SID.TemperatureSensor, variable="CurrentTemperature", value="-16"}
	},
	actions = {
		{
			event = "start",
			types = {"email", "vocal"},
			subject = "Alerte domotique",
			message = "Attention, température du congélateur trop haute. La température est de #value# degrés"
		}, {
			event = "reminder",
			timeDelay = 1800, -- 30 minutes
			type = "vocal",
			message = "Attention, la température du congélateur est toujours trop haute depuis #durationfull#. Elle est actuellement de #value# degrés"
		}, {
			event = "end",
			types = {"email", "vocal"},
			subject = "Alerte domotique",
			message = "Retour à la normale de la température du congélateur"
		}
	}
})
```

## Alarme visuelle (règle liée à une autre)

Un ruban LED est allumé en fonction du niveau des règles actives.

```lua
WatcherManager.addRule({
	name = "VisualAlarms",
	triggers = {
		{type="rule", rule="Entry_Door", status="1", level=1},
		{type="rule", rule="Garage_Door", status="1", level=1},
		{type="rule", rule="Freezer_Temperature", status="1", level=3}
	},
	actions = {
		{ -- Alarme visuelle niveau bas
			event = "start",
			level = 1,
			callback = function ()
				luup.call_action(SID.RGBController, "SetColor", {newColor = "#FD6800"}, DeviceHelper.getIdByName("Lounge_CoffeTable_Controller"))
			end
		}, { -- Alarme visuelle niveau moyen
			event = "start",
			level = 2,
			callback = function ()
				luup.call_action(SID.RGBController, "SetColor", {newColor = "#FD00A2"}, DeviceHelper.getIdByName("Lounge_CoffeTable_Controller"))
			end
		}, { -- Alarme visuelle niveau critique
			event = "start",
			level = 3,
			callback = function ()
				luup.call_action(SID.RGBController, "SetColor", {newColor = "#FF0000"}, DeviceHelper.getIdByName("Lounge_CoffeTable_Controller"))
			end
		}, {
			event = "end",
			callback = function ()
				luup.call_action(SID.RGBController, "SetTarget", {newTargetValue = "0"}, DeviceHelper.getIdByName("Lounge_CoffeTable_Controller"))
			end
		}
	}
})
```

# Tests unitaires

Vous trouverez les tests unitaires dans le répertoire 'test'.

Ces tests utilisent **Vera-Plugin-Mock**
https://github.com/vosmont/Vera-Plugin-Mock
