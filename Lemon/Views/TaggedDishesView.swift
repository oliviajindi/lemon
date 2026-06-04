import SwiftUI
import SwiftData

/// Shows every dish carrying a single tag. Opened by tapping a tag chip on a
/// dish detail page, so tags stay off the main menu but still support browsing.
struct TaggedDishesView: View {
    let tag: String

    @Query(sort: \Dish.createdAt, order: .reverse)
    private var dishes: [Dish]

    private var matchingDishes: [Dish] {
        dishes.filter { DishTags.matches(tag, in: $0.tags) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    TagPill(tag: tag)
                    Text(countLabel(matchingDishes.count))
                        .font(Theme.serif(15).italic())
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.top, 12)

                if matchingDishes.isEmpty {
                    Text("No dishes have this tag anymore.")
                        .font(Theme.serif(14).italic())
                        .foregroundStyle(Theme.inkFaded)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(matchingDishes) { dish in
                            NavigationLink(value: dish) {
                                DishCardView(dish: dish)
                            }
                            .buttonStyle(.plain)

                            if dish != matchingDishes.last {
                                DottedDivider().padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .cardStroke(cornerRadius: 16)
                }
            }
            .padding(20)
        }
        .paperBackground()
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func countLabel(_ n: Int) -> String {
        n == 1 ? "1 Dish" : "\(n) Dishes"
    }
}
