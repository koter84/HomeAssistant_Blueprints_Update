#!/bin/bash
#
# Dieses Skript aktualisiert sich selbst (falls nötig) und vor allem die Home Assistant Blueprints.
# Es erkennt, ob bei einem push force die Remote-Versionen verändert wurden, indem es den
# "Last-Modified"-Header auswertet – dieser wird in den Blueprint als Kommentar eingebettet.
#
# Optionale Sperrliste in blueprints_update.sh.conf (Pfade relativ zu /config/blueprints,
# so wie "find" sie ausgibt):
#   _blueprints_update_blacklist=("./automation/Blackshome/beispiel.yaml" "./script/foo/bar.yaml")
#

self_file="$0"
self_source_url="https://raw.githubusercontent.com/tefracky/homeassistant-blueprints/refs/heads/blueprints/blueprints_update.sh"

# defaults
_do_update="false"
_debug="false"

# --- Ausgabe-Funktionen ---
function _blueprint_update_debug {
    if [ "${_debug}" == "true" ]; then
        _blueprint_update_info "$@"
    fi
}

function _blueprint_update_info {
    if [ "${_debug}" == "true" ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") | $@"
    else
        echo "$@"
    fi
}

function _blueprint_update_newline {
    echo ""
}

# --- URL-Encoding korrigieren ---
function _fix_url {
    echo "$1" | sed \
    -e 's/%/%25/g' \
    -e 's/ /%20/g' \
    -e 's/!/%21/g' \
    -e 's/"/%22/g' \
    -e "s/'/%27/g" \
    -e 's/#/%23/g' \
    -e 's/(/%28/g' \
    -e 's/)/%29/g' \
    -e 's/+/%2b/g' \
    -e 's/,/%2c/g' \
    -e 's/;/%3b/g' \
    -e 's/?/%3f/g' \
    -e 's/@/%40/g' \
    -e 's/\$/%24/g' \
    -e 's/\&/%26/g' \
    -e 's/\*/%2a/g' \
    -e 's/\[/%5b/g' \
    -e 's/\\/%5c/g' \
    -e 's/\]/%5d/g' \
    -e 's/\^/%5e/g' \
    -e 's/`/%60/g' \
    -e 's/{/%7b/g' \
    -e 's/|/%7c/g' \
    -e 's/}/%7d/g' \
    -e 's/~/%7e/g'
}

# --- Datei herunterladen (inklusive HTTP-Header) ---
function _file_download {
    local file="$1"
    local source_url="$2"

    _blueprint_update_debug "-> download blueprint from ${source_url}"
    # Lade die Datei via curl herunter und speichere die HTTP-Header in einer Neben‑Datei
    http_code=$(curl -s -L -D "${file}.headers" -o "${file}" -w '%{http_code}' "$(_fix_url "${source_url}")")
    curl_result=$?
    if [ "${curl_result}" != "0" ]; then
        _blueprint_update_info "! Fehler beim Download, Skript wird beendet..."
        _blueprint_update_newline
        exit 1
    fi
    # Fehlerseiten (z. B. "404: Not Found") nie als Blueprint übernehmen
    if [ "${http_code}" != "200" ]; then
        _blueprint_update_info "-! HTTP ${http_code} beim Download von ${source_url}"
        return 1
    fi
    return 0
}

# --- Prüfen, ob eine Datei ein gültiger Blueprint ist (YAML mit blueprint.domain) ---
function _blueprint_valid {
    local file="$1"
    if ! command -v python3 >/dev/null 2>&1; then
        _blueprint_update_debug "-! python3 nicht gefunden, YAML-Prüfung übersprungen"
        return 0
    fi
    python3 - "${file}" <<'PY'
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)  # ohne PyYAML keine Prüfung möglich
class Loader(yaml.SafeLoader):
    pass
# HA-Tags wie !input oder !secret nur akzeptieren, nicht auswerten
Loader.add_multi_constructor("!", lambda loader, suffix, node: None)
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = yaml.load(f, Loader=Loader)
except Exception:
    sys.exit(1)
ok = isinstance(data, dict) and isinstance(data.get("blueprint"), dict) and "domain" in data["blueprint"]
sys.exit(0 if ok else 1)
PY
}

# --- Prüfen, ob eine Datei auf der Sperrliste steht ---
function _blueprint_blacklisted {
    local element
    for element in "${_blueprints_update_blacklist[@]}"; do
        if [ "${element}" == "$1" ]; then
            return 0
        fi
    done
    return 1
}

# --- Code-Block aus einem Community-Beitrag (Discourse-JSON) extrahieren ---
function _community_extract {
    local file="$1"
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "${file}" <<'PY'
import html, json, re, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        cooked = json.load(f)["post_stream"]["posts"][0]["cooked"]
except Exception:
    sys.exit(1)
match = re.search(r'<code class="lang-(?:yaml|auto)">(.*?)</code>', cooked, re.S)
if not match:
    sys.exit(1)
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write(html.unescape(match.group(1)))
PY
}

# --- Benachrichtigungen via Home Assistant (optional) ---
function _persistent_notification_create {
    local notification_id="$1"
    local notification_message="$2"

    if [ "${_blueprints_update_notify}" == "true" ]; then
        _blueprint_update_debug "notification create: [${notification_id}] [${notification_message}]"
        curl ${_blueprints_update_curl_options} -X POST -H "Authorization: Bearer ${_blueprints_update_token}" \
            -H "Content-Type: application/json" \
            -d "{ \"notification_id\": \"bu:${notification_id}\", \"title\": \"Blueprints Update\", \"message\": \"${notification_message}\" }" \
            "${_blueprints_update_server}/api/services/persistent_notification/create" >/dev/null
    else
        _blueprint_update_info "Benachrichtigungen nicht aktiviert"
    fi
}

function _persistent_notification_dismiss {
    local notification_id="$1"

    if [ "${_blueprints_update_notify}" == "true" ]; then
        _blueprint_update_debug "notification dismiss: [${notification_id}]"
        curl ${_blueprints_update_curl_options} -X POST -H "Authorization: Bearer ${_blueprints_update_token}" \
            -H "Content-Type: application/json" \
            -d "{ \"notification_id\": \"bu:${notification_id}\" }" \
            "${_blueprints_update_server}/api/services/persistent_notification/dismiss" >/dev/null
    else
        _blueprint_update_info "Benachrichtigungen nicht aktiviert"
    fi
}

# --- Temporäre Datei für Downloads erstellen und beim Verlassen löschen ---
_tempfile=$(mktemp -t blueprints_update.XXXXXX)
function clean_tempfile {
    if [ -f "${_tempfile}" ]; then
        rm "${_tempfile}"
    fi
    if [ -f "${_tempfile}.headers" ]; then
        rm "${_tempfile}.headers"
    fi
    if [ -f "${_tempfile}.new" ]; then
        rm "${_tempfile}.new"
    fi
}
trap clean_tempfile EXIT

# --- Kommandozeilen-Optionen parsen ---
options=$(getopt -a -l "help,debug,file:,update" -o "hdf:u" -- "$@")
eval set -- "$options"
while true; do
    case "$1" in
        -h|--help)
            echo "Usage: $0 [--debug] [--file <file>] [--update]"
            exit 0
            ;;
        -d|--debug)
            _debug="true"
            ;;
        -f|--file)
            shift
            _file="$1"
            ;;
        -u|--update)
            _do_update="true"
            ;;
        --)
            shift
            break
            ;;
    esac
    shift
    sleep 1
done

_blueprint_update_info "> ${self_file}"

# --- Konfiguration laden (falls vorhanden) ---
if [ -f "${self_file}.conf" ]; then
    _blueprint_update_debug "-! Lade Konfiguration aus [${self_file}.conf]"
    . "${self_file}.conf"

    _blueprints_update_notify="true"
    if [ -z "${_blueprints_update_server}" ]; then
        _blueprint_update_info "Config gefunden, aber _blueprints_update_server ist nicht gesetzt"
        _blueprints_update_notify="false"
    fi
    if [ -z "${_blueprints_update_token}" ]; then
        _blueprint_update_info "Config gefunden, aber _blueprints_update_token ist nicht gesetzt"
        _blueprints_update_notify="false"
    fi

    if [ -z "${_blueprints_update_curl_options}" ]; then
        _blueprints_update_curl_options="--silent"
    fi

    if [[ "${_blueprints_update_auto_update,,}" == "true" ]]; then
        _do_update="true"
    fi
fi

###############################################################################
# Selbst-Update (das Skript selbst aktualisieren)
###############################################################################
if [ -z "${_file}" ] || [ "${_file}" == "self" ]; then
    file="self"
    if ! _file_download "${_tempfile}" "${self_source_url}" || ! bash -n "${_tempfile}"; then
        _blueprint_update_info "-! Selbst-Update übersprungen (Download fehlgeschlagen oder ungültige Syntax)"
        cp "${self_file}" "${_tempfile}"
    fi
    self_diff=$(diff "${self_file}" "${_tempfile}")
    if [ -z "${self_diff}" ]; then
        _blueprint_update_info "-> self up-2-date"
        _persistent_notification_dismiss "$(basename "${file}")"
    else
        if [ "${_do_update}" == "true" ]; then
            cp "${_tempfile}" "${self_file}"
            chmod +x "${self_file}"
            _blueprint_update_info "-! self updated!"
            _persistent_notification_create "$(basename "${file}")" "Updated $(basename "${file}")"
            exit 0
        else
            _blueprint_update_info "-! self changed!"
            _persistent_notification_create "$(basename "${file}")" "Update available for $(basename "${file}")\n\nupdate command:\n$0 --update --file '${file}'"
        fi
    fi
    _blueprint_update_newline
fi

###############################################################################
# Blueprints-Aktualisierung – Erkennen eines Force Push ohne externe Datei
###############################################################################
# Bestimme das Blueprints-Verzeichnis
# (HA-Container: /config/blueprints; Skript liegt üblicherweise in /config/scripts/)
if [ -d /config/blueprints/ ]; then
    cd /config/blueprints/ || exit 1
elif [ -d "$(dirname "$0")/../blueprints/" ]; then
    cd "$(dirname "$0")/../blueprints/" || exit 1
elif [ -d /blueprints/ ]; then
    cd /blueprints/ || exit 1
elif [ -d /usr/share/hassio/homeassistant/blueprints/ ]; then
    cd /usr/share/hassio/homeassistant/blueprints/ || exit 1
else
    _blueprint_update_info "-! Blueprints-Verzeichnis nicht gefunden"
    exit 1
fi

# Für jedes Blueprint (YAML-Datei) durchlaufen wir das Update-Verfahren
find . -type f -name "*.yaml" -print0 | while read -d $'\0' file; do
    # Wenn eine einzelne Datei ausgewählt wurde, überspringe andere
    if [ -n "${_file}" ] && [ "${_file}" != "${file}" ]; then
        continue
    fi

    _blueprint_update_info "> ${file}"

    # Sperrliste: diese Blueprints nie automatisch aktualisieren
    if _blueprint_blacklisted "${file}"; then
        _blueprint_update_info "-> steht auf der Sperrliste, überspringe"
        _blueprint_update_newline
        continue
    fi

    # Lese den source_url Eintrag aus der Datei
    blueprint_source_url=$(grep '^ *source_url: ' "${file}" | sed -e "s/^ *source_url: *//" -e 's/"//g' -e "s/'//g")
    _blueprint_update_debug "-> source_url: ${blueprint_source_url}"
    if [ -z "${blueprint_source_url}" ]; then
        _blueprint_update_info "-! kein source_url in Datei gefunden"
        _blueprint_update_newline
        continue
    fi

    # --- URL-Anpassungen (GitHub/Gist/Community) ---
    if echo "${blueprint_source_url}" | grep -q 'https://github.com/'; then
        _blueprint_update_debug "-! Umwandlung GitHub URL in Raw URL"
        blueprint_source_url=$(echo "${blueprint_source_url}" | sed -e 's/https:\/\/github.com\//https:\/\/raw.githubusercontent.com\//' -e 's/\/blob\//\//')
        _blueprint_update_debug "-> korrigierte source_url: ${blueprint_source_url}"
    fi

    if echo "${blueprint_source_url}" | grep -q 'https://gist.github.com/'; then
        _blueprint_update_debug "-! Umwandlung GitHub Gist URL in Raw URL"
        if echo "${blueprint_source_url}" | grep -q '#'; then
            _blueprint_update_debug "-> entferne #filename vom Ende der URL"
            blueprint_source_url=$(echo "${blueprint_source_url}" | sed 's/#.*//')
        fi
        blueprint_source_url=$(echo "${blueprint_source_url}" | sed -e 's/https:\/\/gist.github.com\//https:\/\/gist.githubusercontent.com\//' -e "s/\$/\/raw\/$(basename "${file}")/")
        _blueprint_update_debug "-> korrigierte source_url: ${blueprint_source_url}"
    fi

    if echo "${blueprint_source_url}" | grep -q 'https://community.home-assistant.io/'; then
        _blueprint_update_debug "-! Verwendung des Home Assistant Community Blueprint Exchange"
        if ! echo "${blueprint_source_url}" | grep -q '\.json$'; then
            blueprint_source_url="${blueprint_source_url}.json"
            _blueprint_update_debug "-> korrigierte source_url: ${blueprint_source_url}"
        fi
        if ! _file_download "${_tempfile}" "${blueprint_source_url}"; then
            _blueprint_update_newline
            continue
        fi

        # Code-Block (lang-yaml oder lang-auto) aus dem JSON extrahieren
        if ! _community_extract "${_tempfile}"; then
            _blueprint_update_info "-! Kein lang-yaml/auto Codeblock gefunden, überspringe..."
            _blueprint_update_newline
            continue
        fi
    else
        # Für alle anderen Fälle: Überprüfe, ob der Dateiname übereinstimmt (optional)
        if [ "$(basename "${file}")" != "$(basename "${blueprint_source_url}")" ]; then
            _blueprint_update_info "-! Dateiname stimmt nicht überein"
            _blueprint_update_debug "-! [$(basename "${file}")] != [$(basename "${blueprint_source_url}")]"
            _blueprint_update_newline
            # Hier könnte man auch einen forced update erzwingen
        fi
        if ! _file_download "${_tempfile}" "${blueprint_source_url}"; then
            _blueprint_update_newline
            continue
        fi
    fi

    # Nur gültige Blueprints übernehmen (schützt vor Fehlerseiten und kaputtem YAML)
    if ! _blueprint_valid "${_tempfile}"; then
        _blueprint_update_info "-! Download ist kein gültiger Blueprint, überspringe..."
        _persistent_notification_create "$(basename "${file}")" "Update für $(basename "${file}") übersprungen: Download ist kein gültiger Blueprint"
        _blueprint_update_newline
        continue
    fi

    # Fehlt im Download die source_url (häufig bei Community-Beiträgen), die bisherige
    # wieder einsetzen – sonst würde der Blueprint danach nie mehr aktualisiert
    new_source_url=$(grep -m1 '^ *source_url: ' "${_tempfile}" | sed -e "s/^ *source_url: *//" -e 's/"//g' -e "s/'//g")
    orig_source_url=$(grep -m1 '^ *source_url: ' "${file}" | sed -e "s/^ *source_url: *//" -e 's/"//g' -e "s/'//g")
    if [ -z "${new_source_url}" ]; then
        _blueprint_update_debug "-! source_url im Download fehlt, setze ${orig_source_url} wieder ein"
        awk -v url="${orig_source_url}" '
            !done && /^blueprint:[[:space:]]*$/ { print; print "  source_url: \"" url "\""; done = 1; next }
            { print }
        ' "${_tempfile}" > "${_tempfile}.new" && mv "${_tempfile}.new" "${_tempfile}"
    elif [ "${new_source_url}" != "${orig_source_url}" ]; then
        # Remote-Datei verweist auf eine andere Quelle (z. B. Repo umgezogen) – nur informieren
        _blueprint_update_info "-! source_url geändert: ${orig_source_url} -> ${new_source_url}"
    fi

    ############################################################################
    # Entferne in beiden, der heruntergeladenen Datei und der lokalen
    # Datei ggf. den "remote_last_modified:" Kommentar, um nur den reinen YAML-Inhalt zu vergleichen.
    ############################################################################
    # Extrahiere den remote Last-Modified Header (sofern vorhanden)
    remote_lm=$(grep -i '^Last-Modified:' "${_tempfile}.headers" | cut -d ':' -f2- | sed 's/^[[:space:]]*//; s/\r//')
    _blueprint_update_debug "-> remote Last-Modified Header: ${remote_lm}"

    # Entferne Zeilen mit dem zusätzlichen Meta-Header aus der heruntergeladenen Datei
    cleaned_remote=$(sed '/^# remote_last_modified:/d' "${_tempfile}")
    # Führe dasselbe für die lokale Datei durch
    cleaned_local=$(sed '/^# remote_last_modified:/d' "${file}")

    # Lese den in der lokalen Datei vorhandenen Meta-Header (falls vorhanden)
    local_lm=$(grep '^# remote_last_modified:' "${file}" | sed 's/^# remote_last_modified: *//')

    # Vergleiche den reinen YAML-Inhalt beider Dateien
    blueprint_diff=$(diff <(echo "$cleaned_local") <(echo "$cleaned_remote"))
    if [ -z "$blueprint_diff" ] && [ "${remote_lm}" == "${local_lm}" ]; then
        _blueprint_update_info "-> blueprint up-2-date"
        _persistent_notification_dismiss "${file}"
    else
        if [ "${_do_update}" == "true" ]; then
            # Beim Update wird (falls der remote Last-Modified Header vorhanden ist)
            # ein Kommentar mit diesem Header an den Anfang der heruntergeladenen Datei gesetzt.
            if [ -n "${remote_lm}" ]; then
                echo -e "# remote_last_modified: ${remote_lm}\n" > "${_tempfile}.new"
                cat "${_tempfile}" >> "${_tempfile}.new"
                cp "${_tempfile}.new" "${file}"
            else
                cp "${_tempfile}" "${file}"
            fi
            _blueprint_update_info "-! blueprint updated!"
            _persistent_notification_create "$(basename "${file}")" "Updated $(basename "${file}")"
            need_reload="1"
        else
            _blueprint_update_info "-! blueprint changed!"
            _persistent_notification_create "$(basename "${file}")" "Update available for $(basename "${file}")\n\nupdate command:\n$0 --update --file '${file}'"
            if [ "${_debug}" == "true" ]; then
                _blueprint_update_debug "-! diff:"
                diff "${file}" "${_tempfile}"
            fi
        fi
    fi

    _blueprint_update_newline
done

if [ "${need_reload}" == "1" ]; then
    _blueprint_update_info "! Es gab Updates, Home Assistant sollte neu geladen werden!"
fi
