import Foundation

private struct TailscaleStatus: Decodable {
    struct ThisDevice: Decodable { let DNSName: String }
    let thisDevice: ThisDevice
    enum CodingKeys: String, CodingKey { case thisDevice = "Self" }
}

enum TailscaleRouteService {
    static func dnsName(cliPath: String) -> String? {
        guard let result = try? CommandRunner.run(executable: cliPath, arguments: ["status", "--json"]), result.exitCode == 0,
              let status = try? JSONDecoder().decode(TailscaleStatus.self, from: Data(result.output.utf8)) else { return nil }
        return status.thisDevice.DNSName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    static func address(for profile: ServerProfile, dnsName: String) -> String {
        let port = profile.publicPort == 443 ? "" : ":\(profile.publicPort)"
        return "https://\(dnsName)\(port)\(profile.normalizedMountPath)"
    }
}
