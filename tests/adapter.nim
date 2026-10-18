import std/json
import licensebox
var request: JsonNode
proc clockCb(ctx: pointer): cdouble {.cdecl, raises: [].} =
  try: request["now"].getFloat
  except: 0.0
proc bindingCb(ctx: pointer; output: cstring; capacity: csize_t): cint {.cdecl, raises: [].} =
  try:
    let value = request["binding"].getStr
    if value.len >= int(capacity): return 1
    copyMem(output, value.cstring, value.len + 1)
    return 0
  except: return 1
proc signinCb(ctx: pointer; url, code: cstring) {.cdecl, raises: [].} = discard
proc run(r: JsonNode): JsonNode =
  let op = r["op"].getStr
  let product = r["product"].getStr
  case op
  of "derive": return %deriveBinding(product, r["source"].getStr, r["raw_id"].getStr)
  of "native": return %nativeBinding(product)
  of "verify": return verifyLease(r["token"].getStr, product, r["keys"], r["now"].getFloat)
  else: discard
  var options = %*{"product": product, "keys": r["keys"], "server": r["server"], "directory": r["directory"], "version": "conformance"}
  if r.hasKey("ca_bundle"): options["ca_bundle"] = r["ca_bundle"]
  var callbacks = Callbacks(clock: clockCb, onSignIn: signinCb)
  if r.hasKey("binding"): callbacks.machineBinding = bindingCb
  let client = newClient(options, callbacks)
  defer: client.close()
  case op
  of "require": client.requireModule(if r.hasKey("module"): r["module"].getStr else: "core")
  of "heartbeat", "heartbeat-repeat", "heartbeat-after-require":
    let name = if r.hasKey("module"): r["module"].getStr else: "core"
    if op == "heartbeat-after-require": discard client.requireModule("core")
    if op == "heartbeat-repeat": discard client.heartbeat(name)
    client.heartbeat(name)
  of "repeat":
    discard client.requireModule("core")
    client.requireModule("core")
  of "sign_in": client.signIn(3)
  of "request": client.requestAccess(@["export"], "café – test")
  of "record":
    client.recordUsage("export", true, 0.125)
    client.recordUsage("export", false, 0.025)
    newJNull()
  else: client.call(op)
request = parseJson(stdin.readAll())
try: echo $(%*{"ok": true, "value": run(request)})
except LicenseboxError as e: echo $(%*{"ok": false, "error": e.code})
