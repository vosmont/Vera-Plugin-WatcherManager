#Vera-Plugin-WatcherManager

La gestion des évènements domotiques, par les scènes dans la Vera, est compliquée à maintenir et à mettre en œuvre, dès qu'il y a des attentes à faire avec des reprises sous condition.

Ce plugin permet de gérer plus simplement ces évènements par des scripts LUA.

## Principe de fonctionnement

- Un plugin sous forme de module LUA; pas d'interface graphique.
- Le paramétrage (en LUA) à mettre dans le script lancé au démarrage de la Vera.
- Un système de hook permettant d'étendre les fonctionnalités.

> Les écueils :
- Il n'y a pas d'interface graphique de paramétrage (trop compliqué à maintenir et à développer).
- Nécessite d'être un utilisateur avancé sur la Vera (certain paramétrages sont près proches du moteur luup)
- **En cas de problème, il faut aller voir les logs pour analyse**.

Le plugin fonctionne à partir de règles. Une règle a :

- des **triggers** (déclencheurs) qui permettent d'**observer** un ou plusieurs évènements pour pouvoir agir ensuite.
- des **conditions** *éventuelles* à respecter
- des **actions** à effectuer pour un stade particulier (début, relance, fin).
  Une action peut avoir des **conditions particulières** en plus des conditions de la règle.

### Détails techniques

Au démarrage du plugin, celui-ci s'enregistre auprès de la Vera en fonction des triggers définis dans les règles.
C'est la venue des évènements définis dans les triggers (valeur d'un module qui change, une certaine heure de la journée, ...) qui déclenche le calcul du statut de la règle liée.

Pour l'instant, le plugin n'effectue de traitement que lorsqu'un évènement survient : il n'y a pas d'attente active, ce qui permet d'épargner les ressources de la Vera.

### Cycle de vie d'une règle

Pour qu'une **règle** soit et reste **active**, il faut :

- qu'**au moins un** de ses **triggers** soit déclenché
- que **toutes les conditions** soient remplies

Si ces critères ne sont plus remplis, la règle devient inactive.

### Les actions

A chaque stade de la vie d'une règle, des actions peuvent être effectuées.

- à l'activation de la règle ("start")
- tant que la règle est active ("reminder").
  L'action peut être effectuée plusieurs fois.
- à la désactivation de la règle ("end")

Une action peut avoir des conditions particulières, qui si elles ne sont pas respectées, peuvent empêcher sa réalisation.

## Installation

Pour l'utiliser

1. Transférer les fichiers **L_Tools.lua** et **L_WatcherManager.lua** via l'interface de la Vera (UI->Develop Apps->Luup files).

2. Mettre dans le fichier de démarrage (à tester d'abord dans UI->Develop Apps->Test Luup code (Lua))

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

## Paramétrage

### Ajout d'une règle

> Pour simplifier le paramétrage, le nom des modules est utilisé à la place de leur identifiant.
> Ceci permet une plus grande souplesse lors d'un changement d'identifiant d'un module (même fonction mais technologie différente ou changement d'identifiant lors d'un changement de pile)

```lua
WatcherManager.addRule({
	name = "<RULE_NAME>",
	triggers = {
		<TRIGGER1>,
		<TRIGGER2>,
		...
	},
	conditions = {
		<CONDITION1>,
		<CONDITION2>,
		...
	},
	actions = {
		<ACTION1>,
		<ACTION2>,
		...
	}
})
```

### Conditions / Triggers

#### Type "value"

Le type "value" est en rapport avec la **valeur** d'une **variable** pour un **service** et pour un **module**.
Ce type peut être utilisé en tant que trigger ou condition.

Pour plus de détail sur la notion de variable de module, consultez le Wiki de la Vera :
http://wiki.micasaverde.com/index.php/Luup_Lua_extensions#function:_variable_get

Définition pour **un** module à observer/vérifier :
```lua
{type="<TYPE>", device="<DEVICE_NAME1>", service="<SERVICE_ID>", variable="<VARIABLE_NAME>", value="<VALUE>"}
```
Définition pour **plusieurs** modules à observer/vérifier :
```lua
{type="<TYPE>", devices={"<DEVICE_NAME1>", "<DEVICE_NAME2>", ...}, service="<SERVICE_ID>", variable="<VARIABLE_NAME>", value="<VALUE>"}
```
avec 

Paramètre | Description
----------|------------
*TYPE* | Le type de condition/trigger (voir table ci-dessous)
*DEVICE_NAME1*, *DEVICE_NAME2*, ... | Le nom des modules liés à la condition/trigger
*SERVICE_ID* | L'id du service
*VARIABLE_NAME* | Le nom de la variable
*VALUE* | Le seuil

TYPE | Description
----------|------------
*value* | Valeur de la variable égale au seuil
*value-* | Valeur de la variable inférieure au seuil
*value+* | Valeur de la variable supérieure au seuil
*value<>* | Valeur de la variable différente du seuil

> A noter, pour les types "value" et "value<>", il est possible d'utiliser une expression régulière pour la valeur seuil. Le paramètre est alors "*pattern*" à la place de "*value*".

```lua
{type="<TYPE>", device="<DEVICE_NAME1>", service="<SERVICE_ID>", variable="<VARIABLE_NAME>", pattern="<PATTERN>"}
```

#### Type "rule"

TODO

#### Type "timer"

Le type "timer" ne peut être utilisé qu'en tant que trigger.
TODO

http://wiki.micasaverde.com/index.php/Luup_Lua_extensions#function:_call_timer

```lua
{type="timer", timerType=<TYPE>, time="<TIME>", days="<DAYS>"}
```
avec

Paramètre | Description
----------|------------
*TYPE* | Le type de timer (1=Interval timer, 2=Day of week timer, 3=Day of month timer, 4=Absolute timer)
*TIME* | voir wiki Vera
*DAYS* | voir wiki Vera


#### Type "time"

Le type "time" ne peut être utilisé qu'en tant que condition.
TODO

### Actions


 
#### Type "action"


#### Type callback


#### Type personnalisé


## Utilisation

Activation des logs

```lua
-- 0 - Pas de log
-- 1 -> 4 logs de plus en plus détaillés

DataCollector.setVerbosity(4)
```

## Exemples

### Ajout d'une action personnalisée

Ajout d'une action message vocal.
Cette action peut être ensuite utilisée dans les règles.

```lua
WatcherManager.addAction(
	"vocal",
	function (action, context)
		local message = WatcherManager.getEnhancedMessage(action.message, context)
		KarotzHelper.say(message)
	end
)
```

### Contrôle du Home-Cinéma

```lua
WatcherManager.addRule({
	name = "HomeTheater",
	-- QUAND la prise du Home-Cinéma consomme plus de 100W
	triggers = {
		{type="value+", device="Lounge_HomeTheater", service=SID.EnergyMetering, variable="Watts", value="100"}
	},
	actions = {
		-- ALORS envoi d'un mail d'avertissement de l'allumage
		{
			event = "start",
			type = "email",
			subject = "Événement domotique",
			message = "Le home-cinéma vient d'être allumé"
		},
		-- RAPPEL toutes les 30 minutes, un message vocal est joué
		-- A CONDITION QUE il est entre 7 heures et 20 heures 
		--          ET QUE xbmc ne gère pas de la musique
		{
			event = "reminder",
			conditions = {
				{type="time", between={"07:00:00", "20:00:00"}},
				{type="value<>", device="Lounge_XBMCState", service="urn:upnp-org:serviceId:XBMCState1", variable="PlayerStatus", pattern="^Audio_.*$"}
			},
			timeDelay = 1800, -- 30 minutes
			type = "vocal",
			message = "La télévision est allumée depuis #durationfull#"
		},
		-- FINALEMENT envoi d'un mail d'avertissement de l'extinction
		{
			event = "end",
			types = {"email"},
			subject = "Événement domotique",
			message = "Le home-cinéma vient d'être éteint"
		}
	}
})
```

### Surveillance de la porte du garage
 
```lua
WatcherManager.addRule({
	name = "Garage_Door",
	-- QUAND la porte du garage est ouverte
	triggers = {
		{type="value", device="Garage_SectionalDoor", service=SID.SecuritySensor, variable="Tripped", value="1"}
	},
	actions = {
		-- ALORS envoi d'un mail et annonce vocale de l'ouverture
		-- A CONDITION QUE la porte du garage est armée
		{
			event = "start",
			conditions = {
				{type="value", device="Garage_SectionalDoor", service=SID.SecuritySensor, variable="Armed", value="1"}
			},
			types = {"vocal", "email"},
			subject = "Événement domotique",
			message = "La porte du garage est en train de s'ouvrir"
		},
		-- RAPPEL toutes les 10 minutes, un message vocal est joué
		{
			event = "reminder",
			timeDelay = 600, -- 10 minutes
			type = "vocal",
			message = "Attention, la porte du garage est ouverte depuis #durationfull#"
		},
		-- FINALEMENT envoi d'un mail d'avertissement de l'extinction
		-- A CONDITION QUE la porte du garage est armée
		{
			event = "end",
			conditions = {
				{type="value", device="Garage_SectionalDoor", service=SID.SecuritySensor, variable="Armed", value="1"}
			},
			types = {"vocal", "email"},
			subject = "Événement domotique",
			message = "La porte du garage vient de se fermer"
		}
	}
})
```

### Surveillance de la température du congélateur

```lua
WatcherManager.addRule({
	name = "Freezer_Temperature",
	-- QUAND la température du congélateur dépasse -16°C
	triggers = {
		{type="value+", device="Garage_FreezerTemperature", service=SID.TemperatureSensor, variable="CurrentTemperature", value="-16"}
	},
	actions = {
		-- ALORS alerte vocale et envoi mail
		{
			event = "start",
			types = {"email", "vocal"},
			subject = "Alerte domotique",
			message = "Attention, température du congélateur trop haute. La température est de #value# degrés"
		},
		-- RAPPEL toutes les 30 minutes, alerte vocale
		{
			event = "reminder",
			timeDelay = 1800, -- 30 minutes
			type = "vocal",
			message = "Attention, la température du congélateur est toujours trop haute depuis #durationfull#. Elle est actuellement de #value# degrés"
		},
		-- FINALEMENT alerte vocale et envoi mail
		{
			event = "end",
			types = {"email", "vocal"},
			subject = "Alerte domotique",
			message = "Retour à la normale de la température du congélateur"
		}
	}
})
```

### Alarme visuelle (règle liée à une autre)

Un ruban LED est allumé en fonction du niveau des règles actives.

```lua
WatcherManager.addRule({
	name = "VisualAlarms",
	-- QUAND règle "Entry_Door" active (NIVEAU 1)
	--    OU règle "Garage_Door" active (NIVEAU 1)
	--    OU règle "Freezer_Temperature" active (NIVEAU 3)
	triggers = {
		{type="rule", rule="Entry_Door", status="1", level=1},
		{type="rule", rule="Garage_Door", status="1", level=1},
		{type="rule", rule="Freezer_Temperature", status="1", level=3}
	},
	actions = {
		-- ALORS (NIVEAU 1) alarme visuelle niveau bas
		{
			event = "start",
			level = 1,
			type="action",
			device="Lounge_CoffeTable_Controller",
			service=SID.RGBController, action="SetColor", arguments={newColor="#FD6800"}
		},
		-- ALORS (NIVEAU 2) alarme visuelle niveau moyen
		{
			event = "start",
			level = 2,
			type="action",
			device="Lounge_CoffeTable_Controller",
			service=SID.RGBController, action="SetColor", arguments={newColor="#FD00A2"}
		},
		-- ALORS (NIVEAU 3) alarme visuelle niveau critique
		{
			event = "start",
			level = 3,
			type="action",
			device="Lounge_CoffeTable_Controller",
			service=SID.RGBController, action="SetColor", arguments={newColor="#FF0000"}
		},
		-- FINALEMENT extinction de l'alarme visuelle
		{
			event = "end",
			type="action",
			device="Lounge_CoffeTable_Controller",
			service=SID.RGBController, action="SetTarget", arguments={newTargetValue="0"}
		}
	}
})
```

## Tests unitaires

Vous trouverez les tests unitaires dans le répertoire 'test'.

Ces tests utilisent **Vera-Plugin-Mock**
https://github.com/vosmont/Vera-Plugin-Mock


