import server/ship/subsystem.{CrashNow, RebootNow, SetPowerTo}
import shared/protocol.{
  InjectFault, Navigation, Reactor, Reboot, SetPower, Shields,
}

pub fn route_command_test() {
  assert subsystem.route_command(InjectFault(Reactor)) == #(Reactor, CrashNow)
  assert subsystem.route_command(Reboot(Navigation)) == #(Navigation, RebootNow)
  assert subsystem.route_command(SetPower(Shields, 70))
    == #(Shields, SetPowerTo(70))
}
