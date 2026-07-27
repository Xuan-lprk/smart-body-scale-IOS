import Foundation
import Combine
import SwiftUI

@MainActor final class UserProfile: ObservableObject {
    @Published var sex: Sex = .female { didSet { savePrimaryProfile() } }
    @Published var height: Double = 165 { didSet { savePrimaryProfile() } }
    @Published var birthDate = Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now { didSet { savePrimaryProfile() } }
    @Published var members: [FamilyMember] = []
    var age: Int { Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 28 }
    private let primaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    init() {
        if let data = UserDefaults.standard.data(forKey: "afu.primary.profile"),
           let saved = try? JSONDecoder().decode(StoredPrimaryProfile.self, from: data) {
            sex = saved.sex
            height = saved.height
            birthDate = saved.birthDate
        }
        if let data = UserDefaults.standard.data(forKey: "afu.family.members"),
           let saved = try? JSONDecoder().decode([FamilyMember].self, from: data) {
            members = saved
        }
    }
    var primaryMember: FamilyMember { FamilyMember(id: primaryID, name: "本人", sex: sex, height: height, birthDate: birthDate, referenceWeight: 60) }
    func addMember(_ member: FamilyMember) { members.append(member); saveMembers() }
    func removeMembers(at offsets: IndexSet) { members.remove(atOffsets: offsets); saveMembers() }
    func matchedMember(for weight: Double, history: [BodyMeasurement]) -> FamilyMember {
        let candidates = [primaryMember] + members
        let ranked = candidates.map { member -> (FamilyMember, Double) in
            let records = history.filter { $0.memberID == member.id }.prefix(3)
            let reference = records.isEmpty ? member.referenceWeight : records.map(\.weight).reduce(0, +) / Double(records.count)
            return (member, abs(reference - weight))
        }
        return ranked.min(by: { $0.1 < $1.1 })?.0 ?? primaryMember
    }
    func shouldSuggestNewMember(for weight: Double, history: [BodyMeasurement]) -> Bool {
        let candidates = [primaryMember] + members
        let smallestDifference = candidates.map { member -> Double in
            let records = history.filter { $0.memberID == member.id }.prefix(3)
            let reference = records.isEmpty ? member.referenceWeight : records.map(\.weight).reduce(0, +) / Double(records.count)
            return abs(reference - weight)
        }.min() ?? 0
        return smallestDifference > 7
    }
    private func saveMembers() { if let data = try? JSONEncoder().encode(members) { UserDefaults.standard.set(data, forKey: "afu.family.members") } }
    private func savePrimaryProfile() {
        let profile = StoredPrimaryProfile(sex: sex, height: height, birthDate: birthDate)
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "afu.primary.profile")
        }
    }

    private struct StoredPrimaryProfile: Codable {
        let sex: Sex
        let height: Double
        let birthDate: Date
    }
}
