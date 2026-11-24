/// OS-provided IPv4 interface and prefix for native LAN discovery.
class LanDiscoverySubnet {
  const LanDiscoverySubnet(this.name, this.address, this.prefix);
  final String name;
  final String address;
  final int prefix;

  static int? _ipv4(String ip) {
    final parts = ip.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) {
      return null;
    }
    return parts.fold<int>(0, (value, part) => (value << 8) | part!);
  }

  static String _format(int ip) =>
      [24, 16, 8, 0].map((shift) => (ip >> shift) & 255).join('.');
  static int _mask(int prefix) => (0xffffffff << (32 - prefix)) & 0xffffffff;

  static bool _private(int ip) =>
      ip >> 24 == 10 || ip >> 20 == 0xac1 || ip >> 16 == 0xc0a8;

  static bool _virtual(String name) => [
    'docker',
    'br-',
    'virbr',
    'veth',
    'podman',
    'tun',
    'tap',
    'wg',
    'tailscale',
    'waydroid',
    'dummy',
  ].any(name.toLowerCase().startsWith);

  static List<LanDiscoverySubnet> fromPlatform(List<dynamic> raw) {
    final result = <LanDiscoverySubnet>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final name = entry['name'];
      final address = entry['address'];
      final prefix = entry['prefix'];
      if (name is! String ||
          address is! String ||
          prefix is! int ||
          prefix < 1 ||
          prefix > 30 ||
          _virtual(name)) {
        continue;
      }
      final ip = _ipv4(address);
      if (ip == null || !_private(ip)) continue;
      // Do not expand beyond private address space even on a malformed prefix.
      final network = ip & _mask(prefix);
      final end = network | (0xffffffff ^ _mask(prefix));
      if (!_private(network) || !_private(end)) continue;
      result.add(LanDiscoverySubnet(name, address, prefix));
    }
    return result;
  }

  String get broadcast {
    final mask = _mask(prefix);
    return _format((_ipv4(address)! & mask) | (0xffffffff ^ mask));
  }

  /// At most 254 candidates, across at most two local networks. For a larger
  /// subnet use only the /24 containing the local address. Directed broadcast
  /// still covers the full network. No arbitrary ports or internet addresses.
  static List<String> fallbackTargets(List<LanDiscoverySubnet> subnets) {
    final own = subnets.map((s) => s.address).toSet();
    final candidates = <String>{};
    final networks = <(int, int)>{};
    for (final subnet in subnets) {
      final ip = _ipv4(subnet.address)!;
      final prefix = subnet.prefix < 24 ? 24 : subnet.prefix;
      final mask = _mask(prefix);
      final start = ip & mask;
      if (!networks.add((start, prefix))) continue;
      if (networks.length > 2) break;
      final actualMask = _mask(subnet.prefix);
      final actualStart = ip & actualMask;
      final actualEnd = actualStart | (0xffffffff ^ actualMask);
      final end = start | (0xffffffff ^ mask);
      for (var target = start; target <= end; target++) {
        if (target == actualStart || target == actualEnd || !_private(target)) {
          continue;
        }
        final address = _format(target);
        if (!own.contains(address)) candidates.add(address);
        if (candidates.length >= 254) return candidates.toList();
      }
    }
    return candidates.toList();
  }
}
