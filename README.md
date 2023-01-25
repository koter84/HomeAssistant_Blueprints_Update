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
wget -O blueprints_update.sh https://gist.githubusercontent.com/koter84/86790850aa63354bda56d041de31dc70/raw/blueprints_update.sh
chmod +x blueprints_update.sh
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

if you have a script which doesn’t have a source_url in the source file, add it to your local copy with “custom-” in front of the url `source_url: custom-https://example.com/source.yaml` the script will then use that url, and re-insert the source url after downloading.

to actually update the blueprints, run `./blueprints_update.sh --update`

for more verbose logging, use `--debug`
