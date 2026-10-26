import client/ui/log
import shared/protocol.{Critical, Info, LogEntry, Warning}

pub fn anim_key_test() {
  assert log.anim_key(7) == "log-7"
}

pub fn severity_helpers_test() {
  assert log.severity_tag(Info) == "INFO"
  assert log.severity_tag(Warning) == "WARN"
  assert log.severity_tag(Critical) == "CRIT"
  assert log.severity_class(Info) == "sev-info"
  assert log.severity_class(Warning) == "sev-warning"
  assert log.severity_class(Critical) == "sev-critical"
}

pub fn line_text_test() {
  assert log.line_text(LogEntry(0, Critical, "REACTOR", "SUBSYSTEM FAILURE"))
    == "[CRIT] REACTOR: SUBSYSTEM FAILURE"
}
