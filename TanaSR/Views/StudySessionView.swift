import SwiftUI

struct StudySessionView: View {
    @StateObject private var viewModel: StudySessionViewModel
    @StateObject private var audioPlayer = AudioPlayerViewModel()

    init(store: CardStore) {
        _viewModel = StateObject(wrappedValue: StudySessionViewModel(store: store))
    }

    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView("Fehler", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let card = viewModel.currentCard {
                cardView(card)
            } else {
                ContentUnavailableView("Alles gelernt", systemImage: "checkmark.circle", description: Text("Keine fälligen Karten mehr."))
            }
        }
        .padding()
        .task {
            await viewModel.loadDueCards()
        }
    }

    @ViewBuilder
    private func cardView(_ card: Card) -> some View {
        VStack(spacing: 20) {
            Text("\(viewModel.remainingCount) verbleibend")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let imageUrlString = card.imageUrl, let url = URL(string: imageUrlString) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let audioUrlString = card.audioUrl, let url = URL(string: audioUrlString) {
                        Button {
                            audioPlayer.play()
                        } label: {
                            Label(
                                audioPlayer.isPlaying ? "Wird abgespielt…" : "Nochmals abspielen",
                                systemImage: audioPlayer.isPlaying ? "waveform" : "play.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .task(id: card.tanaNodeId) {
                            audioPlayer.load(url: url)
                            audioPlayer.play()
                        }
                    }

                    Text(card.question ?? "")
                        .font(.title2)
                        .fontWeight(.semibold)

                    if viewModel.isAnswerRevealed {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(card.answerBullets, id: \.self) { bullet in
                                Label {
                                    Text(markdownBold(bullet))
                                } icon: {
                                    Image(systemName: "circle.fill")
                                }
                                .labelStyle(BulletLabelStyle())
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            if viewModel.isAnswerRevealed {
                gradeButtons
            } else {
                Button {
                    viewModel.revealAnswer()
                } label: {
                    Text("Antwort zeigen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var gradeButtons: some View {
        HStack(spacing: 8) {
            ForEach(Grade.allCases, id: \.self) { grade in
                Button {
                    Task { await viewModel.grade(grade) }
                } label: {
                    Text(grade.label)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(color(for: grade))
            }
        }
    }

    private func color(for grade: Grade) -> Color {
        switch grade {
        case .again: return .red
        case .hard: return .orange
        case .good: return .green
        case .easy: return .blue
        }
    }

    private func markdownBold(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            configuration.icon.font(.system(size: 6)).padding(.top, 6)
            configuration.title
        }
    }
}

#Preview {
    StudySessionView(store: MockCardStore())
}
