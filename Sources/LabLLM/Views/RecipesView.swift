import SwiftUI

struct RecipesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkbenchPageHeader(eyebrow: "Build", title: "Recipes", subtitle: "Proven launch points for the model, data, and hyperparameters you want to explore.", icon: "wand.and.stars")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(Recipe.all) { recipe in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: recipe.icon).font(.title2).foregroundStyle(.tint)
                                Text(recipe.name).font(.headline)
                            }
                            Text(recipe.summary).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 10) {
                                tag("\(recipe.gpt.nLayers)L·\(recipe.gpt.nEmbd)d")
                                tag("ctx \(recipe.gpt.blockSize)")
                                tag("\(recipe.train.maxSteps) steps")
                            }
                            Button("Apply recipe") { state.apply(recipe) }
                                .buttonStyle(WorkbenchPrimaryButtonStyle())
                                .padding(.top, 4)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WorkbenchTheme.panel, in: RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous).strokeBorder(WorkbenchTheme.grid) }
                    }
                }
            }
            .padding(WorkbenchTheme.pagePadding)
        }
    }

    private func tag(_ s: String) -> some View {
        WorkbenchPill(text: s)
    }
}
