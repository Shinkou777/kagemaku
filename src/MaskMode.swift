import Foundation

/// 一条遮挡条拿来做什么
enum MaskMode: Int, Codable, CaseIterable, Identifiable {
    /// 练听力：整块挡住，听不出来再偷看
    case cover = 0
    /// 学外语：只盖中文那一行，外文照常看
    case learn = 1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .cover: return "听力"
        case .learn: return "学外语"
        }
    }

    var note: String {
        switch self {
        case .cover: return "整块挡住，听不出来再偷看"
        case .learn: return "只盖中文那一行，外文照常看"
        }
    }
}
