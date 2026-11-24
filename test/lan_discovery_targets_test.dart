import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/network/lan_discovery_targets.dart';

void main() {
  test('uses actual prefixes and skips virtual, VPN and public interfaces', () {
    final subnets = LanDiscoverySubnet.fromPlatform([
      {'name': 'wlan0', 'address': '192.168.1.133', 'prefix': 24},
      {'name': 'wlan0', 'address': '192.168.1.149', 'prefix': 32},
      {'name': 'docker0', 'address': '172.17.0.1', 'prefix': 16},
      {'name': 'wg0', 'address': '10.66.66.3', 'prefix': 24},
      {'name': 'eth0', 'address': '8.8.8.8', 'prefix': 24},
    ]);
    expect(subnets.length, 1);
    expect(subnets.single.broadcast, '192.168.1.255');
    final targets = LanDiscoverySubnet.fallbackTargets(subnets);
    expect(targets, contains('192.168.1.102'));
    expect(targets.length, 253);
    expect(targets, isNot(contains('192.168.1.133')));
    expect(targets, isNot(contains('192.168.1.255')));
  });
  test('respects small subnet and caps wider networks', () {
    final narrow = LanDiscoverySubnet.fromPlatform([
      {'name': 'eth0', 'address': '10.0.0.10', 'prefix': 29},
    ]);
    expect(narrow.single.broadcast, '10.0.0.15');
    expect(LanDiscoverySubnet.fallbackTargets(narrow), [
      '10.0.0.9',
      '10.0.0.11',
      '10.0.0.12',
      '10.0.0.13',
      '10.0.0.14',
    ]);
    final wide = LanDiscoverySubnet.fromPlatform([
      {'name': 'eth0', 'address': '10.5.2.10', 'prefix': 16},
    ]);
    expect(wide.single.broadcast, '10.5.255.255');
    expect(LanDiscoverySubnet.fallbackTargets(wide).length, 254);
    expect(
      LanDiscoverySubnet.fallbackTargets(wide)
          .every((ip) => ip.startsWith('10.5.2.')),
      isTrue,
    );
  });
}
