import std/json
import licensebox
assert deriveBinding("demo", "linux-machine-id", "12345678123456789abc1234567890ab") == "m1:linux-machine-id:783b8906a4af61095e68f3f0b4468a953be69ddd7afcf35850b501a7361f309e"
let c = newClient(%*{"product":"demo", "keys":{"k":"A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg"}, "directory":"build/test-state"})
let alias = c
try:
  discard c.status()
  assert false
except LicenseboxError as e: assert e.code == "not_signed_in"
c.logout(); c.close(); alias.close()
try:
  discard alias.status()
  assert false
except LicenseboxError as e: assert e.code == "invalid_argument"
echo "binding checks passed"

# A trusted callback must receive a stable rejection, never deadlock while
# attempting a call or close on the client currently invoking it.
var reentrantClient: Client
var rejectedCall = false
var rejectedClose = false
proc reentrantBinding(ctx: pointer; output: cstring; capacity: csize_t): cint {.cdecl, raises: [].} =
  if reentrantClient != nil:
    try:
      discard reentrantClient.status()
    except LicenseboxError as e:
      rejectedCall = e.code == "invalid_argument"
    except: discard
    try:
      reentrantClient.close()
    except LicenseboxError as e:
      rejectedClose = e.code == "invalid_argument"
    except: discard
  1
reentrantClient = newClient(%*{"product":"demo", "keys":{"k":"A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg"}, "directory":"build/reentry-state"}, Callbacks(machineBinding: reentrantBinding))
try:
  discard reentrantClient.signIn(0.01)
  assert false
except LicenseboxError as e: assert e.code == "identity_unavailable"
assert rejectedCall and rejectedClose
reentrantClient.close()
reentrantClient = nil
echo "callback reentry checks passed"
