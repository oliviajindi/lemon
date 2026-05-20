import SwiftUI

struct RootView: View {
    @State private var tab: AppTab = .menu

    enum AppTab: Hashable { case menu, today, calendar, profile }

    var body: some View {
        TabView(selection: $tab) {
            MenuView()
                .tabItem { Label("Menu", systemImage: "book.closed") }
                .tag(AppTab.menu)

            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)

            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppConfig.shared)
        .environmentObject(DishStore())
}
