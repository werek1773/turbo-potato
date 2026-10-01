import Foundation

enum AppConfig {
    /// Supabase project "Wspinaczka 2" (eu-central-1). The publishable key is
    /// meant to ship inside the app; Row Level Security protects the data.
    static let supabaseURL = URL(string: "https://afmppshzdkljlgzokdam.supabase.co")!
    static let supabasePublishableKey = "sb_publishable_zVDQ6h-oJVw1GPyQUkxqmg_fVdKQixb"

    static let sectorPhotosBucket = "sector-photos"
}
