## Linux binding to the maintained Licensebox C core. Returned JSON values own
## their memory. Clients are reference objects: aliases share close state.
import std/[json, rlocks, strutils]

type
  LicenseboxError* = object of CatchableError
    code*: string
  SignInCallback* = proc(context: pointer; url, code: cstring) {.cdecl, raises: [].}
  ClockCallback* = proc(context: pointer): cdouble {.cdecl, raises: [].}
  BindingCallback* = proc(context: pointer; output: cstring; capacity: csize_t): cint {.cdecl, raises: [].}
  CancelledCallback* = proc(context: pointer): cint {.cdecl, raises: [].}
  Callbacks* {.bycopy.} = object
    context*: pointer
    onSignIn*: SignInCallback
    clock*: ClockCallback
    machineBinding*: BindingCallback
    cancelled*: CancelledCallback
  ClientObj = object
    handle: pointer
    mutex: RLock
    busy: bool
    callbacks: Callbacks
  Client* = ref ClientObj

{.passL: "-llicensebox".}
proc createNative(options: cstring; cb: ptr Callbacks; output: ptr pointer): cint {.cdecl, importc: "lb_client_create_json".}
proc callNative(h: pointer; op, args: cstring; output: ptr cstring): cint {.cdecl, importc: "lb_client_call_json".}
proc destroyNative(h: pointer) {.cdecl, importc: "lb_client_destroy".}
proc freeNative(p: pointer) {.cdecl, importc: "lb_free".}
proc resultCode(r: cint): cstring {.cdecl, importc: "lb_result_code".}
proc errorCode(h: pointer): cstring {.cdecl, importc: "lb_error_code".}
proc errorMessage(h: pointer): cstring {.cdecl, importc: "lb_error_message".}
proc deriveNative(product, source, raw: cstring; output: cstring; capacity: csize_t): cint {.cdecl, importc: "lb_derive_binding".}
proc bindingNative(product, output: cstring; capacity: csize_t): cint {.cdecl, importc: "lb_native_binding".}
proc verifyNative(token, product, keys: cstring; now: cdouble; output: ptr cstring): cint {.cdecl, importc: "lb_verify_lease_json".}

proc fail(code, message: string) {.noreturn.} =
  var e = newException(LicenseboxError, message)
  e.code = code
  raise e
proc valid(s: string): string =
  if '\0' in s: fail("invalid_argument", "NUL in argument")
  s
proc check(r: cint; h: pointer = nil) =
  if r == 0: return
  var code = $resultCode(r)
  var message = code
  if h != nil and code != "invalid_argument":
    let saved = $errorCode(h)
    if saved != "ok": code = saved
    message = $errorMessage(h)
  fail(code, message)
proc owned(p: cstring): JsonNode =
  if p == nil: fail("protocol_error", "missing native result")
  try: result = parseJson($p)
  finally: freeNative(p)
proc `=destroy`(self: var ClientObj) =
  if self.handle != nil: destroyNative(self.handle)
  deinitRLock(self.mutex)
proc newClient*(options: JsonNode; callbacks = Callbacks()): Client =
  ## callbacks.context is borrowed and must outlive this client; callbacks must
  ## not raise or reenter. Clock/binding callbacks are trusted test/platform seams.
  new(result)
  initRLock(result.mutex)
  result.callbacks = callbacks
  check(createNative(($options).cstring, addr result.callbacks, addr result.handle))
proc close*(self: Client) =
  acquire(self.mutex)
  defer: release(self.mutex)
  if self.busy: fail("invalid_argument", "callback reentry")
  if self.handle != nil:
    destroyNative(self.handle)
    self.handle = nil
proc call*(self: Client; operation: string; args = newJObject()): JsonNode =
  discard valid(operation)
  acquire(self.mutex)
  defer: release(self.mutex)
  if self.handle == nil or self.busy: fail("invalid_argument", "closed client or callback reentry")
  self.busy = true
  defer: self.busy = false
  var p: cstring
  let code = callNative(self.handle, operation.cstring, ($args).cstring, addr p)
  if code != 0:
    freeNative(p)
    check(code, self.handle)
  owned(p)
proc lease*(self: Client): JsonNode = self.call("lease")
proc requireModule*(self: Client; name: string): JsonNode = self.call("require", %*{"module": valid(name)})
proc heartbeat*(self: Client; name: string): JsonNode = self.call("heartbeat", %*{"module": valid(name)})
proc status*(self: Client): JsonNode = self.call("status")
proc signIn*(self: Client; timeout = 0.0): JsonNode = self.call("sign_in", %*{"timeout": timeout})
proc logout*(self: Client) = discard self.call("logout")
proc modules*(self: Client): JsonNode = self.call("modules")
proc requests*(self: Client): JsonNode = self.call("requests")
proc requestAccess*(self: Client; names: seq[string]; note = ""): JsonNode = self.call("request", %*{"modules": names, "note": valid(note)})
proc accessLink*(self: Client): string = self.call("access-link").getStr
proc recordUsage*(self: Client; command: string; success: bool; elapsed: float) = discard self.call("record", %*{"command": valid(command), "success": success, "elapsed": elapsed})
proc deriveBinding*(product, source, rawId: string): string =
  discard valid(product); discard valid(source)
  let raw = rawId.strip(leading=false, trailing=true, chars={'\0'})
  if '\0' in raw: fail("identity_unavailable", "invalid identifier")
  var output: array[128, char]
  check(deriveNative(product.cstring, source.cstring, raw.cstring, cast[cstring](addr output[0]), 128))
  $cast[cstring](addr output[0])
proc nativeBinding*(product: string): string =
  discard valid(product)
  var output: array[128, char]
  check(bindingNative(product.cstring, cast[cstring](addr output[0]), 128))
  $cast[cstring](addr output[0])
proc verifyLease*(token, product: string; keys: JsonNode; now: float): JsonNode =
  discard valid(token); discard valid(product)
  var p: cstring
  let code = verifyNative(token.cstring, product.cstring, ($keys).cstring, now, addr p)
  if code != 0:
    freeNative(p)
    check(code)
  owned(p)
