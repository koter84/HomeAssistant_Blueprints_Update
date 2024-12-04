Home Assistant Blueprints Updater
=================================

This is a script to automatically check for updates for your HA Blueprints.

This is very much a work in progress.
More info on the [Home Assistant Community forum post](https://community.home-assistant.io/t/allow-blueprint-upgrades/366939)

At the moment it can create persistent notifications when an update is available, update a single blueprint or update all blueprints at once. It's also possible to auto-update the blueprints when a new version is available.
Unfortunately it is not possible (yet) to react to the notification to easily update just a single blueprint when an update is available.

Installation
------------

run the following commands on your home-assistant server command-line
```bash
mkdir -p /config/scripts/
cd /config/scripts/
wget -O blueprints_update.sh https://raw.githubusercontent.com/koter84/HomeAssistant_Blueprints_Update/main/blueprints_update.sh
chmod +x blueprints_update.sh
```

to enable notifications in home-assistant create and edit `blueprints_update.sh.conf` (in the same directory as the script)
```bash
_blueprints_update_server="http://localhost:8123"
_blueprints_update_token="---paste-long-lived-access-token-here---"
_blueprints_update_auto_update="false"
_blueprints_update_curl_options="--silent"
```

edit the `configuration.yaml` and add
```yaml
shell_command:
  blueprints_update: /config/scripts/blueprints_update.sh {{ arguments }}
```

create an automation to run the script, this will run the script every day at 03:00
```yaml
alias: _Blueprints Update - Check
description: ""
trigger:
  - platform: time_pattern
    hours: "3"
condition: []
action:
  - service: shell_command.blueprints_update
    data_template:
      arguments: ""
  - parallel:
    - alias: Pull into HA new blueprint code if any were loaded
      service: automation.reload
      data: {}
    - alias: Pull into HA new blueprint code if any were loaded
      service: script.reload
      data: {}
mode: single
```

optionally you can also create automations that call the script with certain arguments, which makes it possible to update blueprints from the front-end without the need for terminal/ssh access.
( for this to work the shell_command needs to have the `{{ arguments }}` part at the end, as it shows in the `configuration.yaml` example above, but this has recently been added, so check your `configuration.yaml` for that )
```yaml
alias: _Blueprints Update - Update All
description: ""
trigger: []
condition: []
action:
  - service: shell_command.blueprints_update
    data_template:
      arguments: "--update"
  - parallel:
    - alias: Pull into HA new blueprint code if any were loaded
      service: automation.reload
    - alias: Pull into HA new blueprint code if any were loaded
      service: script.reload
mode: single

alias: _Blueprints Update - Update Self
description: ""
trigger: []
condition: []
action:
  - service: shell_command.blueprints_update
    data_template:
      arguments: "--update --file 'self'"
mode: single

alias: _Blueprints Update - Update Specific Blueprint
description: ""
trigger: []
condition: []
action:
  - service: shell_command.blueprints_update
    data_template:
      arguments: "--update --file './automation/example/example.yaml'"
  - parallel:
    - alias: Pull into HA new blueprint code if any were loaded
      service: automation.reload
    - alias: Pull into HA new blueprint code if any were loaded
      service: script.reload
mode: single

alias: _Blueprints Update - Update Multiple Blueprints
description: ""
trigger: []
condition: []
action:
  - service: shell_command.blueprints_update
    data_template:
      arguments: "--update --file './automation/example/test-1.yaml'"
  - service: shell_command.blueprints_update
    data_template:
      arguments: "--update --file './script/example/test-2.yaml'"
  - parallel:
    - alias: Pull into HA new blueprint code if any were loaded
      service: automation.reload
    - alias: Pull into HA new blueprint code if any were loaded
      service: script.reload
mode: single
```

Usage
-----

if you have a script which doesn’t have a source_url in the source file, just add it to your local copy `source_url: https://example.com/source.yaml` the script will then use that url, and re-insert the source url after downloading.

if you fill in the server and [token](https://developers.home-assistant.io/docs/auth_api/#long-lived-access-token) settings in the `blueprints_update.sh.conf` file, the script generates a persistent notification when there is an update to one of the blueprints, and dismisses the notification when it is updated.

when you enable the auto_update setting you get a persistent notification that it was updated which won't get dismissed automatically.

to actually update the blueprints, run `./blueprints_update.sh --update` and add `--file` with the file-path to update just a single blueprint, use `--file self` to update just the script. The full commands are also in the notification, for easy copy-pasting.

for more verbose logging, use `--debug`
