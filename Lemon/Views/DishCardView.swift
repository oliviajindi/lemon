import SwiftUI

/// One menu-card row: hand-drawn illustration, dish name, tags, and date.
/// Designed to read like a row from a printed restaurant menu.
struct DishCardView: View {
    let dish: Dish
    var isCompactStyle: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DishIllustrationView(dish: dish, size: isCompactStyle ? 40 : 56)

            VStack(alignment: .leading, spacing: isCompactStyle ? 2 : 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(dish.name)
                        .font(Theme.menuDishName(isCompactStyle ? 13 : 17))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if !isCompactStyle {
                    HStack(spacing: 6) {
                        // Chef credits — shown when one or more chefs have been set.
                        if !dish.chefs.isEmpty {
                            ForEach(Array(dish.chefs.enumerated()), id: \.element.id) { index, chef in
                                NavigationLink(destination: ChefDishesView(chef: chef)) {
                                    HStack(spacing: 0) {
                                        ChefAvatarView(chef: chef, size: 14)
                                            .padding(.trailing, 3)

                                        Text(chef.name)
                                            .font(Theme.hand(12))
                                            .foregroundStyle(Theme.inkFaded)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                if index < dish.chefs.count - 1 {
                                    Text(", ")
                                        .font(Theme.hand(12))
                                        .foregroundStyle(Theme.inkFaded)
                                }
                            }
                        }

                        // Separator between chef and tags
                        if !dish.chefs.isEmpty && !dish.tags.isEmpty {
                            Text("·")
                                .font(Theme.hand(12))
                                .foregroundStyle(Theme.inkFaded)
                        }

                        // Tags
                        if !dish.tags.isEmpty {
                            Text(dish.tags.prefix(4).map { "#\($0)" }.joined(separator: "  "))
                                .font(.system(size: 12, weight: .regular, design: .default).italic())
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, isCompactStyle ? 4 : 8)
        .contentShape(Rectangle())
    }
}

/// Renders the dish's illustration with a soft paper frame.
/// Falls back to a glyph while the image is missing/loading.
struct DishIllustrationView: View {
    let dish: Dish
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.7))

            if let data = dish.imageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: size * 0.4, weight: .light))
                    .foregroundStyle(Theme.inkFaded)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .cardStroke(cornerRadius: 10)
        .shadow(color: Theme.paperShadow.opacity(0.5), radius: 3, x: 1, y: 2)
    }
}
