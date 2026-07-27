import SwiftUI

struct EmptyStateView: View {
    let title: String
    let icon: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.teal)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}

struct MetricTile: View {
    let title: String; let valueString: String; let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.teal)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(valueString).font(.headline).fontWeight(.bold)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(.background, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.teal.opacity(0.12)))
    }
}
