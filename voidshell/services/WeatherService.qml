pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// VOID SHELL — weather source for the dashboard (PRD 22.3).
// Real data only: coordinates come from a one-shot IP geolocation that is
// cached, forecasts come from Open-Meteo, and the last successful payload
// is cached to disk. Offline runs keep the cache and report `stale`
// instead of inventing a temperature.
Singleton {
    id: root

    // idle -> loading -> ok | stale | unavailable
    property string status: "idle"
    property bool hasData: false
    property real temperature: 0
    property int weatherCode: -1
    property real windSpeed: 0
    property int humidity: -1
    property string locationLabel: ""
    property real updatedAt: 0
    property var daily: []

    property real latitude: 0
    property real longitude: 0
    property bool coordsResolved: false

    // Nothing is fetched until a view asks for it, and refreshes stop again
    // when every view stops asking (PRD 36). Views declare interest through
    // their own flag — the dashboard's overview/weather tabs and the lock
    // screen chip — so they never fight over one shared boolean.
    property bool viewsDashboard: false
    property bool viewsLock: false
    readonly property bool enabled: root.viewsDashboard || root.viewsLock

    readonly property bool fetching: status === "loading"
    readonly property string conditionText: weatherCode >= 0 ? root.describeCode(weatherCode) : ""
    readonly property bool stale: status === "stale"

    readonly property string updatedLabel: {
        if (updatedAt <= 0) {
            return "";
        }
        const mins = Math.floor((Date.now() - updatedAt) / 60000);
        if (mins < 1) {
            return "just now";
        }
        if (mins < 60) {
            return mins + "m ago";
        }
        const hours = Math.floor(mins / 60);
        if (hours < 24) {
            return hours + "h ago";
        }
        return Math.floor(hours / 24) + "d ago";
    }

    // ---- persisted files -----------------------------------------------------
    FileView {
        id: locationFile
        path: StorageService.ready ? StorageService.path("location.json") : ""
        printErrors: false
        onLoaded: root.parseLocation(locationFile.text())
        onLoadFailed: root.startGeolocation()
    }

    FileView {
        id: weatherFile
        path: StorageService.ready ? StorageService.path("weather.json") : ""
        printErrors: false
        onLoaded: root.parseCache(weatherFile.text())
    }

    // ---- network -------------------------------------------------------------
    Process {
        id: geoProc
        command: ["sh", "-c", "curl -fsS --max-time 8 https://ipwho.is/ || curl -fsS --max-time 8 https://freeipapi.com/api/json"]
        stdout: StdioCollector {
            id: geoOut
        }
        onExited: exitCode => {
            geoProc.running = false;
            if (exitCode === 0) {
                root.parseGeolocation(geoOut.text);
            } else if (!root.hasData) {
                root.status = "unavailable";
            }
        }
    }

    Process {
        id: weatherProc
        stdout: StdioCollector {
            id: weatherOut
        }
        onExited: exitCode => {
            weatherProc.running = false;
            if (exitCode === 0) {
                try {
                    root.parseForecast(weatherOut.text);
                } catch (e) {
                    console.warn("[voidshell] forecast parse failed:", e);
                    root.status = root.hasData ? "stale" : "unavailable";
                }
            } else {
                root.status = root.hasData ? "stale" : "unavailable";
            }
        }
    }

    Timer {
        interval: 15 * 60 * 1000
        repeat: true
        running: root.enabled
        onTriggered: root.refresh()
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.refresh();
        }
    }

    // ---- public API ----------------------------------------------------------
    function hasCoords() {
        return root.coordsResolved && isFinite(root.latitude) && isFinite(root.longitude);
    }

    function refresh() {
        if (!root.enabled) {
            return;
        }
        if (root.hasCoords()) {
            root.fetchForecast();
        } else {
            root.startGeolocation();
        }
    }

    function startGeolocation() {
        if (!root.enabled || geoProc.running) {
            return;
        }
        if (!root.hasData) {
            root.status = "loading";
        }
        geoProc.running = true;
    }

    function fetchForecast() {
        if (!root.enabled || !root.hasCoords() || weatherProc.running) {
            return;
        }
        root.status = "loading";
        const url = "https://api.open-meteo.com/v1/forecast?latitude=" + root.latitude + "&longitude=" + root.longitude + "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=7";
        weatherProc.command = ["curl", "-fsS", "--max-time", "12", url];
        weatherProc.running = true;
    }

    // ---- parsing -------------------------------------------------------------
    function parseLocation(content) {
        if (!content || content.trim() === "") {
            root.startGeolocation();
            return;
        }
        try {
            const data = JSON.parse(content);
            if (typeof data.latitude === "number" && typeof data.longitude === "number") {
                root.latitude = data.latitude;
                root.longitude = data.longitude;
                root.locationLabel = [data.city, data.country].filter(s => s).join(", ");
                root.coordsResolved = true;
                root.fetchForecast();
                return;
            }
        } catch (e) {
            console.warn("[voidshell] location.json malformed:", e);
        }
        root.startGeolocation();
    }

    function parseGeolocation(content) {
        try {
            const data = JSON.parse(content);
            if (data && data.success === false) {
                throw new Error("provider rejected request");
            }
            const lat = Number(data.latitude);
            const lon = Number(data.longitude);
            if (!isFinite(lat) || !isFinite(lon) || (lat === 0 && lon === 0)) {
                throw new Error("no coordinates");
            }
            root.latitude = lat;
            root.longitude = lon;
            root.locationLabel = [data.city, data.country || data.countryName].filter(s => s).join(", ");
            root.coordsResolved = true;
            root.saveLocation();
            root.fetchForecast();
        } catch (e) {
            console.warn("[voidshell] geolocation failed:", e);
            if (!root.hasData) {
                root.status = "unavailable";
            }
        }
    }

    function saveLocation() {
        if (!StorageService.ready) {
            return;
        }
        locationFile.setText(JSON.stringify({
            latitude: root.latitude,
            longitude: root.longitude,
            city: root.locationLabel.split(",")[0] || "",
            country: "",
            savedAt: Date.now()
        }));
    }

    function parseCache(content) {
        if (!content || content.trim() === "") {
            return;
        }
        try {
            const data = JSON.parse(content);
            if (data && typeof data.temperature === "number") {
                root.latitude = Number(data.latitude) || root.latitude;
                root.longitude = Number(data.longitude) || root.longitude;
                if (isFinite(root.latitude) && isFinite(root.longitude) && (root.latitude !== 0 || root.longitude !== 0)) {
                    root.coordsResolved = true;
                }
                root.applyForecast(data);
                root.status = "stale";
                if (root.hasCoords()) {
                    root.fetchForecast();
                }
            }
        } catch (e) {
            console.warn("[voidshell] weather cache malformed:", e);
        }
    }

    function parseForecast(content) {
        const data = JSON.parse(content);
        const current = data.current;
        if (!current || typeof current.temperature_2m !== "number") {
            throw new Error("unexpected forecast payload");
        }
        const daily = data.daily || {};
        const times = Array.isArray(daily.time) ? daily.time : [];
        const codes = Array.isArray(daily.weather_code) ? daily.weather_code : [];
        const maxes = Array.isArray(daily.temperature_2m_max) ? daily.temperature_2m_max : [];
        const mins = Array.isArray(daily.temperature_2m_min) ? daily.temperature_2m_min : [];
        const days = [];
        for (let i = 0; i < times.length; i++) {
            days.push({
                date: times[i],
                code: Number(codes[i]),
                max: Math.round(Number(maxes[i])),
                min: Math.round(Number(mins[i]))
            });
        }
        root.applyForecast({
            temperature: current.temperature_2m,
            weatherCode: Number(current.weather_code),
            windSpeed: Number(current.wind_speed_10m),
            humidity: Number(current.relative_humidity_2m),
            location: root.locationLabel,
            updatedAt: Date.now(),
            latitude: root.latitude,
            longitude: root.longitude,
            daily: days
        });
        root.status = "ok";
        root.saveCache();
    }

    function applyForecast(data) {
        root.temperature = Number(data.temperature);
        root.weatherCode = Number(data.weatherCode);
        root.windSpeed = Number(data.windSpeed);
        root.humidity = Number(data.humidity);
        if (data.location) {
            root.locationLabel = data.location;
        }
        root.updatedAt = Number(data.updatedAt) || 0;
        root.daily = Array.isArray(data.daily) ? data.daily : [];
        root.hasData = true;
    }

    function saveCache() {
        if (!StorageService.ready) {
            return;
        }
        weatherFile.setText(JSON.stringify({
            version: 1,
            temperature: root.temperature,
            weatherCode: root.weatherCode,
            windSpeed: root.windSpeed,
            humidity: root.humidity,
            location: root.locationLabel,
            updatedAt: root.updatedAt,
            latitude: root.latitude,
            longitude: root.longitude,
            daily: root.daily
        }));
    }

    // ---- WMO code mapping ----------------------------------------------------
    function describeCode(code) {
        const c = Number(code);
        if (c === 0) {
            return "Clear";
        }
        if (c === 1) {
            return "Mainly clear";
        }
        if (c === 2) {
            return "Partly cloudy";
        }
        if (c === 3) {
            return "Overcast";
        }
        if (c === 45 || c === 48) {
            return "Fog";
        }
        if (c >= 51 && c <= 57) {
            return "Drizzle";
        }
        if (c >= 61 && c <= 67) {
            return "Rain";
        }
        if (c >= 71 && c <= 77) {
            return "Snow";
        }
        if (c >= 80 && c <= 82) {
            return "Showers";
        }
        if (c >= 85 && c <= 86) {
            return "Snow showers";
        }
        if (c >= 95) {
            return "Thunderstorm";
        }
        return "Unknown";
    }

    // WMO code -> Nerd Font weather glyph (verified codepoints, never
    // pasted literals, so a font fallback cannot swap the symbol).
    function iconFor(code) {
        const c = Number(code);
        if (c === 0 || c === 1) {
            return String.fromCodePoint(0xF0599); // md-weather_sunny
        }
        if (c === 2 || c === 3) {
            return String.fromCodePoint(0xF0595); // md-weather_partly_cloudy
        }
        if (c === 45 || c === 48) {
            return String.fromCodePoint(0xF0591); // md-weather_fog
        }
        if (c >= 51 && c <= 67) {
            return String.fromCodePoint(0xF0597); // md-weather_rainy
        }
        if (c >= 71 && c <= 77) {
            return String.fromCodePoint(0xF0598); // md-weather_snowy
        }
        if (c >= 80 && c <= 82) {
            return String.fromCodePoint(0xF0596); // md-weather_pouring
        }
        if (c === 85 || c === 86) {
            return String.fromCodePoint(0xF067F); // md-weather_snowy_rainy
        }
        if (c >= 95) {
            return String.fromCodePoint(0xF0593); // md-weather_lightning
        }
        return String.fromCodePoint(0xF0590); // md-weather_cloudy
    }

    function dayLabel(dateString) {
        const parts = String(dateString).split("-");
        if (parts.length < 3) {
            return dateString;
        }
        const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        return Qt.formatDate(d, "ddd");
    }
}
