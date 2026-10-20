import EduBarCore
import SwiftUI

/// Météo de la ville choisie, affichée dans la journée quand le prochain cours est loin.
struct WeatherCard: View {
    let model: AppModel
    let forecast: Forecast
    let city: String

    /// « 03/10 ».
    private var fetchedDay: String {
        let c = model.calendar.dateComponents([.day, .month], from: forecast.fetched)
        return L10n.current == .fr
            ? String(format: "%02d/%02d", c.day ?? 0, c.month ?? 0)
            : String(format: "%02d/%02d", c.month ?? 0, c.day ?? 0)
    }

    var body: some View {
        let now = Weather.condition(forecast.code, isDay: forecast.isDay)
        let today = Weather.dayKey(model.now, calendar: model.calendar)
        let days = forecast.days.filter { $0.date >= today }.prefix(5)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: now.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 30))
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Weather.degrees(forecast.temperature))
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text(now.label).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Label(city, systemImage: "location.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(L10n.tr(
                        "Ressenti \(Weather.degrees(forecast.apparent)) · vent \(Int(forecast.wind.rounded())) km/h",
                        "Feels like \(Weather.degrees(forecast.apparent)) · wind \(Int(forecast.wind.rounded())) km/h"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !days.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(days, id: \.date) { day in
                        VStack(spacing: 3) {
                            Text(day.date == today ? L10n.tr("Auj.", "Today") : Weather.weekday(day.date) ?? "")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: Weather.condition(day.code, isDay: true).symbol)
                                .symbolRenderingMode(.multicolor)
                                .font(.callout)
                                .frame(height: 18)
                            Text(Weather.degrees(day.max)).font(.caption.monospacedDigit())
                            Text(Weather.degrees(day.min)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            // Sous 30 %, la pluie ne mérite pas la place.
                            Text((day.rain ?? 0) >= 30 ? L10n.tr("\(day.rain ?? 0) %", "\(day.rain ?? 0)%") : " ")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            // Sans rafraîchissement automatique, elle peut dater : le jour est dit s'il n'est pas aujourd'hui.
            Text(L10n.tr("Météo Open-Meteo", "Weather by Open-Meteo") + " · " + (model.calendar.isDate(forecast.fetched, inSameDayAs: model.now) ? "" : fetchedDay + " ")
                + Display.time(forecast.fetched, calendar: model.calendar))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
}

/// Volet « Météo » des réglages.
struct WeatherEditor: View {
    let model: AppModel

    var body: some View {
        let settings = model.weather
        VStack(alignment: .leading, spacing: 8) {
            caption(L10n.tr(
                "Quand le prochain cours est loin, la barre et la journée affichent la météo de ta ville à la place. Données Open-Meteo, sans compte : seuls le nom cherché et les coordonnées de la ville sont envoyés.",
                "When the next class is far away, the menu bar and the day view show your city's weather instead. Data from Open-Meteo, no account: only the searched name and the city's coordinates are sent."
            ))
            Toggle(L10n.tr("Afficher la météo", "Show weather"), isOn: binding(\.weather.enabled))
                .font(.callout.weight(.medium))
            if settings.enabled {
                Stepper(
                    L10n.tr("Pas de cours avant \(settings.hours) h ou plus", "No class for \(settings.hours) h or more"),
                    value: binding(\.weather.hours), in: 1...72
                )
                    .font(.caption)
                Toggle(L10n.tr("Toujours en haut de la journée", "Always at the top of the day"), isOn: binding(\.weather.alwaysInDay))
                    .font(.caption)
                    .help(L10n.tr(
                        "Même en cours. La barre, elle, n'affiche la météo que quand le prochain cours est loin.",
                        "Even during class. The menu bar only shows the weather when the next class is far away."
                    ))
                Toggle(L10n.tr("Actualiser automatiquement", "Refresh automatically"), isOn: binding(\.weather.autoRefresh))
                    .font(.caption)
                if settings.autoRefresh {
                    Picker(L10n.tr("Toutes les", "Every"), selection: binding(\.weather.refreshMinutes)) {
                        ForEach(WeatherSettings.refreshChoices, id: \.self) {
                            Text($0 < 60 ? "\($0) min" : "\($0 / 60) h").tag($0)
                        }
                    }
                    .font(.caption)
                } else {
                    caption(L10n.tr(
                        "Chargée une fois, puis seulement avec le bouton ↻ du menu.",
                        "Loaded once, then only with the ↻ button in the menu."
                    ))
                }
                placeRow(
                    L10n.tr("Affichée", "Shown"), "location.fill", settings.place, empty: L10n.tr("aucune ville", "no city")
                ) { model.weather.place = nil }
                placeRow(
                    "Campus", "graduationcap.fill", settings.campus, empty: L10n.tr("même ville", "same city")
                ) { model.weather.campus = nil }
                if let error = model.weatherStore.lastError {
                    Label(error, systemImage: "xmark.circle").font(.caption).foregroundStyle(.red).lineLimit(2)
                }
                Picker(L10n.tr("Ville à chercher", "City to search"), selection: binding(\.weatherForCampus)) {
                    Text(L10n.tr("Ville affichée", "Shown city")).tag(false)
                    Text("Campus").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                HStack {
                    TextField(
                        model.weatherForCampus
                            ? L10n.tr("Ville du campus", "Campus city")
                            : L10n.tr("Chez toi, au travail…", "Home, work…"),
                        text: binding(\.weatherDraft)
                    )
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .onSubmit(model.searchWeather)
                    Button(L10n.tr("Chercher", "Search"), action: model.searchWeather)
                        .font(.caption)
                        .disabled(model.weatherSearching || Weather.searchURL(model.weatherDraft) == nil)
                    if model.weatherSearching { ProgressView().controlSize(.small) }
                }
                ForEach(Array(model.weatherResults.enumerated()), id: \.offset) { _, place in
                    Button { model.pickWeatherPlace(place) } label: {
                        Label(place.label, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                }
                if let message = model.weatherMessage {
                    Label(message, systemImage: "xmark.circle").font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if settings.place == nil, model.weatherResults.isEmpty {
                    caption(L10n.tr("Choisis la ville affichée pour voir la météo.", "Choose the shown city to see the weather."))
                }
                caption(L10n.tr(
                    "Ville affichée : celle de la barre et de la journée (chez toi, au travail). Campus : celle de l'alerte pluie, si elle est différente.",
                    "Shown city: the one in the menu bar and the day view (home, work). Campus: the one for the rain alert, if different."
                ))
                rainEditor(settings)
            }
        }
        .font(.body.weight(.regular))
        .padding(.top, 6)
    }

    private func placeRow(
        _ title: String, _ icon: String, _ place: WeatherPlace?, empty: String, remove: @escaping () -> Void
    ) -> some View {
        HStack {
            Label("\(title)" + L10n.tr(" : ", ": ") + "\(place?.label ?? empty)", systemImage: icon)
                .font(.caption)
                .foregroundStyle(place == nil ? .secondary : .primary)
                .lineLimit(2)
            Spacer()
            if place != nil {
                Button(L10n.tr("Retirer", "Remove"), action: remove).font(.caption)
            }
        }
    }

    @ViewBuilder
    private func rainEditor(_ settings: WeatherSettings) -> some View {
        HStack {
            Toggle(L10n.tr("Alerte pluie avant la sortie", "Rain alert before you leave"), isOn: binding(\.weather.rainAlert))
                .font(.callout.weight(.medium))
            Spacer()
            Button(L10n.tr("Tester", "Test"), action: model.testRainAlert)
                .font(.caption)
        }
        if settings.rainAlert {
            Stepper(
                L10n.tr("\(settings.rainMinutes) min avant la fin des cours", "\(settings.rainMinutes) min before classes end"),
                value: binding(\.weather.rainMinutes), in: 5...120, step: 5
            )
                .font(.caption)
            Stepper(
                L10n.tr("À partir de \(settings.rainThreshold) % de risque", "From \(settings.rainThreshold)% chance"),
                value: binding(\.weather.rainThreshold), in: 10...90, step: 10
            )
                .font(.caption)
            caption(settings.rainPlace.map {
                L10n.tr(
                    "Une notification avant la fin du dernier cours de la journée, seulement s'il risque de pleuvoir à \($0.name) dans l'heure qui suit.",
                    "A notification before your last class of the day ends, only if rain is likely in \($0.name) within the next hour."
                )
            } ?? L10n.tr("Choisis une ville : sans elle, pas d'alerte.", "Choose a city: without one, there is no alert."))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func binding<T>(_ path: ReferenceWritableKeyPath<AppModel, T>) -> Binding<T> {
        Binding(get: { model[keyPath: path] }, set: { model[keyPath: path] = $0 })
    }
}
