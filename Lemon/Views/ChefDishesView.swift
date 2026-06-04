import SwiftUI
import SwiftData

/// Displays a list of dishes associated with a specific chef.
/// Tapping a dish navigates to its detail view.
struct ChefDishesView: View {
    @EnvironmentObject private var store: DishStore
    let chef: Chef

    @Query(sort: \Dish.createdAt, order: .reverse) private var dishes: [Dish]
    @State private var isAddingDish = false

    // Compute dishes belonging to this chef.
    private var chefDishes: [Dish] {
        dishes.filter { $0.chefs.contains { $0.id == chef.id } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header with chef avatar and name
                HStack(spacing: 12) {
                    ChefAvatarView(chef: chef, size: 48)
                    Text(chef.name)
                        .font(Theme.title(22, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
                .padding(.bottom, 8)

                if chefDishes.isEmpty {
                    Text("No dishes for this chef yet.")
                        .font(Theme.hand(14))
                        .foregroundStyle(Theme.inkFaded)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(chefDishes) { dish in
                            NavigationLink(value: dish) {
                                DishCardView(dish: dish)
                            }
                            .buttonStyle(.plain)

                            if dish != chefDishes.last {
                                DottedDivider()
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .paperBackground()
        .navigationTitle(chef.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingDish = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add dish for \(chef.name)")
            }
        }
        .sheet(isPresented: $isAddingDish) {
            RecipeAssistantSheet(mode: .creator(initialChef: chef)) { addedDish in
                isAddingDish = false
            }
        }
    }
}

// Preview for SwiftUI canvas
#if DEBUG
struct ChefDishesView_Previews: PreviewProvider {
    static var previews: some View {
        ChefDishesView(chef: Chef(name: "Sample Chef"))
            .environmentObject(DishStore())
    }
}
#endif
