import SwiftUI

// MARK: - Arc d'objectif (demi-cercle, ADN direct de Reading Goals d'Apple Books)

struct ArcForme: Shape {
    var fraction: Double // 0...1

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var chemin = Path()
        let centre = CGPoint(x: rect.midX, y: rect.maxY)
        let rayon = min(rect.width / 2, rect.height) - 1
        guard rayon > 0, fraction > 0 else { return chemin }
        chemin.addArc(
            center: centre,
            radius: rayon,
            startAngle: .degrees(180),
            endAngle: .degrees(180 + 180 * min(max(fraction, 0), 1)),
            clockwise: false
        )
        return chemin
    }
}

struct ArcObjectifView: View {
    let minutes: Int
    let objectif: Int

    private var fraction: Double {
        guard objectif > 0 else { return 0 }
        return min(1, Double(minutes) / Double(objectif))
    }

    private var atteint: Bool { objectif > 0 && minutes >= objectif }

    /// Format horaire, comme le « 0:00 » d'Apple Books.
    private var tempsLisible: String {
        minutes >= 60
            ? String(format: "%d:%02d", minutes / 60, minutes % 60)
            : String(format: "%d:%02d", minutes, 0)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ArcForme(fraction: 1)
                .stroke(Color(uiColor: .secondarySystemFill), style: StrokeStyle(lineWidth: 11, lineCap: .round))
            ArcForme(fraction: fraction)
                .stroke(Couleurs.accent, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .animation(.spring(duration: 0.8), value: fraction)

            VStack(spacing: 2) {
                Text("Temps de lecture aujourd'hui")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                if atteint {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Couleurs.accent, in: Circle())
                        Text(tempsLisible)
                            .font(.system(size: 46, weight: .medium, design: .serif))
                            .monospacedDigit()
                    }
                } else {
                    Text(tempsLisible)
                        .font(.system(size: 52, weight: .medium, design: .serif))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Text("sur votre objectif de \(objectif) minutes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)
            .animation(.spring(duration: 0.5), value: atteint)
        }
        .aspectRatio(2.1, contentMode: .fit)
        .accessibilityLabel("Objectif du jour : \(minutes) minutes sur \(objectif)")
    }
}

// MARK: - Semaine de série (L M M J V S D, jours lus remplis, aujourd'hui cerclé)

struct SemaineSerieView: View {
    /// Jours (startOfDay) où au moins une session a eu lieu.
    let joursActifs: Set<Date>

    private let lettres = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<7, id: \.self) { index in
                let jour = jourDeLaSemaine(index)
                let actif = joursActifs.contains(jour)
                let estAujourdhui = Calendar.current.isDateInToday(jour)

                Text(lettres[index])
                    .font(.system(size: 10, weight: .heavy))
                    .frame(width: 24, height: 24)
                    .background(actif ? Couleurs.accent : Color(uiColor: .secondarySystemFill), in: Circle())
                    .foregroundStyle(actif ? .white : .secondary)
                    .overlay {
                        if estAujourdhui {
                            Circle().strokeBorder(Couleurs.accent, lineWidth: 1.5)
                        }
                    }
            }
        }
        .accessibilityLabel("Jours de lecture de la semaine")
    }

    /// Date (startOfDay) du index-ième jour de la semaine courante, lundi en premier.
    private func jourDeLaSemaine(_ index: Int) -> Date {
        var calendrier = Calendar.current
        calendrier.firstWeekday = 2 // lundi
        let aujourdhui = calendrier.startOfDay(for: .now)
        let debutSemaine = calendrier.dateInterval(of: .weekOfYear, for: aujourdhui)?.start ?? aujourdhui
        return calendrier.date(byAdding: .day, value: index, to: debutSemaine) ?? aujourdhui
    }
}
