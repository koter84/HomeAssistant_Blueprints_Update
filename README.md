Home Assistant Blueprints Updater
=================================

This is a script to automatically check for updates for your HA Blueprints.
When an update is found it can also automatically be updated.

This is very much a work in progress, it works, but you need to run it manually from the command line.
More info on the [Home Assistant Community forum post](https://community.home-assistant.io/t/allow-blueprint-upgrades/366939)


Installation
------------

run the following commands on your home-assistant server command-line
```bash
mkdir -p /config/scripts/
cd /config/scripts/
wget -O blueprints_update.sh https://raw.githubusercontent.com/koter84/HomeAssistant_Blueprints_Update/main/blueprints_update.sh
chmod +x blueprints_update.sh
```

to enable notifications in home-assistant create and edit `blueprints_update.sh.conf`
```bash
_blueprints_update_server="http://localhost:8123"
_blueprints_update_token="---paste-long-lived-access-token---"
_blueprints_update_auto_update="false"
```

edit the `configuration.yaml` and add
```yaml
shell_command:
  blueprints_update: /config/scripts/blueprints_update.sh
```

create an automation to run the script
```yaml
alias: _Blueprints Update
description: ""
condition: []
action:
  - service: shell_command.blueprints_update
    data: {}
mode: single
```

Usage
-----

if you have a script which doesn’t have a source_url in the source file, just add it to your local copy `source_url: https://example.com/source.yaml` the script will then use that url, and re-insert the source url after downloading.

if you fill in the server and [token](https://developers.home-assistant.io/docs/auth_api/#long-lived-access-token) settings in the `blueprints_update.sh.conf` file, the script generates a persistent notification when there is an update to one of the blueprints, and dismisses the notification when it is updated.

when you enable the auto_update setting you get a persistent notification that it was updated which won't get dismissed automatically.

to actually update the blueprints, run `./blueprints_update.sh --update`

for more verbose logging, use `--debug`
